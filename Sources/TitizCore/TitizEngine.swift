import CHunspell
import Foundation

/// Pure Swift, deterministic Turkish proofreading engine.
public struct TitizEngine: Sendable {
    /// Semantic development version of the TitizCore engine.
    public static let version = "0.1.0-dev"

    /// Version string exposed by the underlying `CHunspell` bridge.
    public static var hunspellBridgeVersion: String {
        String(cString: chunspell_bridge_version())
    }

    public let resources: TitizResources
    public let personalDictionaryStore: PersonalDictionaryStore
    private let characterEngine: CharacterEngine
    private let spellingEngine: SpellingEngine

    public init(
        resources: TitizResources = .shared,
        personalDictionaryStore: PersonalDictionaryStore = PersonalDictionaryStore(),
        characterConfig: CharacterEngineConfiguration = .default
    ) {
        self.resources = resources
        self.personalDictionaryStore = personalDictionaryStore
        self.characterEngine = CharacterEngine(
            dictionary: resources.dictionary,
            gpaScorer: resources.gpaScorer,
            englishWordlist: resources.englishWordlist,
            frequencyTable: resources.frequencyTable,
            config: characterConfig
        )
        self.spellingEngine = SpellingEngine(
            dictionary: resources.dictionary,
            gpaScorer: resources.gpaScorer,
            englishWordlist: resources.englishWordlist,
            frequencyTable: resources.frequencyTable,
            ruleCatalog: resources.ruleCatalog
        )
    }

    /// Runs UTF-8 NFC normalization, structural lexing, and 4-tier proper-noun protection (Tier 0–3).
    public func analyze(_ text: String, additionalPersonalTerms: [String] = []) -> AnalyzedDocument {
        let snapshot = makeEffectiveSnapshot(additionalPersonalTerms: additionalPersonalTerms)
        return analyze(text, personalSnapshot: snapshot)
    }

    /// Processes input text under the specified correction mode.
    public func correct(
        _ text: String,
        mode: CorrectionMode = .combined,
        additionalPersonalTerms: [String] = []
    ) -> CorrectionResult {
        let snapshot = makeEffectiveSnapshot(additionalPersonalTerms: additionalPersonalTerms)
        let analyzed = analyze(text, personalSnapshot: snapshot)

        switch mode {
        case .character:
            return characterEngine.process(analyzed)
        case .spelling:
            return spellingEngine.process(analyzed, enableJointDeasciify: false)
        case .combined:
            let charResult = characterEngine.process(analyzed)
            if charResult.edits.isEmpty {
                let spellOnly = spellingEngine.process(analyzed, enableJointDeasciify: true)
                return CorrectionResult(
                    originalText: charResult.originalText,
                    correctedText: spellOnly.correctedText,
                    mode: .combined,
                    edits: spellOnly.edits,
                    ambiguousSuggestions: charResult.ambiguousSuggestions
                )
            }

            let intermediateDoc = analyze(charResult.correctedText, personalSnapshot: snapshot)
            let priorEditsByToken = mapPriorEdits(charResult.edits, onto: intermediateDoc.tokens)
            let spellResult = spellingEngine.process(
                intermediateDoc,
                enableJointDeasciify: true,
                priorCharacterEdits: priorEditsByToken
            )

            let mergedEdits = mergeCombinedEdits(
                characterEdits: charResult.edits,
                spellingEdits: spellResult.edits,
                normalized: analyzed.normalized
            )

            return CorrectionResult(
                originalText: charResult.originalText,
                correctedText: spellResult.correctedText,
                mode: .combined,
                edits: mergedEdits,
                ambiguousSuggestions: charResult.ambiguousSuggestions
            )
        }
    }

    // MARK: - Private Pipeline Helpers

    private func makeEffectiveSnapshot(additionalPersonalTerms: [String]) -> PersonalDictionarySnapshot {
        let baseSnapshot = personalDictionaryStore.snapshot
        guard !additionalPersonalTerms.isEmpty else {
            return baseSnapshot
        }
        let extraEntries = additionalPersonalTerms.map { PersonalDictionaryEntry(term: $0, isCaseSensitive: true) }
        return PersonalDictionarySnapshot(entries: baseSnapshot.entries + extraEntries)
    }

    private func analyze(_ text: String, personalSnapshot: PersonalDictionarySnapshot) -> AnalyzedDocument {
        let normalized = TextNormalizer.normalize(text)
        let lexed = StructuralLexer.tokenize(normalized)
        let tier0Protected = Tier0Protector.apply(to: lexed)
        let protectedTokens = ProperNounProtector.apply(
            to: tier0Protected,
            personalDictionary: personalSnapshot,
            gazetteer: resources.gazetteer,
            englishWordlist: resources.englishWordlist,
            dictionary: resources.dictionary
        )
        return AnalyzedDocument(normalized: normalized, tokens: protectedTokens)
    }

    private func mapPriorEdits(_ edits: [Edit], onto tokens: [Token]) -> [Int: Edit] {
        guard !edits.isEmpty else { return [:] }
        var map: [Int: Edit] = [:]
        for edit in edits {
            let rStart = edit.correctedRange.location
            let rEnd = edit.correctedRange.location + edit.correctedRange.length
            for idx in tokens.indices {
                let tokRange = tokens[idx].utf16Range
                let tStart = tokRange.location
                let tEnd = tokRange.location + tokRange.length
                if rStart >= tStart && rEnd <= tEnd {
                    map[idx] = edit
                    break
                }
            }
        }
        return map
    }

