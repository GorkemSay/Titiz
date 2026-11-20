import Foundation

/// Longest-match token trie for multi-word entities (Tier 3 and multi-word Tier 1 entries).
/// Tokenizes phrases with `StructuralLexer` so spacing and punctuation align losslessly.
public struct MultiWordEntityTrie: Sendable, Equatable {
    private final class Node: @unchecked Sendable, Equatable {
        var children: [String: Node] = [:]
        var matchedPhrase: String?

        static func == (lhs: Node, rhs: Node) -> Bool {
            lhs.matchedPhrase == rhs.matchedPhrase && lhs.children == rhs.children
        }
    }

    private let root = Node()
    public let caseSensitive: Bool
    public let phraseCount: Int

    public var isEmpty: Bool {
        phraseCount == 0
    }

    public init(phrases: [String], caseSensitive: Bool = true) {
        self.caseSensitive = caseSensitive
        var inserted = 0

        for rawPhrase in phrases {
            let trimmed = rawPhrase.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let phraseTokens = StructuralLexer.tokenize(TextNormalizer.normalize(trimmed))
                .filter { $0.kind != .whitespace }
            guard phraseTokens.count >= 2 else { continue }

            var current = root
            for token in phraseTokens {
                let key = Self.key(for: token.stemText, caseSensitive: caseSensitive)
                if let next = current.children[key] {
                    current = next
                } else {
                    let next = Node()
                    current.children[key] = next
                    current = next
                }
            }
            if current.matchedPhrase == nil {
                current.matchedPhrase = trimmed
                inserted += 1
            }
        }

        self.phraseCount = inserted
    }

    /// Scans `tokens` left-to-right, annotating the longest multi-word entity match at each position.
    public func apply(
        to tokens: inout [Token],
        tier: ProtectionTier,
        reasonPrefix: String,
        overrideExistingEntityOrWordTier0: Bool = false
    ) {
        guard !isEmpty else { return }

        var index = 0
        while index < tokens.count {
            let startToken = tokens[index]
            guard case .word = startToken.kind else {
                index += 1
                continue
            }

            if !overrideExistingEntityOrWordTier0 && startToken.isProtected {
                index += 1
                continue
            }

            if let match = longestMatch(startingAt: index, in: tokens) {
                for pos in index...match.endTokenIndex {
                    let tok = tokens[pos]
                    guard tok.kind != .whitespace else { continue }
                    if case .protectedSpan = tok.kind { continue }

                    if overrideExistingEntityOrWordTier0 {
                        // Tier 1 Personal Dictionary always takes precedence over Tier 2/3 and word-level Tier 0.
                        tokens[pos].protection = ProtectionInfo(
                            tier: tier,
                            reason: "\(reasonPrefix): \(match.phrase)",
                            structuralKind: tokens[pos].protection?.structuralKind
                        )
                    } else if tokens[pos].protection == nil {
                        tokens[pos].protection = ProtectionInfo(
                            tier: tier,
                            reason: "\(reasonPrefix): \(match.phrase)",
                            structuralKind: nil
                        )
                    }
                }
                index = match.endTokenIndex + 1
            } else {
                index += 1
            }
        }
    }

    // MARK: - Private Matching

    private func longestMatch(
        startingAt startIndex: Int,
        in tokens: [Token]
    ) -> (endTokenIndex: Int, phrase: String)? {
        var currentNode = root
        var cursor = startIndex
        var bestEndIndex: Int?
        var bestPhrase: String?

        while cursor < tokens.count {
            let token = tokens[cursor]

            if token.kind == .whitespace {
                if token.text.contains(where: \.isNewline) {
                    break
                }
                cursor += 1
                continue
            }

            let matchKey: String
            let isTerminalOnlyToken: Bool

            switch token.kind {
            case .word:
                matchKey = Self.key(for: token.text, caseSensitive: caseSensitive)
                isTerminalOnlyToken = false
            case let .apostropheWord(stem, _, _):
                // Apostrophe-inflected words are permitted only as the final word of a multi-word entity.
                matchKey = Self.key(for: stem, caseSensitive: caseSensitive)
                isTerminalOnlyToken = true
            case .punctuation:
                matchKey = token.text
                isTerminalOnlyToken = false
            case .whitespace, .protectedSpan:
                return bestEndIndex.flatMap { endIdx in bestPhrase.map { (endIdx, $0) } }
            }

            guard let nextNode = currentNode.children[matchKey] else {
                break
            }
            currentNode = nextNode

            if let phrase = currentNode.matchedPhrase {
                bestEndIndex = cursor
                bestPhrase = phrase
            }

            if isTerminalOnlyToken {
                break
            }

            cursor += 1
        }

        guard let bestEndIndex, let bestPhrase else {
            return nil
        }
        return (bestEndIndex, bestPhrase)
    }

    private static func key(for text: String, caseSensitive: Bool) -> String {
        let nfc = text.precomposedStringWithCanonicalMapping
        return caseSensitive ? nfc : TurkishLocale.lowercased(nfc)
    }
}
