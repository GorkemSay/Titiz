import Foundation

/// Turkish-aware string case conversion and diacritic utilities using `Locale(identifier: "tr_TR")`.
public enum TurkishLocale {
    public static let locale = Locale(identifier: "tr_TR")

    private static let turkishDiacritics: Set<Character> = [
        "ç", "Ç", "ğ", "Ğ", "ı", "İ", "ö", "Ö", "ş", "Ş", "ü", "Ü"
    ]

    /// Lowercases text using `tr_TR` locale rules (`İ → i`, `I → ı`) and guarantees NFC output.
    public static func lowercased(_ string: String) -> String {
        let nfc = string.precomposedStringWithCanonicalMapping
        return nfc.lowercased(with: locale).precomposedStringWithCanonicalMapping
    }

    /// Uppercases text using `tr_TR` locale rules (`i → İ`, `ı → I`) and guarantees NFC output.
    public static func uppercased(_ string: String) -> String {
        let nfc = string.precomposedStringWithCanonicalMapping
        return nfc.uppercased(with: locale).precomposedStringWithCanonicalMapping
    }

    /// Uppercases only the first grapheme cluster using `tr_TR` locale rules, leaving the rest untouched.
    public static func capitalizedFirstCharacter(_ string: String) -> String {
        let nfc = string.precomposedStringWithCanonicalMapping
        guard let first = nfc.first else {
            return ""
        }
        return uppercased(String(first)) + nfc.dropFirst()
    }

    /// Returns `true` if the string contains any Turkish-specific diacritic character (`ç, ğ, ı, İ, ö, ş, ü`).
    public static func containsTurkishDiacritic(_ string: String) -> Bool {
        string.precomposedStringWithCanonicalMapping.contains { turkishDiacritics.contains($0) }
    }

    /// Folds Turkish-specific diacritics to their ASCII base characters while preserving case.
    public static func asciiFolded(_ string: String) -> String {
        let nfc = string.precomposedStringWithCanonicalMapping
        var result = String()
        result.reserveCapacity(nfc.utf8.count)

        for character in nfc {
            switch character {
            case "ç": result.append("c")
            case "Ç": result.append("C")
            case "ğ": result.append("g")
            case "Ğ": result.append("G")
            case "ı": result.append("i")
            case "İ": result.append("I")
            case "ö": result.append("o")
            case "Ö": result.append("O")
            case "ş": result.append("s")
            case "Ş": result.append("S")
            case "ü": result.append("u")
            case "Ü": result.append("U")
            default: result.append(character)
            }
        }

        return result
    }
}
