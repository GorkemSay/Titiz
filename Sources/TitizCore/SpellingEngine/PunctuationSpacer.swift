import Foundation

/// Fixes unambiguous Turkish punctuation spacing mistakes over typed `StructuralLexer` tokens:
/// removes horizontal whitespace directly before `? ! , . ; :` and inserts a single space after
/// them when directly glued onto an adjacent word/span (protecting URLs, decimals, times, quotes, and `...`).
public enum PunctuationSpacer {
    public struct TokenSpacingRewrite: Sendable, Equatable {
        public let dropLeadingWhitespace: Bool
        public let insertTrailingSpace: Bool

        public init(dropLeadingWhitespace: Bool = false, insertTrailingSpace: Bool = false) {
            self.dropLeadingWhitespace = dropLeadingWhitespace
            self.insertTrailingSpace = insertTrailingSpace
        }
    }

    private static let targetPunctuation: Set<String> = ["?", "!", ",", ".", ";", ":"]
    private static let closingDelimiters: Set<String> = ["\"", "'", "”", "’", ")", "]", "}"]
    private static let unambiguousOpeningDelimiters: Set<String> = ["(", "[", "{", "“", "‘"]

    /// Computes spacing actions keyed by punctuation token index in `tokens`.
    public static func planSpacing(in tokens: [Token]) -> [Int: TokenSpacingRewrite] {
        var plan: [Int: TokenSpacingRewrite] = [:]

        for index in tokens.indices {
            let token = tokens[index]
            guard token.kind == .punctuation, targetPunctuation.contains(token.text) else {
                continue
            }

            let dropBefore = shouldDropWhitespaceBefore(punctuationAt: index, in: tokens)
            let insertAfter = shouldInsertSpaceAfter(punctuationAt: index, in: tokens)

            if dropBefore || insertAfter {
                plan[index] = TokenSpacingRewrite(
                    dropLeadingWhitespace: dropBefore,
                    insertTrailingSpace: insertAfter
                )
            }
        }

        return plan
    }

    // MARK: - Private Rules

    private static func shouldDropWhitespaceBefore(punctuationAt index: Int, in tokens: [Token]) -> Bool {
        guard index >= 2 else { return false }

        let ws = tokens[index - 1]
        guard ws.kind == .whitespace, !ws.text.contains(where: \.isNewline) else {
            return false
        }

        let beforeWS = tokens[index - 2]
        switch beforeWS.kind {
        case .word, .apostropheWord, .protectedSpan:
            return true
        case .punctuation:
            return closingDelimiters.contains(beforeWS.text)
        case .whitespace:
            return false
        }
    }

    private static func shouldInsertSpaceAfter(punctuationAt index: Int, in tokens: [Token]) -> Bool {
        guard index + 1 < tokens.count else { return false }

        let next = tokens[index + 1]
        switch next.kind {
        case .word, .apostropheWord, .protectedSpan:
            // Preserve compact single-letter dot abbreviations such as `e.g.` or `a.m.` if unspaced.
            if tokens[index].text == ".",
               index >= 1,
               tokens[index - 1].kind == .word,
               tokens[index - 1].text.count == 1,
               tokens[index - 1].text.first?.isLowercase == true,
               next.kind == .word,
               next.text.count == 1,
               next.text.first?.isLowercase == true {
                return false
            }
            return true
        case .punctuation:
            // Insert space before unambiguous opening brackets/quotes (`(`, `[`, `{`, `“`, `‘`),
            // while never splitting `...`, `?!`, `."`, or `.)`.
            return unambiguousOpeningDelimiters.contains(next.text)
        case .whitespace:
            return false
        }
    }
}
