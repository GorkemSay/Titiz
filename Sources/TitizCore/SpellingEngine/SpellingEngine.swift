import Foundation

/// Deterministic, high-precision Turkish spelling and punctuation engine (Phase 5).
public struct SpellingEngine: Sendable {
    private static let abbreviationWords: Set<String> = [
        "dr", "prof", "av", "doç", "uzm", "yrd", "müh", "alb", "org", "gen",
        "vb", "vs", "bkz", "örn", "yy", "sf", "no", "tel", "apt", "mah", "cad", "sok"
    ]

    private static let openingBracketOrQuote: Set<String> = [
        "\"", "'", "“", "‘", "(", "[", "{"
    ]

    private static let sentenceEndingPunctuation: Set<String> = [
        ".", "!", "?", "…"
    ]

    private static let clauseBoundaryPunctuation: Set<String> = [
        ",", ";", ":", "—", "–"
    ]

    private static let clauseBoundaryConjunctions: Set<String> = [
        "ama", "fakat", "ancak", "lakin", "çünkü", "cunku"
    ]

    private static let standaloneQuestionOperators: Set<String> = [
        "mi", "mı", "mu", "mü",
        "miyim", "mıyım", "muyum", "müyüm",
        "misin", "mısın", "musun", "müsün",
        "miyiz", "mıyız", "muyuz", "müyüz",
        "misiniz", "mısınız", "musunuz", "müsünüz",
        "miydi", "mıydı", "muydu", "müydü",
        "miydim", "mıydım", "muydum", "müydüm",
        "miydin", "mıydın", "muydun", "müydün",
        "miydik", "mıydık", "muyduk", "müydük",
        "miydiniz", "mıydınız", "muydunuz", "müydünüz",
        "miymiş", "mıymış", "muymuş", "müymüş", "miymis", "muymus",
        "miyse", "mıysa", "muysa", "müyse",
        "midir", "mıdır", "mudur", "müdür",
        "ne", "nasıl", "nasil", "neden", "niye", "niçin", "nicin",
        "kim", "kimi", "kime", "kimde", "kimden", "kimin",
        "nerede", "nereye", "nereden", "nere",
        "hangi", "hangisi",
        "kaç", "kac", "kaçıncı", "kacinci", "kaça", "kaca"
    ]

    private let dictionary: HunspellDictionary
    private let gpaScorer: GPAScorer
    private let englishWordlist: EnglishWordlist
    private let frequencyTable: TurkishFrequencyTable
    private let ruleCatalog: SpellingRuleCatalog

    public init(
        dictionary: HunspellDictionary,
        gpaScorer: GPAScorer,
        englishWordlist: EnglishWordlist,
        frequencyTable: TurkishFrequencyTable,
        ruleCatalog: SpellingRuleCatalog
    ) {
        self.dictionary = dictionary
        self.gpaScorer = gpaScorer
        self.englishWordlist = englishWordlist
        self.frequencyTable = frequencyTable
        self.ruleCatalog = ruleCatalog
    }

