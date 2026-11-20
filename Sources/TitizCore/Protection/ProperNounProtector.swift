import Foundation

/// Applies 4-tier proper-noun protection after Tier 0 structural lexing:
/// Precedence: Tier 1 (Personal Dictionary) -> Tier 3 (Multi-Word Trie) -> Tier 2A (Non-Colliding) -> Tier 2B (Context-Aware Colliding).
public enum ProperNounProtector {
    private static let followingTitleCues: Set<String> = [
        "Bey", "Hanım", "Hanim", "Hoca", "Usta", "Abi", "Abla", "Kaptan",
        "Başkan", "Baskan", "Bakan", "Müdür", "Mudur", "Efendi", "Paşa", "Pasa",
        "Dr", "Prof", "Av", "Müh", "Muh"
    ]

    private static let precedingTitleCues: Set<String> = [
        "Sayın", "Sayin", "Bay", "Bayan", "Dr", "Prof", "Av", "Doç", "Doc", "Uzm"
    ]

    private static let categoryCuePrefixes: [String] = [
        "film", "dizi", "oyun", "kitab", "kitap", "roman", "şarkı", "sarki", "albüm", "album",
        "şirket", "sirket", "firma", "ekib", "ekip", "grup", "grub", "takım", "takim",
        "dil", "platform", "uygulama", "servis", "marka", "mağaza", "magaza", "kütüphane", "kutuphane",
        "havaliman", "üniversite", "universite", "meydan", "cadde", "bulvar", "köprü", "kopru",
        "kule", "müze", "muze", "ilçe", "ilce"
    ]

    private static let exactCategoryCues: Set<String> = [
        "ili", "iline", "ilinde", "ilinden", "eyaleti", "eyaletinde"
    ]

    private static let openingBracketOrQuote: Set<String> = [
        "\"", "'", "“", "‘", "(", "[", "{"
    ]

    private static let sentenceEndingPunctuation: Set<String> = [
        ".", "!", "?", "…"
    ]

    /// Applies Tier 1, Tier 3, Tier 2A, and Tier 2B annotations in exact precedence order.
    public static func apply(
        to tokens: [Token],
        personalDictionary: PersonalDictionarySnapshot,
        gazetteer: EntityGazetteer,
        englishWordlist: EnglishWordlist,
        dictionary: HunspellDictionary
    ) -> [Token] {
        var result = tokens

        // 1. Tier 1: Personal Dictionary (single & multi-word; highest entity precedence).
        personalDictionary.apply(to: &result)

        // 2. Tier 3: Multi-word entities matched before single-word Tier 2.
        gazetteer.tier3Trie.apply(
            to: &result,
            tier: .tier3MultiWordEntity,
            reasonPrefix: "Multi-word entity (Tier 3)",
            overrideExistingEntityOrWordTier0: false
        )

        // 3. Tier 2A & Tier 2B: Single-word entities (plus uncatalogued foreign apostrophe stems).
        for index in result.indices {
            guard result[index].protection == nil else { continue }

            let stem: String
            let isApostrophe: Bool

            switch result[index].kind {
            case .word:
                stem = result[index].text
                isApostrophe = false
            case let .apostropheWord(wordStem, _, _):
                stem = wordStem
                isApostrophe = true
            case .punctuation, .whitespace, .protectedSpan:
                continue
            }

            if gazetteer.tier2A.contains(stem) {
                result[index].protection = ProtectionInfo(
                    tier: .tier2ANonCollidingEntity,
                    reason: "Non-colliding proper noun (Tier 2A)",
                    structuralKind: nil
                )
                continue
            }

            if let first = stem.first, first.isUppercase,
               gazetteer.tier2B.contains(stem),
               hasTier2BContext(at: index, in: result, isApostrophe: isApostrophe) {
                result[index].protection = ProtectionInfo(
                    tier: .tier2BCollidingEntity,
                    reason: "Colliding entity with proper-noun context (Tier 2B)",
                    structuralKind: nil
                )
                continue
            }

            // Additional foreign-stem apostrophe protection (e.g. Docker'da, driver'a) when clearly English
            // and not an ordinary Turkish word.
            if isApostrophe,
               ForeignSuffixGuard.shouldPreserveSuffix(
                   for: result[index],
                   englishWordlist: englishWordlist,
                   dictionary: dictionary
               ) {
                result[index].protection = ProtectionInfo(
                    tier: .tier2BCollidingEntity,
                    reason: "Foreign stem with Turkish apostrophe suffix",
                    structuralKind: nil
                )
            }
        }

        return result
    }

    // MARK: - Tier 2B Context Detection

    private static func hasTier2BContext(
        at index: Int,
        in tokens: [Token],
        isApostrophe: Bool
    ) -> Bool {
        if isApostrophe {
            return true
        }

        if hasAdjacentEntityCue(at: index, in: tokens) {
            return true
        }

        return !isAtSentenceStart(at: index, in: tokens)
    }

    private static func isAtSentenceStart(at index: Int, in tokens: [Token]) -> Bool {
        var cursor = index - 1
        while cursor >= 0 {
            let tok = tokens[cursor]
            switch tok.kind {
            case .whitespace:
                if tok.text.contains(where: \.isNewline) {
                    return true
                }
                cursor -= 1
            case .punctuation:
                if openingBracketOrQuote.contains(tok.text) {
                    cursor -= 1
                    continue
                }
                return sentenceEndingPunctuation.contains(tok.text)
            case .word, .apostropheWord, .protectedSpan:
                return false
            }
        }
        return true
    }

    private static func hasAdjacentEntityCue(at index: Int, in tokens: [Token]) -> Bool {
        if let nextWord = nextWordToken(after: index, in: tokens) {
            let stem = nextWord.stemText
            if followingTitleCues.contains(stem) || isCategoryCueWord(stem) {
                return true
            }
        }

        if let prevCue = previousCueWord(before: index, in: tokens) {
            if precedingTitleCues.contains(prevCue) {
                return true
            }
        }

        return false
    }

    private static func nextWordToken(after index: Int, in tokens: [Token]) -> Token? {
        var cursor = index + 1
        while cursor < tokens.count {
            let tok = tokens[cursor]
            switch tok.kind {
            case .whitespace:
                if tok.text.contains(where: \.isNewline) { return nil }
                cursor += 1
            case .punctuation:
                return nil
            case .word, .apostropheWord:
                return tok
            case .protectedSpan:
                return nil
            }
        }
        return nil
    }

    private static func previousCueWord(before index: Int, in tokens: [Token]) -> String? {
        var cursor = index - 1
        while cursor >= 0 {
            let tok = tokens[cursor]
            switch tok.kind {
            case .whitespace:
                if tok.text.contains(where: \.isNewline) { return nil }
                cursor -= 1
            case .punctuation:
                if tok.text == "." {
                    // Handles abbreviations such as `Dr. Can` or `Prof. Deniz`.
                    cursor -= 1
                    continue
                }
                return nil
            case .word, .apostropheWord:
                return tok.stemText
            case .protectedSpan:
                return nil
            }
        }
        return nil
    }

    private static func isCategoryCueWord(_ word: String) -> Bool {
        let lower = TurkishLocale.lowercased(word)
        if exactCategoryCues.contains(lower) {
            return true
        }
        for prefix in categoryCuePrefixes where lower.hasPrefix(prefix) {
            // Keep length tight so unrelated long derivatives are not over-matched.
            if lower.count <= prefix.count + 6 {
                return true
            }
        }
        return false
    }
}
