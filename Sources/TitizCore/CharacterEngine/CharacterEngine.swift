import Foundation

/// Tunable, principled scoring parameters for the Phase 3 3-Bucket Character Engine.
public struct CharacterEngineConfiguration: Sendable, Equatable {
    public let bigramWeight: Double
    public let gpaWeight: Double
    /// Minimum score margin required to replace a valid Turkish original with another Turkish candidate.
    public let originalValidOverrideThreshold: Double
    /// Minimum score separation above the runner-up Turkish candidate when overriding a valid original.
    public let runnerUpMargin: Double
    /// Minimum score separation required when an ASCII original collides with the English wordlist.
    public let englishCollisionMargin: Double
    /// Minimum unigram log10 probability for a replacement overriding an English wordlist collision.
    public let englishCollisionMinUnigramLog10: Double

    public static let `default` = CharacterEngineConfiguration(
        bigramWeight: 1.85,
        gpaWeight: 1.10,
        originalValidOverrideThreshold: 2.00,
        runnerUpMargin: 0.45,
        englishCollisionMargin: 1.00,
        englishCollisionMinUnigramLog10: -6.0
    )

    public init(
        bigramWeight: Double,
        gpaWeight: Double,
        originalValidOverrideThreshold: Double,
        runnerUpMargin: Double,
        englishCollisionMargin: Double,
        englishCollisionMinUnigramLog10: Double
    ) {
        self.bigramWeight = bigramWeight
        self.gpaWeight = gpaWeight
        self.originalValidOverrideThreshold = originalValidOverrideThreshold
        self.runnerUpMargin = runnerUpMargin
        self.englishCollisionMargin = englishCollisionMargin
        self.englishCollisionMinUnigramLog10 = englishCollisionMinUnigramLog10
    }
}

/// Pure Swift 3-bucket Turkish diacritic restoration engine.
///
/// Guarantees strict one-way ASCII-to-diacritic restoration: already-present Turkish diacritics
/// (`ç, ğ, ı, İ, ö, ş, ü`) and protected spans are never altered.
public struct CharacterEngine: Sendable {
    private let dictionary: HunspellDictionary
    private let gpaScorer: GPAScorer
    private let englishWordlist: EnglishWordlist
    private let frequencyTable: TurkishFrequencyTable
    private let config: CharacterEngineConfiguration

    public init(
        dictionary: HunspellDictionary,
        gpaScorer: GPAScorer,
        englishWordlist: EnglishWordlist,
        frequencyTable: TurkishFrequencyTable,
        config: CharacterEngineConfiguration = .default
    ) {
        self.dictionary = dictionary
        self.gpaScorer = gpaScorer
        self.englishWordlist = englishWordlist
        self.frequencyTable = frequencyTable
        self.config = config
    }

    private struct PendingBucket2Item {
        let tokenIndex: Int
        let stem: String
        let result: CandidateGenerationResult
        let predictions: [GPACharPrediction]
    }

    private struct AppliedEditDraft {
        let origin: EditOrigin
        let ruleID: String
        let bucket: CharacterBucket
        let confidence: Double
        let originalStem: String
        let replacementStem: String
        let alternatives: [String]
    }