    /// Runs deterministic spelling and punctuation rules over `document`.
    /// When `enableJointDeasciify` is `true` (Combined mode), fused ASCII clitics and compounds
    /// are split and deasciified jointly while avoiding destructive rewrites on uncertain Character edits.
    public func process(
        _ document: AnalyzedDocument,
        enableJointDeasciify: Bool = false,
        priorCharacterEdits: [Int: Edit] = [:]
    ) -> CorrectionResult {
        let tokens = document.tokens
        let normalizedText = document.normalized.text
        let spacingPlan = PunctuationSpacer.planSpacing(in: tokens)

        var wordReplacements: [Int: (replacement: String, ruleID: String, confidence: Double)] = [:]

        for index in tokens.indices {
            let token = tokens[index]
            guard !token.isProtected else { continue }

            // Guard against stacking destructive spelling splits on uncertain Character Bucket 2 edits.
            let priorCharEdit = priorCharacterEdits[index]
            let isUncertainPriorEdit = priorCharEdit?.bucket == .bucket2 && (priorCharEdit?.confidence ?? 1.0) < 0.90

            switch token.kind {
            case .word:
                if !isUncertainPriorEdit {
                    if let closedFix = ruleCatalog.closedFix(
                        for: token.text,
                        includeASCIIJointVariants: enableJointDeasciify
                    ) {
                        let rendered = applySentenceStartIfNeeded(
                            closedFix.replacement,
                            at: index,
                            in: tokens
                        )
                        wordReplacements[index] = (rendered, closedFix.ruleID, 0.99)
                        continue
                    }

                    let qContext = questionContext(at: index, in: tokens)
                    if let cliticSplit = QuestionCliticSplitter.splitIfApplicable(
                        word: token.text,
                        inSentence: normalizedText,
                        wordRange: token.range,
                        questionContext: qContext,
                        enableJointDeasciify: enableJointDeasciify,
                        dictionary: dictionary,
                        gpaScorer: gpaScorer,
                        englishWordlist: englishWordlist,
                        frequencyTable: frequencyTable
                    ) {
                        let rendered = applySentenceStartIfNeeded(
                            cliticSplit.replacement,
                            at: index,
                            in: tokens
                        )
                        let resolvedRuleID = priorCharEdit != nil ? "spell.joint.question_clitic" : cliticSplit.ruleID
                        wordReplacements[index] = (rendered, resolvedRuleID, 0.96)
                        continue
                    }
                }

                // Sentence-start capitalization using `tr_TR` locale (respecting abbreviations & protected tokens).
                if isAtSentenceStart(index: index, in: tokens),
                   shouldCapitalizeSentenceStartWord(token.text) {
                    let capitalized = TurkishLocale.capitalizedFirstCharacter(token.text)
                    if capitalized != token.text {
                        wordReplacements[index] = (capitalized, "spell.capitalization.sentence_start", 0.98)
                    }
                }

            case let .apostropheWord(wordStem, apostrophe, suffix):
                // ForeignSuffixGuard keeps suffix untouched; sentence-start capitalization applies only to the stem.
                if isAtSentenceStart(index: index, in: tokens),
                   shouldCapitalizeSentenceStartWord(wordStem) {
                    let capitalizedStem = TurkishLocale.capitalizedFirstCharacter(wordStem)
                    if capitalizedStem != wordStem {
                        wordReplacements[index] = (
                            capitalizedStem + String(apostrophe) + suffix,
                            "spell.capitalization.sentence_start",
                            0.98
                        )
                    }
                }

            case .punctuation, .whitespace, .protectedSpan:
                break
            }
        }

        // Reassemble final text and compute exact UTF-16 edit ranges against `document.normalized.original`.
        var correctedText = String()
        correctedText.reserveCapacity(normalizedText.utf8.count + 16)
        var correctedUTF16Cursor = 0
        var edits: [Edit] = []

        var index = 0
        while index < tokens.count {
            // Merge `dropLeadingWhitespace` on punctuation cleanly with the whitespace + punctuation tokens.
            if index + 1 < tokens.count,
               tokens[index].kind == .whitespace,
               spacingPlan[index + 1]?.dropLeadingWhitespace == true {
                let wsToken = tokens[index]
                let punctToken = tokens[index + 1]
                let trailingSpace = spacingPlan[index + 1]?.insertTrailingSpace == true ? " " : ""

                let origSpan = UTF16Range(
                    location: wsToken.utf16Range.location,
                    length: wsToken.utf16Range.length + punctToken.utf16Range.length
                )
                let origRange = document.normalized.originalUTF16Range(for: origSpan)
                let replacement = punctToken.text + trailingSpace
                let correctedRange = UTF16Range(
                    location: correctedUTF16Cursor,
                    length: replacement.utf16.count
                )

                let originalSlice = wsToken.text + punctToken.text
                edits.append(
                    Edit(
                        origin: .spelling,
                        ruleID: "spell.punctuation.space_before",
                        bucket: nil,
                        confidence: 0.99,
                        original: originalSlice,
                        replacement: replacement,
                        alternatives: [],
                        originalRange: origRange,
                        correctedRange: correctedRange
                    )
                )

                correctedText.append(replacement)
                correctedUTF16Cursor += replacement.utf16.count
                index += 2
                continue
            }

            let token = tokens[index]

            if let spacing = spacingPlan[index], spacing.insertTrailingSpace {
                let replacement = token.text + " "
                let origRange = document.normalized.originalUTF16Range(for: token.utf16Range)
                let correctedRange = UTF16Range(
                    location: correctedUTF16Cursor,
                    length: replacement.utf16.count
                )

                edits.append(
                    Edit(
                        origin: .spelling,
                        ruleID: "spell.punctuation.space_after",
                        bucket: nil,
                        confidence: 0.99,
                        original: token.text,
                        replacement: replacement,
                        alternatives: [],
                        originalRange: origRange,
                        correctedRange: correctedRange
                    )
                )

                correctedText.append(replacement)
                correctedUTF16Cursor += replacement.utf16.count
                index += 1
                continue
            }

            if let rewrite = wordReplacements[index] {
                let origRange = document.normalized.originalUTF16Range(for: token.utf16Range)
                let correctedRange = UTF16Range(
                    location: correctedUTF16Cursor,
                    length: rewrite.replacement.utf16.count
                )

                edits.append(
                    Edit(
                        origin: .spelling,
                        ruleID: rewrite.ruleID,
                        bucket: nil,
                        confidence: rewrite.confidence,
                        original: token.text,
                        replacement: rewrite.replacement,
                        alternatives: [],
                        originalRange: origRange,
                        correctedRange: correctedRange
                    )
                )

                correctedText.append(rewrite.replacement)
                correctedUTF16Cursor += rewrite.replacement.utf16.count
                index += 1
                continue
            }

            correctedText.append(token.text)
            correctedUTF16Cursor += token.utf16Range.length
            index += 1
        }

        return CorrectionResult(
            originalText: document.normalized.original,
            correctedText: correctedText,
            mode: enableJointDeasciify ? .combined : .spelling,
            edits: edits,
            ambiguousSuggestions: []
        )
    }

