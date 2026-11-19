import Foundation

/// Applies Tier 0 structural protection to lexical tokens:
/// ALL-CAPS acronyms, CamelCase/PascalCase/digit-mixed/underscore identifiers,
/// numeric/version stems, and short quoted UI labels.
public enum Tier0Protector {
    private static let uiLabelConnectors: Set<String> = [
        "de", "da", "ve", "ile", "of", "to", "in", "on", "as", "or", "the", "for", "and"
    ]

    private static let quotePairs: [String: String] = [
        "\"": "\"",
        "'": "'",
        "“": "”",
        "‘": "’"
    ]

    /// Returns tokens annotated with Tier 0 structural `ProtectionInfo` where applicable.
    public static func apply(to tokens: [Token]) -> [Token] {
        var result = tokens

        for index in result.indices where result[index].protection == nil {
            let token = result[index]
            switch token.kind {
            case .word, .apostropheWord:
                let stem = token.stemText
                if isNumericOrVersionStem(stem) {
                    result[index].protection = ProtectionInfo(
                        tier: .tier0Structural,
                        reason: "Numeric or version stem",
                        structuralKind: .numericOrVersion
                    )
                } else if isAllCapsAcronym(stem) {
                    result[index].protection = ProtectionInfo(
                        tier: .tier0Structural,
                        reason: "ALL-CAPS acronym",
                        structuralKind: .allCapsAcronym
                    )
                } else if isCamelOrMixedIdentifier(stem) {
                    result[index].protection = ProtectionInfo(
                        tier: .tier0Structural,
                        reason: "CamelCase, underscore, or digit-mixed identifier",
                        structuralKind: .camelOrMixedIdentifier
                    )
                }
            case .punctuation, .whitespace, .protectedSpan:
                break
            }
        }

        applyQuotedUILabels(to: &result)
        return result
    }

    private static func isNumericOrVersionStem(_ stem: String) -> Bool {
        guard let first = stem.first else {
            return false
        }
        if first.isNumber && stem.allSatisfy({ $0.isNumber || $0 == "." || $0 == "," || $0 == ":" }) {
            return true
        }
        return false
    }

    private static func isAllCapsAcronym(_ stem: String) -> Bool {
        guard stem.count >= 2 else {
            return false
        }
        return stem.allSatisfy { $0.isLetter && $0.isUppercase && !$0.isLowercase }
    }

    private static func isCamelOrMixedIdentifier(_ stem: String) -> Bool {
        guard !stem.isEmpty else {
            return false
        }

        let hasLetter = stem.contains(where: \.isLetter)
        let hasDigit = stem.contains(where: \.isNumber)
        if hasLetter && hasDigit {
            return true
        }

        if stem.contains("_") {
            return true
        }

        let chars = Array(stem)
        // Lowercase followed by uppercase (e.g. iOS, macOS, MaviKutu, GitHub)
        for index in 0..<(chars.count - 1) {
            if chars[index].isLowercase && chars[index + 1].isUppercase {
                return true
            }
        }

        // Two or more uppercase letters followed by a lowercase letter (e.g. NSStatusItem, URLSession)
        if chars.count >= 3 {
            for index in 0..<(chars.count - 2) {
                if chars[index].isUppercase && chars[index + 1].isUppercase && chars[index + 2].isLowercase {
                    return true
                }
            }
        }

        return false
    }

    private static func applyQuotedUILabels(to tokens: inout [Token]) {
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            guard token.kind == .punctuation, let closingQuote = quotePairs[token.text] else {
                index += 1
                continue
            }

            if let closeIndex = findClosingQuote(
                in: tokens,
                from: index + 1,
                closingQuote: closingQuote
            ) {
                if isShortUILabelSpan(tokens[(index + 1)..<closeIndex]) {
                    for innerIndex in (index + 1)..<closeIndex {
                        switch tokens[innerIndex].kind {
                        case .word, .apostropheWord:
                            if tokens[innerIndex].protection == nil {
                                tokens[innerIndex].protection = ProtectionInfo(
                                    tier: .tier0Structural,
                                    reason: "Quoted UI label",
                                    structuralKind: .quotedUILabel
                                )
                            }
                        case .punctuation, .whitespace, .protectedSpan:
                            break
                        }
                    }
                }
                index = closeIndex + 1
            } else {
                index += 1
            }
        }
    }

    private static func findClosingQuote(
        in tokens: [Token],
        from startIndex: Int,
        closingQuote: String
    ) -> Int? {
        for index in startIndex..<tokens.count {
            let candidate = tokens[index]
            if candidate.kind == .whitespace, candidate.text.contains(where: \.isNewline) {
                return nil
            }
            if candidate.kind == .punctuation, candidate.text == closingQuote {
                return index
            }
        }
        return nil
    }

    private static func isShortUILabelSpan(_ span: ArraySlice<Token>) -> Bool {
        var wordTokens: [Token] = []

        for token in span {
            switch token.kind {
            case .word, .apostropheWord:
                wordTokens.append(token)
            case .whitespace:
                if token.text.contains(where: \.isNewline) {
                    return false
                }
            case .punctuation, .protectedSpan:
                return false
            }
        }

        guard (1...3).contains(wordTokens.count) else {
            return false
        }

        guard let firstChar = wordTokens[0].stemText.first, firstChar.isUppercase else {
            return false
        }

        return wordTokens.allSatisfy { token in
            let stem = token.stemText
            if let first = stem.first, first.isUppercase {
                return true
            }
            return uiLabelConnectors.contains(TurkishLocale.lowercased(stem))
        }
    }
}