    private func mergeCombinedEdits(
        characterEdits: [Edit],
        spellingEdits: [Edit],
        normalized: NormalizedText
    ) -> [Edit] {
        guard !spellingEdits.isEmpty else { return characterEdits }
        guard !characterEdits.isEmpty else { return spellingEdits }

        var merged: [Edit] = []
        merged.reserveCapacity(characterEdits.count + spellingEdits.count)

        var consumedCharIndices: Set<Int> = []
        var overlappingPairs: [Int: Edit] = [:]

        for spellEdit in spellingEdits {
            let sMidStart = spellEdit.originalRange.location
            let sMidEnd = sMidStart + spellEdit.originalRange.length

            if let charIdx = characterEdits.firstIndex(where: { charEdit in
                let cMidStart = charEdit.correctedRange.location
                let cMidEnd = cMidStart + charEdit.correctedRange.length
                return sMidStart < cMidEnd && cMidStart < sMidEnd
            }) {
                consumedCharIndices.insert(charIdx)
                overlappingPairs[charIdx] = spellEdit
            } else {
                // Pure spelling edit: project originalRange from intermediate charResult back to NFC normalized text,
                // then map through NormalizedText back to NFD originalText.
                var charNormDeltaBefore = 0
                for charEdit in characterEdits {
                    let cMidEnd = charEdit.correctedRange.location + charEdit.correctedRange.length
                    if cMidEnd <= sMidStart {
                        // `charEdit.original` is the NFC token stem inside `normalized.text`.
                        charNormDeltaBefore += (charEdit.correctedRange.length - charEdit.original.utf16.count)
                    }
                }
                let normOrigRange = UTF16Range(
                    location: spellEdit.originalRange.location - charNormDeltaBefore,
                    length: spellEdit.originalRange.length
                )
                let projectedOrigRange = normalized.originalUTF16Range(for: normOrigRange)
                merged.append(
                    Edit(
                        id: spellEdit.id,
                        origin: spellEdit.origin,
                        ruleID: spellEdit.ruleID,
                        bucket: spellEdit.bucket,
                        confidence: spellEdit.confidence,
                        original: spellEdit.original,
                        replacement: spellEdit.replacement,
                        alternatives: spellEdit.alternatives,
                        originalRange: projectedOrigRange,
                        correctedRange: spellEdit.correctedRange
                    )
                )
            }
        }

        for (charIdx, charEdit) in characterEdits.enumerated() {
            if let spellEdit = overlappingPairs[charIdx] {
                // Both stages touched the same token (e.g. `yarin` -> `yarın` -> `Yarın`): unify cleanly.
                let prefixLen = spellEdit.originalRange.location - charEdit.correctedRange.location
                let suffixStart = (charEdit.correctedRange.location + charEdit.correctedRange.length)
                let spellEnd = spellEdit.originalRange.location + spellEdit.originalRange.length
                let replacement: String
                if prefixLen == 0 && spellEnd == suffixStart {
                    replacement = spellEdit.replacement
                } else {
                    replacement = spellEdit.replacement
                }
                merged.append(
                    Edit(
                        id: charEdit.id,
                        origin: charEdit.origin,
                        ruleID: "\(charEdit.ruleID)+\(spellEdit.ruleID)",
                        bucket: charEdit.bucket,
                        confidence: min(charEdit.confidence, spellEdit.confidence),
                        original: charEdit.original,
                        replacement: replacement,
                        alternatives: charEdit.alternatives,
                        originalRange: charEdit.originalRange,
                        correctedRange: spellEdit.correctedRange
                    )
                )
            } else if !consumedCharIndices.contains(charIdx) {
                // Pure character edit: project correctedRange forward into final text.
                let cMidStart = charEdit.correctedRange.location
                var spellDeltaBefore = 0
                for spellEdit in spellingEdits {
                    let sMidEnd = spellEdit.originalRange.location + spellEdit.originalRange.length
                    if sMidEnd <= cMidStart {
                        spellDeltaBefore += (spellEdit.correctedRange.length - spellEdit.originalRange.length)
                    }
                }
                let projectedCorrectedRange = UTF16Range(
                    location: charEdit.correctedRange.location + spellDeltaBefore,
                    length: charEdit.correctedRange.length
                )
                merged.append(
                    Edit(
                        id: charEdit.id,
                        origin: charEdit.origin,
                        ruleID: charEdit.ruleID,
                        bucket: charEdit.bucket,
                        confidence: charEdit.confidence,
                        original: charEdit.original,
                        replacement: charEdit.replacement,
                        alternatives: charEdit.alternatives,
                        originalRange: charEdit.originalRange,
                        correctedRange: projectedCorrectedRange
                    )
                )
            }
        }

        return merged.sorted { lhs, rhs in
            if lhs.originalRange.location != rhs.originalRange.location {
                return lhs.originalRange.location < rhs.originalRange.location
            }
            return lhs.correctedRange.location < rhs.correctedRange.location
        }
    }
}