    // MARK: - Sentence Start & Capitalization Helpers

    private func isAtSentenceStart(index: Int, in tokens: [Token]) -> Bool {
        var cursor = index - 1
        var newlineCount = 0

        while cursor >= 0 {
            let tok = tokens[cursor]
            switch tok.kind {
            case .whitespace:
                if tok.text.contains(where: \.isNewline) {
                    newlineCount += 1
                    if newlineCount >= 2 {
                        return true
                    }
                }
                cursor -= 1
            case .punctuation:
                if Self.openingBracketOrQuote.contains(tok.text) {
                    // Skip an opening quote/bracket only when directly hugging the candidate word
                    // (do not cross closing quotes such as `"Bitti." ve`).
                    if cursor + 1 < tokens.count, tokens[cursor + 1].kind != .whitespace {
                        cursor -= 1
                        continue
                    }
                    return false
                }
                guard Self.sentenceEndingPunctuation.contains(tok.text) else {
                    return false
                }
                // Ellipsis `...` ends a sentence; abbreviation periods (`Dr.`, `vb.`) do not.
                if tok.text == "." && isAbbreviationPeriod(at: cursor, in: tokens) {
                    return false
                }
                return true
            case .word, .apostropheWord, .protectedSpan:
                return false
            }
        }
        return true
    }

