import Foundation
import Testing
@testable import TitizCore

@Suite("CharacterEngine & Disambiguator")
struct CharacterEngineTests {
    private static let engine = TitizEngine(resources: .shared)

    @Test("GPAScorer loads all 6 decision lists and preserves one-way polarity")
    func gpaScorerPolarityAndOneWay() {
        let gpa = TitizResources.shared.gpaScorer

        #expect(gpa.patternCount(for: "c") == 2547)
        #expect(gpa.patternCount(for: "g") == 752)
        #expect(gpa.patternCount(for: "i") == 2953)
        #expect(gpa.patternCount(for: "o") == 1621)
        #expect(gpa.patternCount(for: "s") == 3198)
        #expect(gpa.patternCount(for: "u") == 2394)

        // Check uppercase I vs İ polarity: Istanbul -> İstanbul, Isparta -> Isparta
        let istanbulSentence = "Istanbul guzel bir sehir."
        let istRange = istanbulSentence.range(of: "Istanbul")!
        #expect(gpa.oneWayPredictedWord(for: "Istanbul", inSentence: istanbulSentence, wordRange: istRange) == "İstanbul")

        let ispartaSentence = "Isparta gulu meshurdur."
        let ispRange = ispartaSentence.range(of: "Isparta")!
        #expect(gpa.oneWayPredictedWord(for: "Isparta", inSentence: ispartaSentence, wordRange: ispRange) == "Isparta")

        // Strict one-way guarantee: existing Turkish diacritics are never evaluated or stripped
        let mixed = "çıkacagim"
        let mixedPreds = gpa.predictions(for: mixed, inSentence: mixed, wordRange: mixed.startIndex..<mixed.endIndex)
        #expect(mixedPreds.allSatisfy { indexPred in
            let chars = Array(mixed)
            return "cgiouCGIOSU".contains(chars[indexPred.index])
        })
        #expect(!mixedPreds.contains { $0.index == 0 || $0.index == 1 })
    }

    @Test("EnglishWordlist loads 30k-50k words with clean English vs Turkish boundaries")
    func englishWordlistChecks() {
        let en = TitizResources.shared.englishWordlist
        #expect((30_000...50_000).contains(en.count))

        for english in ["driver", "feedback", "search", "is", "on", "son", "can", "gun", "basin", "us", "of", "swift", "apple"] {
            #expect(en.contains(english), "Expected EnglishWordlist to contain '\(english)'")
        }

        for turkishOnly in ["disari", "cikacagim", "icin", "cocuklar", "yagmur", "cok", "bugun", "cunku"] {
            #expect(!en.contains(turkishOnly), "Turkish-only word '\(turkishOnly)' must not be in EnglishWordlist")
        }
    }

    @Test("TurkishFrequencyTable ranks Turkish minimal pairs and collocations accurately")
    func frequencyTableRanking() {
        let freq = TitizResources.shared.frequencyTable
        #expect(freq.unigramEntryCount == 150_000)
        #expect(freq.bigramEntryCount >= 250_000)

        #expect(freq.unigramLog10("yarın") > freq.unigramLog10("yarin") + 2.0)
        #expect(freq.unigramLog10("iş") > freq.unigramLog10("is") + 1.5)
        #expect(freq.unigramLog10("ise") > freq.unigramLog10("işe") + 1.0)
        #expect(freq.pmiBoost(previous: "işe", current: "gittim") > freq.pmiBoost(previous: "ise", current: "gittim"))
    }

    @Test("Strict one-way guarantee never strips or toggles existing Turkish diacritics")
    func mixedTextOneWayGuarantee() {
        let samples: [(input: String, expected: String)] = [
            ("Bugün dışarı çıkacagim icin cok mutluyum.", "Bugün dışarı çıkacağım için çok mutluyum."),
            ("Öğretmenimiz ödevlerin yarın teslim edilmesini soyledi.", "Öğretmenimiz ödevlerin yarın teslim edilmesini söyledi."),
            ("Dışarıda yağmur yagiyor ve şemsiye lazım.", "Dışarıda yağmur yağıyor ve şemsiye lazım."),
            ("İstanbul'da Şemsiye ve Irmak sokakları çok kalabalık.", "İstanbul'da Şemsiye ve Irmak sokakları çok kalabalık.")
        ]

        for (input, expected) in samples {
            let result = Self.engine.correct(input, mode: .character)
            #expect(result.correctedText == expected)
        }
    }

    @Test("Bucket 0 protects English terms, foreign suffixes, and Tier 0 spans")
    func bucket0Protection() {
        let sentence = "Yeni driver guncellemesi, feedback ve loglarini \"Search\" ile https://tdk.gov.tr ve ./scripts/bundle-app.sh uzerinden TDK API iOS GPT-4 MaviKutu icinde inceledik."
        let result = Self.engine.correct(sentence, mode: .character)

        #expect(
            result.correctedText ==
            "Yeni driver güncellemesi, feedback ve loglarini \"Search\" ile https://tdk.gov.tr ve ./scripts/bundle-app.sh üzerinden TDK API iOS GPT-4 MaviKutu içinde inceledik."
        )
        for preserved in ["driver", "feedback", "loglarini", "\"Search\"", "https://tdk.gov.tr", "./scripts/bundle-app.sh", "TDK", "API", "iOS", "GPT-4", "MaviKutu"] {
            #expect(result.correctedText.contains(preserved))
        }
    }

    @Test("Bucket 1 restores unambiguous ASCII words including 8+-mutable-char Turkish words")
    func bucket1Restoration() {
        let result = Self.engine.correct(
            "universiteli yeni sehir kutuphanesinde turkce calismak ve belirginlestirememissek bunu duzeltecek",
            mode: .character
        )
        #expect(
            result.correctedText ==
            "üniversiteli yeni şehir kütüphanesinde türkçe çalışmak ve belirginleştirememişsek bunu düzeltecek"
        )
        let nonBucket1 = result.edits.filter { $0.origin != .character || $0.bucket != .bucket1 }.map {
            "\($0.original)->\($0.replacement)(\($0.bucket?.rawValue ?? "nil"),\($0.alternatives))"
        }
        #expect(nonBucket1.isEmpty)
    }

    @Test("Bucket 2 disambiguates high-skew pairs and collocations while preserving ambiguous originals")
    func bucket2DisambiguationAndPreservation() {
        let highSkew = Self.engine.correct("Bu is yarin aksam bitecek.", mode: .character)
        #expect(highSkew.correctedText == "Bu iş yarın akşam bitecek.")

        let collocation = Self.engine.correct("Sabah erkenden ise gittim.", mode: .character)
        #expect(collocation.correctedText == "Sabah erkenden işe gittim.")

        let englishCollisionInTurkish = Self.engine.correct("dugmesine basin.", mode: .character)
        #expect(englishCollisionInTurkish.correctedText == "düğmesine basın.")

        // Ambiguous or valid Turkish/English originals must remain untouched
        let conditionalIse = Self.engine.correct("Hava güzel ise çıkarız.", mode: .character)
        #expect(conditionalIse.correctedText == "Hava güzel ise çıkarız.")

        let validSok = Self.engine.correct("Fişi prize sok.", mode: .character)
        #expect(validSok.correctedText == "Fişi prize sok.")
        #expect(validSok.ambiguousSuggestions.contains { $0.original == "sok" && $0.candidates.contains("şok") })

        let validSon = Self.engine.correct("Son karar bu.", mode: .character)
        #expect(validSon.correctedText == "Son karar bu.")

        let englishPhrase = Self.engine.correct("The Last of Us", mode: .character)
        #expect(englishPhrase.correctedText == "The Last of Us")
    }

    @Test("Character mode obeys scope boundary without changing capitalization or punctuation spacing")
    func characterModeScopeBoundary() {
        let result = Self.engine.correct("yarin disari cikacagim ?", mode: .character)
        #expect(result.correctedText == "yarın dışarı çıkacağım ?")
    }

    @Test("Edit provenance tracks exact original and corrected UTF-16 ranges even on NFD input")
    func editProvenanceAndNFDMapping() {
        // "I\u{0307}stanbul'da disari cikacagim" -> "I\u{0307}" is 2 UTF-16 code units in original, 1 in NFC
        let nfdInput = "I\u{0307}stanbul'da disari cikacagim"
        let result = Self.engine.correct(nfdInput, mode: .character)

        #expect(result.correctedText == "İstanbul'da dışarı çıkacağım")
        #expect(result.edits.count == 2)

        let nsOriginal = nfdInput as NSString
        let nsCorrected = result.correctedText as NSString

        for edit in result.edits {
            #expect(edit.origin == .character)
            #expect(edit.bucket == .bucket1)
            let origSlice = nsOriginal.substring(with: NSRange(location: edit.originalRange.location, length: edit.originalRange.length))
            let corrSlice = nsCorrected.substring(with: NSRange(location: edit.correctedRange.location, length: edit.correctedRange.length))
            #expect(origSlice == edit.original)
            #expect(corrSlice == edit.replacement)
        }
    }
}
