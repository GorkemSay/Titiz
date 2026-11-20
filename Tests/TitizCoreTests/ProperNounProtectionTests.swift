import Foundation
import Testing
@testable import TitizCore

@Suite("4-Tier Proper Noun Protection & Personal Dictionary")
struct ProperNounProtectionTests {
    @Test("EntityGazetteer loads Wikidata CC0 collision-filtered Tier2A, Tier2B, and Tier3 resources")
    func gazetteerLoadsAndCrossFilters() throws {
        let gazetteer = TitizResources.shared.gazetteer

        #expect(gazetteer.tier2A.count >= 500)
        #expect(gazetteer.tier2B.count >= 100)
        #expect(gazetteer.tier3Trie.phraseCount >= 200)

        // Strict disjointness between Tier2A and Tier2B
        #expect(gazetteer.tier2A.isDisjoint(with: gazetteer.tier2B))

        // Canonical SPEC.md Tier 2A distinctive entities
        for term in ["Intel", "Nvidia", "Spotify", "Netflix", "PlayStation", "Valorant", "Atatürk", "İstanbul"] {
            #expect(gazetteer.tier2A.contains(term), "Expected Tier2A to contain \(term)")
        }

        // Canonical SPEC.md Tier 2B colliding entities must reside in Tier2B (never Tier2A)
        for term in ["Can", "It", "Son", "Su", "Yol", "Güneş", "Swift", "Apple", "Deniz"] {
            #expect(gazetteer.tier2B.contains(term), "Expected Tier2B to contain \(term)")
            #expect(!gazetteer.tier2A.contains(term), "Tier2A must not contain colliding word \(term)")
        }

        // Ordinary Turkish/English words must never appear in Tier2A
        for ordinary in ["is", "son", "yol", "su", "can", "apple", "swift", "var", "yok", "film"] {
            #expect(!gazetteer.tier2A.contains(ordinary))
        }
    }

    @Test("Tier 2A protects distinctive brands and proper nouns in all sentence positions")
    func tier2AProtection() {
        let engine = TitizEngine()
        let doc = engine.analyze("Intel, Nvidia, Spotify, Netflix, PlayStation, Valorant, Atatürk ve İstanbul'da toplandı.")

        for expected in ["Intel", "Nvidia", "Spotify", "Netflix", "Valorant", "Atatürk", "İstanbul'da"] {
            let tok = doc.tokens.first { $0.text == expected }
            #expect(tok != nil, "Missing token \(expected)")
            #expect(tok?.protection?.tier == .tier2ANonCollidingEntity, "Expected Tier2A for \(expected)")
        }

        // PlayStation is also structural CamelCase (Tier 0) or Tier 2A — both protect unconditionally
        let playStation = doc.tokens.first { $0.text == "PlayStation" }
        #expect(playStation?.isProtected == true)

        // Character restoration still fixes ordinary Turkish words around protected entities
        let corrected = engine.correct("Intel ve Spotify uzerinden Ataturk icin yazi hazirladik.", mode: .character)
        #expect(corrected.correctedText.contains("Intel"))
        #expect(corrected.correctedText.contains("Spotify"))
        #expect(corrected.correctedText.contains("üzerinden"))
        #expect(corrected.correctedText.contains("için"))
        #expect(corrected.correctedText.contains("yazı"))
        #expect(corrected.correctedText.contains("hazırladık"))
    }

    @Test("Tier 2B requires strong proper-noun context and never blocks ordinary sentence-start Turkish")
    func tier2BContextDetection() {
        let engine = TitizEngine()

        // 1. Apostrophe inflection protects Tier2B even at sentence start
        let apostropheDoc = engine.analyze("Can'a ve Apple'da çalışan ekibe Swift'i önerdik.")
        for name in ["Can'a", "Apple'da", "Swift'i"] {
            let tok = apostropheDoc.tokens.first { $0.text == name }
            #expect(tok?.protection?.tier == .tier2BCollidingEntity, "Expected Tier2B for \(name)")
        }

        // 2. Title and category cues protect Tier2B even at sentence start
        let cueDoc = engine.analyze("Can Bey geldi. It filmi ve Son oyunu harikaydı. Swift dili çok hızlı.")
        #expect(cueDoc.tokens.first { $0.text == "Can" }?.protection?.tier == .tier2BCollidingEntity)
        #expect(cueDoc.tokens.first { $0.text == "It" }?.protection?.tier == .tier2BCollidingEntity)
        #expect(cueDoc.tokens.first { $0.text == "Son" }?.protection?.tier == .tier2BCollidingEntity)
        #expect(cueDoc.tokens.first { $0.text == "Swift" }?.protection?.tier == .tier2BCollidingEntity)

        // 3. Mid-sentence capitalized colliding entity is protected
        let midDoc = engine.analyze("Bugün Deniz ile görüştüm.")
        #expect(midDoc.tokens.first { $0.text == "Deniz" }?.protection?.tier == .tier2BCollidingEntity)

        // 4. Ordinary Turkish capitalized at sentence start WITHOUT apostrophe or cue is NOT Tier2B locked
        let ordinaryDoc = engine.analyze("Son durum belli oldu. Yol uzun ama Su çok soğuk. Güneş açtı.")
        for sentenceStartWord in ["Son", "Yol", "Güneş"] {
            let tok = ordinaryDoc.tokens.first { $0.text == sentenceStartWord }
            #expect(tok?.isProtected == false, "\(sentenceStartWord) at sentence start without cues must not be blocked")
        }
    }

