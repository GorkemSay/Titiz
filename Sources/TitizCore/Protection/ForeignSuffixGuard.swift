import Foundation

/// Enforces the foreign-stem apostrophe suffix invariant:
/// suffixes attached to protected entities or foreign English stems (`Apple'da`, `iPhone'u`, `GitHub'ta`)
/// reflect pronunciation rather than written Turkish vowel harmony and must never be auto-mutated.
public enum ForeignSuffixGuard {
    /// Returns `true` if the token is an apostrophe-inflected word whose suffix must remain untouched
    /// by diacritic restoration, vowel harmonization, or spelling rules.
    public static func shouldPreserveSuffix(
        for token: Token,
        englishWordlist: EnglishWordlist,
        dictionary: HunspellDictionary
    ) -> Bool {
        guard case let .apostropheWord(stem, _, _) = token.kind else {
            return false
        }

        if token.isProtected {
            return true
        }

        if englishWordlist.contains(stem) {
            let lowered = TurkishLocale.lowercased(stem)
            if !dictionary.contains(lowered, assumeNFC: true) {
                return true
            }
        }

        return false
    }
}