    /// Runs two-pass Bucket 0 / 1 / 2 character restoration on `document`.
    public func process(_ document: AnalyzedDocument) -> CorrectionResult {
        let tokens = document.tokens
        let normalizedText = document.normalized.text

        var updatedStems: [Int: String] = [:]
        var appliedDrafts: [Int: AppliedEditDraft] = [:]
        var pendingBucket2: [PendingBucket2Item] = []
        var intraDocCache: [String: CandidateGenerationResult] = [:]

        // Pass 1: Evaluate all eligible unprotected tokens; apply Bucket 1 immediately so Pass 2
        // sees restored neighboring Turkish words for bigram disambiguation.
        for index in tokens.indices {
            let token = tokens[index]
            guard !token.isProtected else { continue }

            let stem: String
            switch token.kind {
            case .word:
                stem = token.text
            case let .apostropheWord(wordStem, _, _):
                stem = wordStem
            case .punctuation, .whitespace, .protectedSpan:
                continue
            }

            let stemEnd = normalizedText.index(token.range.lowerBound, offsetBy: stem.count)
            let stemRange = token.range.lowerBound..<stemEnd
            let predictions = gpaScorer.predictions(for: stem, inSentence: normalizedText, wordRange: stemRange)

            let genResult: CandidateGenerationResult
            if let cached = intraDocCache[stem] {
                genResult = cached
            } else {
                let computed = CandidateGenerator.generate(
                    for: stem,
                    gpaPredictions: predictions,
                    dictionary: dictionary
                )
                if computed.mutableCount <= 7 {
                    intraDocCache[stem] = computed
                }
                genResult = computed
            }

            // Bucket 0: 0 valid Turkish alternatives -> leave untouched.
            guard !genResult.validAlternatives.isEmpty else {
                continue
            }

            let collidesWithEnglish = englishWordlist.contains(stem)
                || englishWordlist.containsForeignStemWithTurkishSuffix(stem)

            // Bucket 1: original invalid, exactly 1 valid Turkish candidate, and not an English collision.
            if !genResult.originalIsValid && genResult.validAlternatives.count == 1 && !collidesWithEnglish {
                let replacement = genResult.validAlternatives[0]
                updatedStems[index] = replacement
                appliedDrafts[index] = AppliedEditDraft(
                    origin: .character,
                    ruleID: "char.bucket1",
                    bucket: .bucket1,
                    confidence: 1.0,
                    originalStem: stem,
                    replacementStem: replacement,
                    alternatives: []
                )
            } else {
                pendingBucket2.append(
                    PendingBucket2Item(
                        tokenIndex: index,
                        stem: stem,
                        result: genResult,
                        predictions: predictions
                    )
                )
            }
        }

        // Pass 2: Disambiguate Bucket 2 candidates using Pass-1-restored neighbors + frequency + GPA.
        var pendingSuggestions: [Int: [String]] = [:]

        for item in pendingBucket2 {
            let tokenIdx = item.tokenIndex
            let prevWord = neighborStem(before: tokenIdx, in: tokens, updatedStems: updatedStems)
            let nextWord = neighborStem(after: tokenIdx, in: tokens, updatedStems: updatedStems)

            let candidateList = [item.stem] + item.result.validAlternatives
            let scoredCandidates: [(candidate: String, score: Double)] = candidateList.map { cand in
                let uni = frequencyTable.unigramLog10(cand)
                let biPrev = prevWord.map { frequencyTable.pmiBoost(previous: $0, current: cand) } ?? 0.0
                let biNext = nextWord.map { frequencyTable.pmiBoost(previous: cand, current: $0) } ?? 0.0
                let gpaAgree = gpaScorer.agreementScore(
                    candidate: cand,
                    original: item.stem,
                    predictions: item.predictions
                )
                let total = uni + config.bigramWeight * (biPrev + biNext) + config.gpaWeight * gpaAgree
                return (cand, total)
            }

            let origScore = scoredCandidates[0].score
            let rankedAlternatives = scoredCandidates.dropFirst().sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.candidate < rhs.candidate
            }

            guard let bestAlt = rankedAlternatives.first else { continue }
            let secondScore = rankedAlternatives.count > 1 ? rankedAlternatives[1].score : -Double.greatestFiniteMagnitude

            let isEnglishWord = englishWordlist.contains(item.stem)
                || englishWordlist.containsForeignStemWithTurkishSuffix(item.stem)
            var shouldApply = false
            var computedConfidence = 0.0

            if isEnglishWord && !item.result.originalIsValid {
                let hasForeignContext = isForeignContextWord(prevWord) || isForeignContextWord(nextWord)
                let hasTurkishContext = isTurkishContextWord(prevWord) || isTurkishContextWord(nextWord)
                let bestUni = frequencyTable.unigramLog10(bestAlt.candidate)

                if !hasForeignContext && hasTurkishContext {
                    let marginOverRunnerUp = bestAlt.score - secondScore
                    let marginOverOrig = bestAlt.score - origScore
                    if marginOverOrig >= config.englishCollisionMargin,
                       marginOverRunnerUp >= config.runnerUpMargin,
                       bestUni >= config.englishCollisionMinUnigramLog10 {
                        shouldApply = true
                        computedConfidence = sigmoidConfidence(marginOverOrig - config.englishCollisionMargin + 1.0)
                    }
                }
            } else if item.result.originalIsValid {
                let marginOverOrig = bestAlt.score - origScore
                let marginOverRunnerUp = bestAlt.score - secondScore
                if marginOverOrig >= config.originalValidOverrideThreshold,
                   marginOverRunnerUp >= config.runnerUpMargin {
                    shouldApply = true
                    computedConfidence = sigmoidConfidence(marginOverOrig - config.originalValidOverrideThreshold + 0.8)
                }
            } else {
                // Original invalid, 2+ valid Turkish candidates, not in English wordlist
                let marginOverRunnerUp = bestAlt.score - secondScore
                if marginOverRunnerUp >= config.runnerUpMargin {
                    shouldApply = true
                    computedConfidence = sigmoidConfidence(marginOverRunnerUp + 0.6)
                }
            }

            if shouldApply {
                updatedStems[tokenIdx] = bestAlt.candidate
                let alts = rankedAlternatives.dropFirst().map(\.candidate) + [item.stem]
                appliedDrafts[tokenIdx] = AppliedEditDraft(
                    origin: .character,
                    ruleID: "char.bucket2",
                    bucket: .bucket2,
                    confidence: computedConfidence,
                    originalStem: item.stem,
                    replacementStem: bestAlt.candidate,
                    alternatives: alts
                )
            } else {
                pendingSuggestions[tokenIdx] = rankedAlternatives.map(\.candidate)
            }
        }

