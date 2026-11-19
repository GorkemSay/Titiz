import Foundation
import Testing
@testable import TitizCore

@Suite("TurkishLocale & TextNormalizer")
struct TextNormalizerAndLocaleTests {
    @Test("TurkishLocale handles İ/I/ı/i case conversions without stray U+0307")
    func turkishCaseConversions() {
        #expect(TurkishLocale.lowercased("İSTANBUL") == "istanbul")
        #expect(TurkishLocale.lowercased("ISPARTA") == "ısparta")
        #expect(TurkishLocale.lowercased("İ") == "i")
        #expect(TurkishLocale.lowercased("I") == "ı")

        // NFD I + U+0307 must fold to plain ASCII "i", never leaving a combining dot above
        let nfdCapital = "I\u{0307}STANBUL"
        let lowered = TurkishLocale.lowercased(nfdCapital)
        #expect(lowered == "istanbul")
        #expect(!lowered.unicodeScalars.contains("\u{0307}"))
        #expect(lowered.utf8.elementsEqual("istanbul".utf8))

        #expect(TurkishLocale.uppercased("istanbul") == "İSTANBUL")
        #expect(TurkishLocale.uppercased("ısparta") == "ISPARTA")
        #expect(TurkishLocale.uppercased("i") == "İ")
        #expect(TurkishLocale.uppercased("ı") == "I")
    }

    @Test("TurkishLocale capitalizes first character and folds diacritics cleanly")
    func capitalizeAndAsciiFold() {
        #expect(TurkishLocale.capitalizedFirstCharacter("iyi günler") == "İyi günler")
        #expect(TurkishLocale.capitalizedFirstCharacter("ısparta") == "Isparta")
        #expect(TurkishLocale.capitalizedFirstCharacter("") == "")

        #expect(TurkishLocale.containsTurkishDiacritic("yarın"))
        #expect(TurkishLocale.containsTurkishDiacritic("İstanbul"))
        #expect(!TurkishLocale.containsTurkishDiacritic("Intel"))

        #expect(TurkishLocale.asciiFolded("Çğıİöşü ÇĞIİÖŞÜ") == "CgiIosu CGIIOSU")
    }

    @Test("TextNormalizer detects already-NFC fast path vs NFD byte differences")
    func nfcDetectionAndMapping() {
        let alreadyNFC = "İstanbul'da yağmur yağıyor."
        let fastNormalized = TextNormalizer.normalize(alreadyNFC)
        #expect(fastNormalized.wasAlreadyNFC)
        #expect(fastNormalized.text.utf8.elementsEqual(alreadyNFC.utf8))

        // NFD input: I + combining dot above, g + combining breve, emoji surrogate pair (😀 = 2 UTF-16 units)
        let nfdInput = "I\u{0307}stanbul 😀 yag\u{0306}mur"
        let normalized = TextNormalizer.normalize(nfdInput)
        let expectedNFC = "İstanbul 😀 yağmur"

        #expect(!normalized.wasAlreadyNFC)
        #expect(normalized.text.utf8.elementsEqual(expectedNFC.utf8))

        // Verify range mapping for "yağmur" after NFD and surrogate-pair emoji
        let wordRange = normalized.text.range(of: "yağmur")!
        let origRange = normalized.originalRange(for: wordRange)
        #expect(String(nfdInput[origRange]) == "yag\u{0306}mur")

        let origUTF16 = normalized.originalUTF16Range(for: normalized.normalizedUTF16Range(for: wordRange))
        #expect(origUTF16 == UTF16Range(location: 13, length: 7))

        // Verify range mapping for "İstanbul"
        let cityRange = normalized.text.range(of: "İstanbul")!
        let origCityRange = normalized.originalRange(for: cityRange)
        #expect(String(nfdInput[origCityRange]) == "I\u{0307}stanbul")
    }
}
