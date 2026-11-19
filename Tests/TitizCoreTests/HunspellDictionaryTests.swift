import Foundation
import Testing
@testable import TitizCore

@Suite("HunspellDictionary")
struct HunspellDictionaryTests {
    private static let sharedTurkish: HunspellDictionary = {
        do {
            return try HunspellDictionary.loadBundledTurkish()
        } catch {
            fatalError("Failed to load bundled Turkish dictionary: \(error)")
        }
    }()

    @Test("Loads bundled tr_TR dictionary and accepts valid Turkish words")
    func validTurkishWords() {
        let dictionary = Self.sharedTurkish

        let validWords = [
            "yarın", "dışarı", "çıkacağım", "için", "geldi",
            "ekonomi", "samimi", "resmi", "İstanbul", "yağmur",
            "gördün", "olmuş", "her", "şey"
        ]

        for word in validWords {
            #expect(dictionary.contains(word), "Expected tr_TR to accept '\(word)'")
        }
    }

    @Test("Rejects ASCII-corrupted Turkish spellings while returning suggestions")
    func rejectsASCIICorruptedWordsAndSuggests() {
        let dictionary = Self.sharedTurkish

        let asciiWords = ["disari", "cikacagim", "icin", "yagmur", "turkce", "cicek"]
        for word in asciiWords {
            #expect(!dictionary.contains(word), "Expected tr_TR not to accept ASCII '\(word)'")
        }

        // In tdd-ai/hunspell-tr, both "yarin" (derived from "ya" + SFX 27513) and "yarın" are valid;
        // verify deterministic acceptance (motivating Phase 3 Bucket 2 disambiguation).
        for _ in 0..<20 {
            #expect(dictionary.contains("yarin"))
            #expect(dictionary.contains("yarın"))
        }

        let icinSuggestions = dictionary.suggestions(for: "icin")
        #expect(icinSuggestions.contains("için"))

        let yagmurSuggestions = dictionary.suggestions(for: "yagmur")
        #expect(yagmurSuggestions.contains("yağmur"))

        let disariSuggestions = dictionary.suggestions(for: "disari")
        #expect(!disariSuggestions.isEmpty)
    }

    @Test("Normalizes NFD input to NFC before Hunspell lookup")
    func nfdInputLookup() {
        let dictionary = Self.sharedTurkish

        // NFD forms: I + U+0307 (İ) and g + U+0306 (ğ)
        let nfdIstanbul = "I\u{0307}stanbul"
        let nfdYagmur = "yag\u{0306}mur"

        #expect(dictionary.contains(nfdIstanbul))
        #expect(dictionary.contains(nfdYagmur))
        #expect(!dictionary.contains(""))
    }

    @Test("Adds words dynamically via addRuntimeWord")
    func runtimeWordAddition() throws {
        let dictionary = try HunspellDictionary.loadBundledTurkish()
        let customTerm = "TitizUygulamasiTestKelimesi"

        #expect(!dictionary.contains(customTerm))
        #expect(dictionary.addRuntimeWord(customTerm))
        #expect(dictionary.contains(customTerm))
    }

    @Test("Throws failedToLoad when dictionary files do not exist")
    func missingDictionaryThrows() {
        #expect(throws: HunspellDictionaryError.failedToLoad(
            affPath: "/nonexistent/tr_TR.aff",
            dicPath: "/nonexistent/tr_TR.dic"
        )) {
            _ = try HunspellDictionary(
                affPath: "/nonexistent/tr_TR.aff",
                dicPath: "/nonexistent/tr_TR.dic"
            )
        }
    }

    @Test("Concurrent spell and suggest calls remain thread-safe")
    func concurrentAccess() async {
        let dictionary = Self.sharedTurkish
        let probes = ["yarın", "dışarı", "çıkacağım", "için", "disari", "yağmur", "ekonomi", "icin", "yagmur", "yarin"]
        let rejected: Set<String> = ["disari", "icin", "yagmur"]

        let allValid = await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
            for iteration in 0..<64 {
                let word = probes[iteration % probes.count]
                group.addTask {
                    let isValid = dictionary.contains(word)
                    if !isValid {
                        _ = dictionary.suggestions(for: word)
                    }
                    return isValid == !rejected.contains(word)
                }
            }

            var passed = true
            for await outcome in group {
                if !outcome {
                    passed = false
                }
            }
            return passed
        }

        #expect(allValid)
    }
}