        // Reassemble correctedText and build exact UTF-16 ranges for edits and ambiguous suggestions.
        var correctedText = String()
        correctedText.reserveCapacity(normalizedText.utf8.count + 16)
        var correctedUTF16Cursor = 0

        var edits: [Edit] = []
        var ambiguousSuggestions: [AmbiguousTokenSuggestion] = []

        for index in tokens.indices {
            let token = tokens[index]
            let stemUTF16Length: Int
            let renderedText: String

            switch token.kind {
            case .word:
                stemUTF16Length = token.utf16Range.length
                renderedText = updatedStems[index] ?? token.text
            case let .apostropheWord(wordStem, apostrophe, suffix):
                stemUTF16Length = wordStem.utf16.count
                let finalStem = updatedStems[index] ?? wordStem
                renderedText = finalStem + String(apostrophe) + suffix
            case .punctuation, .whitespace, .protectedSpan:
                stemUTF16Length = token.utf16Range.length
                renderedText = token.text
            }

            let normStemRange = UTF16Range(location: token.utf16Range.location, length: stemUTF16Length)
            let origStemRange = document.normalized.originalUTF16Range(for: normStemRange)

            if let draft = appliedDrafts[index] {
                let correctedStemRange = UTF16Range(
                    location: correctedUTF16Cursor,
                    length: draft.replacementStem.utf16.count
                )
                edits.append(
                    Edit(
                        origin: draft.origin,
                        ruleID: draft.ruleID,
                        bucket: draft.bucket,
                        confidence: draft.confidence,
                        original: draft.originalStem,
                        replacement: draft.replacementStem,
                        alternatives: draft.alternatives,
                        originalRange: origStemRange,
                        correctedRange: correctedStemRange
                    )
                )
            } else if let candidates = pendingSuggestions[index] {
                ambiguousSuggestions.append(
                    AmbiguousTokenSuggestion(
                        original: token.stemText,
                        originalRange: origStemRange,
                        candidates: candidates
                    )
                )
            }

            correctedText.append(renderedText)
            correctedUTF16Cursor += renderedText.utf16.count
        }

        return CorrectionResult(
            originalText: document.normalized.original,
            correctedText: correctedText,
            mode: .character,
            edits: edits,
            ambiguousSuggestions: ambiguousSuggestions
        )
    }

    // MARK: - Private Context Helpers

    private func neighborStem(
        before index: Int,
        in tokens: [Token],
        updatedStems: [Int: String]
    ) -> String? {
        var cursor = index - 1
        while cursor >= 0 {
            let tok = tokens[cursor]
            switch tok.kind {
            case .whitespace:
                if tok.text.contains(where: \.isNewline) { return nil }
                cursor -= 1
            case .punctuation:
                if ".!?;:\"".contains(tok.text) { return nil }
                cursor -= 1
            case .word, .apostropheWord:
                return updatedStems[cursor] ?? tok.stemText
            case .protectedSpan:
                return nil
            }
        }
        return nil
    }

    private func neighborStem(
        after index: Int,
        in tokens: [Token],
        updatedStems: [Int: String]
    ) -> String? {
        var cursor = index + 1
        while cursor < tokens.count {
            let tok = tokens[cursor]
            switch tok.kind {
            case .whitespace:
                if tok.text.contains(where: \.isNewline) { return nil }
                cursor += 1
            case .punctuation:
                if ".!?;:\"".contains(tok.text) { return nil }
                cursor += 1
            case .word, .apostropheWord:
                return updatedStems[cursor] ?? tok.stemText
            case .protectedSpan:
                return nil
            }
        }
        return nil
    }

    private func isForeignContextWord(_ word: String?) -> Bool {
        guard let word else { return false }
        return englishWordlist.contains(word) && !CandidateGenerator.isValidTurkishWord(word, dictionary: dictionary)
    }

    private func isTurkishContextWord(_ word: String?) -> Bool {
        guard let word else { return false }
        if TurkishLocale.containsTurkishDiacritic(word) {
            return CandidateGenerator.isValidTurkishWord(word, dictionary: dictionary)
        }
        return CandidateGenerator.isValidTurkishWord(word, dictionary: dictionary) && !englishWordlist.contains(word)
    }

    private func sigmoidConfidence(_ margin: Double) -> Double {
        let value = 1.0 / (1.0 + exp(-margin))
        return min(max(value, 0.5), 0.99)
    }
}
