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
    }

    /// Runs UTF-8 NFC normalization, structural lexing, and 4-tier proper-noun protection (Tier 0–3).
    public func analyze(_ text: String, additionalPersonalTerms: [String] = []) -> AnalyzedDocument {
        let normalized = TextNormalizer.normalize(text)
        let lexed = StructuralLexer.tokenize(normalized)
        let tier0Protected = Tier0Protector.apply(to: lexed)

        let baseSnapshot = personalDictionaryStore.snapshot
        let effectiveSnapshot: PersonalDictionarySnapshot
        if additionalPersonalTerms.isEmpty {
            effectiveSnapshot = baseSnapshot
        } else {
            let extraEntries = additionalPersonalTerms.map { PersonalDictionaryEntry(term: $0, isCaseSensitive: true) }
            effectiveSnapshot = PersonalDictionarySnapshot(entries: baseSnapshot.entries + extraEntries)
        }

        let protectedTokens = ProperNounProtector.apply(
            to: tier0Protected,
            personalDictionary: effectiveSnapshot,
            gazetteer: resources.gazetteer,
            englishWordlist: resources.englishWordlist,
            dictionary: resources.dictionary
        )
        return AnalyzedDocument(normalized: normalized, tokens: protectedTokens)
    }

    /// Processes input text under the specified correction mode.
    public func correct(
        _ text: String,
        mode: CorrectionMode = .combined,
        additionalPersonalTerms: [String] = []
    ) -> CorrectionResult {
        let analyzed = analyze(text, additionalPersonalTerms: additionalPersonalTerms)

        switch mode {
        case .character:
            return characterEngine.process(analyzed)
        case .spelling:
            // Deterministic TDK spelling & punctuation rules arrive in Phase 5.
            return CorrectionResult(
                originalText: analyzed.normalized.original,
                correctedText: analyzed.normalized.original,
                mode: .spelling
            )
        case .combined:
            // Phase 5 adds Spelling + Joint split-and-deasciify.
            let charResult = characterEngine.process(analyzed)
            return CorrectionResult(
                originalText: charResult.originalText,
                correctedText: charResult.correctedText,
                mode: .combined,
                edits: charResult.edits,
                ambiguousSuggestions: charResult.ambiguousSuggestions
            )
        }
    }
}