    @Test("Tier 3 longest-match multi-word trie matches multi-word titles before single-word Tier 2")
    func tier3LongestMatchTrie() {
        let engine = TitizEngine()
        let doc = engine.analyze("Visual Studio Code üzerinde The Last of Us'ta ve Red Dead Redemption oynadık.")

        for word in ["Visual", "Studio", "Code", "The", "Last", "of", "Us'ta", "Red", "Dead", "Redemption"] {
            let tok = doc.tokens.first { $0.text == word }
            #expect(tok != nil, "Missing token \(word)")
            #expect(tok?.protection?.tier == .tier3MultiWordEntity, "Expected Tier3 for \(word)")
        }

        // Longest-match test on custom trie
        let customTrie = MultiWordEntityTrie(phrases: ["New York", "New York Times", "Yeni Proje X"])
        var lexed = StructuralLexer.tokenize(TextNormalizer.normalize("New York Times haberleri ve Yeni Proje X'in raporu"))
        customTrie.apply(to: &lexed, tier: .tier3MultiWordEntity, reasonPrefix: "Test trie")

        let times = lexed.first { $0.text == "Times" }
        #expect(times?.protection?.tier == .tier3MultiWordEntity)
        #expect(times?.protection?.reason.contains("New York Times") == true)

        let projectX = lexed.first { $0.text == "X'in" }
        #expect(projectX?.protection?.tier == .tier3MultiWordEntity)
        #expect(projectX?.protection?.reason.contains("Yeni Proje X") == true)
    }

    @Test("Personal Dictionary persists to JSON, reloads immediately, and outranks all built-in tiers")
    func personalDictionaryPersistenceAndPrecedence() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TitizTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storeURL = tempDir.appendingPathComponent("personal_dictionary.json")
        let store = PersonalDictionaryStore(storageURL: storeURL)
        try store.add(term: "Yeni Proje X")
        try store.add(term: "bulutkutu")
        try store.add(term: "MaviKutu")

        let engine = TitizEngine(personalDictionaryStore: store)

        // Precedence: MaviKutu (also Tier 0 CamelCase) -> Tier 1 Personal Dictionary
        let canonical = engine.analyze("Intel ekibinden MaviKutu icin cevap geldi.")
        #expect(canonical.tokens.first { $0.text == "Intel" }?.protection?.tier == .tier2ANonCollidingEntity)
        #expect(canonical.tokens.first { $0.text == "MaviKutu" }?.protection?.tier == .tier1PersonalDictionary)

        // Multi-word & lowercase entries protect immediately
        let result = engine.correct("Yeni Proje X ve bulutkutu icin guncelleme hazir.", mode: .character)
        #expect(result.correctedText == "Yeni Proje X ve bulutkutu için güncelleme hazır.")

        let phraseDoc = engine.analyze("Yeni Proje X'in detayları ve bulutkutu")
        #expect(phraseDoc.tokens.first { $0.text == "Yeni" }?.protection?.tier == .tier1PersonalDictionary)
        #expect(phraseDoc.tokens.first { $0.text == "Proje" }?.protection?.tier == .tier1PersonalDictionary)
        #expect(phraseDoc.tokens.first { $0.text == "X'in" }?.protection?.tier == .tier1PersonalDictionary)
        #expect(phraseDoc.tokens.first { $0.text == "bulutkutu" }?.protection?.tier == .tier1PersonalDictionary)

        // Disk persistence round-trip
        let reloadedStore = try PersonalDictionaryStore.load(from: storeURL)
        #expect(reloadedStore.entries.map(\.term).sorted() == ["MaviKutu", "Yeni Proje X", "bulutkutu"])

        // Immediate reload / removal takes effect immediately on the active engine
        try store.add(term: "disari")
        let beforeRemove = engine.correct("disari", mode: .character)
        #expect(beforeRemove.correctedText == "disari")

        try store.remove(term: "disari")
        let afterRemove = engine.correct("disari", mode: .character)
        #expect(afterRemove.correctedText == "dışarı")
    }

    @Test("Foreign-stem apostrophe suffix guard preserves pronunciation suffixes on protected and foreign stems")
    func foreignStemApostropheSuffixGuard() {
        let engine = TitizEngine()
        let resources = TitizResources.shared

        let sample = "Apple'da çalışan ekip iPhone'u, GitHub'ta ve Docker'da testi bitirdi."
        let doc = engine.analyze(sample)

        for tokenText in ["Apple'da", "iPhone'u", "GitHub'ta", "Docker'da"] {
            let tok = doc.tokens.first { $0.text == tokenText }
            #expect(tok != nil, "Missing token \(tokenText)")
            #expect(
                ForeignSuffixGuard.shouldPreserveSuffix(
                    for: tok!,
                    englishWordlist: resources.englishWordlist,
                    dictionary: resources.dictionary
                )
            )
        }

        // Ordinary Turkish inflected word does not trigger foreign-stem suffix guard
        let trDoc = engine.analyze("Okul'da veya kitap'ta okudum.")
        let okul = trDoc.tokens.first { $0.text == "Okul'da" }!
        #expect(
            !ForeignSuffixGuard.shouldPreserveSuffix(
                for: okul,
                englishWordlist: resources.englishWordlist,
                dictionary: resources.dictionary
            )
        )

        let corrected = engine.correct(sample, mode: .character)
        #expect(corrected.correctedText == sample)
    }
}