    private func questionContext(at index: Int, in tokens: [Token]) -> QuestionCliticSplitter.QuestionContext {
        let immediatelyFollowedByQuestionMark: Bool = {
            var cursor = index + 1
            while cursor < tokens.count {
                let tok = tokens[cursor]
                if tok.kind == .whitespace {
                    if tok.text.contains(where: \.isNewline) {
                        return false
                    }
                    cursor += 1
                    continue
                }
                return tok.kind == .punctuation && tok.text == "?"
            }
            return false
        }()

        let clauseEndsWithQuestionMark: Bool = {
            if immediatelyFollowedByQuestionMark {
                return true
            }
            var cursor = index + 1
            while cursor < tokens.count {
                let tok = tokens[cursor]
                if tok.kind == .whitespace, tok.text.contains(where: \.isNewline) {
                    return false
                }
                if tok.kind == .punctuation, Self.sentenceEndingPunctuation.contains(tok.text) {
                    if tok.text == "." && isAbbreviationPeriod(at: cursor, in: tokens) {
                        cursor += 1
                        continue
                    }
                    return tok.text == "?"
                }
                cursor += 1
            }
            return false
        }()

        guard clauseEndsWithQuestionMark else {
            return QuestionCliticSplitter.QuestionContext(
                immediatelyFollowedByQuestionMark: immediatelyFollowedByQuestionMark,
                clauseEndsWithQuestionMark: false,
                clauseHasOtherQuestionOperator: false
            )
        }

        let clauseHasOtherQuestionOperator =
            hasQuestionOperator(startingAt: index - 1, step: -1, in: tokens) ||
            hasQuestionOperator(startingAt: index + 1, step: 1, in: tokens)

        return QuestionCliticSplitter.QuestionContext(
            immediatelyFollowedByQuestionMark: immediatelyFollowedByQuestionMark,
            clauseEndsWithQuestionMark: true,
            clauseHasOtherQuestionOperator: clauseHasOtherQuestionOperator
        )
    }

    private func hasQuestionOperator(startingAt startIndex: Int, step: Int, in tokens: [Token]) -> Bool {
        var cursor = startIndex
        while cursor >= 0 && cursor < tokens.count {
            let tok = tokens[cursor]
            switch tok.kind {
            case .whitespace:
                if tok.text.contains(where: \.isNewline) {
                    return false
                }
            case .punctuation:
                if Self.clauseBoundaryPunctuation.contains(tok.text) {
                    return false
                }
                if Self.sentenceEndingPunctuation.contains(tok.text),
                   !(tok.text == "." && isAbbreviationPeriod(at: cursor, in: tokens)) {
                    return false
                }
            case .word:
                let lower = TurkishLocale.lowercased(tok.text)
                if Self.clauseBoundaryConjunctions.contains(lower) {
                    return false
                }
                if Self.standaloneQuestionOperators.contains(lower) {
                    return true
                }
            case .apostropheWord, .protectedSpan:
                break
            }
            cursor += step
        }
        return false
    }

    private func isAbbreviationPeriod(at periodIndex: Int, in tokens: [Token]) -> Bool {
        guard periodIndex >= 1 else { return false }
        let prev = tokens[periodIndex - 1]
        guard prev.kind == .word else { return false }

        let lowered = TurkishLocale.lowercased(prev.text)
        return Self.abbreviationWords.contains(lowered)
    }

    private func shouldCapitalizeSentenceStartWord(_ word: String) -> Bool {
        guard let first = word.first, first.isLetter, first.isLowercase else {
            return false
        }
        // Only capitalize words whose tail is lowercase (avoid breaking iPhone/macOS-style identifiers).
        guard word.dropFirst().allSatisfy({ $0.isLowercase || !$0.isLetter }) else {
            return false
        }
        // Capitalize if it is a valid Turkish dictionary form (e.g. `istanbul`, `son`) or not a lowercase English-only word.
        if CandidateGenerator.isValidTurkishWord(word, dictionary: dictionary) {
            return true
        }
        return !englishWordlist.contains(word)
    }

    private func applySentenceStartIfNeeded(_ replacement: String, at index: Int, in tokens: [Token]) -> String {
        guard isAtSentenceStart(index: index, in: tokens),
              let first = replacement.first,
              first.isLowercase else {
            return replacement
        }
        return TurkishLocale.capitalizedFirstCharacter(replacement)
    }
}
