import Testing
@testable import TitizCore

@Suite("StructuralLexer & Tier 0 Protection")
struct StructuralLexerAndTier0Tests {
    private let engine = TitizEngine()

    @Test("Lossless round-trip invariant holds on mixed Turkish, code, URLs, and punctuation")
    func losslessRoundTrip() {
        let sample = """
        Merhaba!\r\nBugün https://tdk.gov.tr/sozluk?q=titiz. adresine baktım; \
        detaylar `swift test` ile ./scripts/bundle-app.sh içinde.\n@gorkemsay #Türkçe 14:30'da görüşürüz!
        """
        let document = engine.analyze(sample)
        #expect(document.tokens.map(\.text).joined().utf8.elementsEqual(document.normalized.text.utf8))
    }

    @Test("Punctuation never glues onto adjacent words")
    func punctuationSeparation() {
        let document = engine.analyze("yarin,disari")
        let summary = document.tokens.map { ($0.text, $0.kind) }

        #expect(summary.count == 3)
        #expect(summary[0].0 == "yarin" && summary[0].1 == .word)
        #expect(summary[1].0 == "," && summary[1].1 == .punctuation)
        #expect(summary[2].0 == "disari" && summary[2].1 == .word)
    }

    @Test("Quoted short UI labels are Tier 0 protected while quote punctuation stays separate")
    func quotedUILabels() {
        let doc = engine.analyze("Sonra \"Search\" veya 'Gönder' ya da “Yine de Aç” düğmesine basın.")
        let protectedTexts = doc.tokens.filter(\.isProtected).map(\.text)

        #expect(protectedTexts == ["Search", "Gönder", "Yine", "de", "Aç"])

        for token in doc.tokens where protectedTexts.contains(token.text) {
            #expect(token.protection?.tier == .tier0Structural)
            #expect(token.protection?.structuralKind == .quotedUILabel)
        }

        // Quotes themselves remain separate punctuation tokens
        let quotePunctuation = doc.tokens.filter { $0.kind == .punctuation && ["\"", "'", "“", "”"].contains($0.text) }
        #expect(quotePunctuation.count == 6)

        // Longer or lowercase quoted sentences must NOT be treated as UI labels
        let sentenceDoc = engine.analyze("\"Bugün dışarı çıkacağım ama hava soğuk.\"")
        #expect(sentenceDoc.tokens.allSatisfy { !$0.isProtected })

        let shortLowerSentence = engine.analyze("\"Bugün geldim\"")
        #expect(shortLowerSentence.tokens.allSatisfy { !$0.isProtected })
    }

    @Test("CamelCase, digit-mixed, underscore, and ALL-CAPS acronyms are Tier 0 protected")
    func identifiersAndAcronyms() {
        let sample = "MaviKutu MaviKutu'nun GitHub MenuBarExtra iOS macOS GPT-4 GPT-4'ün tr_TR TDK API SQL TDK'nın O"
        let doc = engine.analyze(sample)

        func token(_ text: String) -> Token? {
            doc.tokens.first { $0.text == text }
        }

        for id in ["MaviKutu", "MaviKutu'nun", "GitHub", "MenuBarExtra", "iOS", "macOS", "GPT-4", "GPT-4'ün", "tr_TR"] {
            let t = token(id)
            #expect(t != nil, "Missing token \(id)")
            #expect(t?.protection?.tier == .tier0Structural)
            #expect(t?.protection?.structuralKind == .camelOrMixedIdentifier)
        }

        for acronym in ["TDK", "API", "SQL", "TDK'nın"] {
            let t = token(acronym)
            #expect(t != nil, "Missing acronym \(acronym)")
            #expect(t?.protection?.tier == .tier0Structural)
            #expect(t?.protection?.structuralKind == .allCapsAcronym)
        }

        // Single uppercase Turkish pronoun "O" must NOT be flagged as an acronym
        let pronounO = token("O")
        #expect(pronounO != nil)
        #expect(pronounO?.isProtected == false)
    }

    @Test("Apostrophe-inflected TitleCase words split stem and suffix without false Tier 0 triggers")
    func apostropheWords() {
        let doc = engine.analyze("Intel'den ve Intel’den haber geldi.")
        let apostropheTokens = doc.tokens.filter {
            if case .apostropheWord = $0.kind { return true }
            return false
        }

        #expect(apostropheTokens.count == 2)
        #expect(apostropheTokens[0].kind == .apostropheWord(stem: "Intel", apostrophe: "'", suffix: "den"))
        #expect(apostropheTokens[1].kind == .apostropheWord(stem: "Intel", apostrophe: "’", suffix: "den"))
        // TitleCase "Intel" awaits Tier 2A protection in Phase 4 rather than false CamelCase Tier 0
        #expect(!apostropheTokens[0].isProtected)
        #expect(!apostropheTokens[1].isProtected)
    }

    @Test("URLs, emails, handles, hashtags, code spans, and file paths are Tier 0 protected")
    func structuralSpans() {
        let sample = """
        Bağlantılar: https://tdk.gov.tr/sozluk?q=titiz. ve (https://tr.wikipedia.org/wiki/Swift_(programlama_dili)) \
        ile www.apple.com/tr, ayrıca gorkemsay@protonmail.com. Hesap @gorkemsay #Türkçe #Swift6 \
        komut `swift test` yollar /Users/gorkemsay/Desktop/test.swift ~/Library/Caches/Titiz/data.json \
        ./scripts/bundle-app.sh Sources/TitizCore/TitizEngine.swift ve/veya mi/mı.
        """
        let doc = engine.analyze(sample)

        func hasSpan(_ text: String, _ kind: StructuralProtectionKind) -> Bool {
            doc.tokens.contains {
                $0.text == text && $0.kind == .protectedSpan(kind) && $0.protection?.tier == .tier0Structural
            }
        }

        #expect(hasSpan("https://tdk.gov.tr/sozluk?q=titiz", .url))
        #expect(hasSpan("https://tr.wikipedia.org/wiki/Swift_(programlama_dili)", .url))
        #expect(hasSpan("www.apple.com/tr", .url))
        #expect(hasSpan("gorkemsay@protonmail.com", .email))
        #expect(hasSpan("@gorkemsay", .handle))
        #expect(hasSpan("#Türkçe", .hashtag))
        #expect(hasSpan("#Swift6", .hashtag))
        #expect(hasSpan("`swift test`", .inlineCode))
        #expect(hasSpan("/Users/gorkemsay/Desktop/test.swift", .filePath))
        #expect(hasSpan("~/Library/Caches/Titiz/data.json", .filePath))
        #expect(hasSpan("./scripts/bundle-app.sh", .filePath))
        #expect(hasSpan("Sources/TitizCore/TitizEngine.swift", .filePath))

        // Turkish slash alternatives must remain plain words + punctuation, never file paths
        #expect(doc.tokens.contains { $0.text == "ve" && $0.kind == .word })
        #expect(doc.tokens.contains { $0.text == "veya" && $0.kind == .word })
        #expect(doc.tokens.contains { $0.text == "mi" && $0.kind == .word })
        #expect(doc.tokens.contains { $0.text == "mı" && $0.kind == .word })
        #expect(!doc.tokens.contains { $0.kind == .protectedSpan(.filePath) && ($0.text == "ve/veya" || $0.text == "mi/mı") })
    }

    @Test("Numbers, decimals, times, and versions preserve trailing punctuation and inflections")
    func numbersAndVersions() {
        let doc = engine.analyze("Pi 3.14 ve saat 14:30. Buluşma 14:30'da veya 2026'da, sürüm v1.7.6.")

        #expect(doc.tokens.contains { $0.text == "3.14" && $0.kind == .protectedSpan(.numericOrVersion) })
        #expect(doc.tokens.contains { $0.text == "14:30" && $0.kind == .protectedSpan(.numericOrVersion) })
        #expect(doc.tokens.contains { $0.text == "v1.7.6" && $0.kind == .protectedSpan(.numericOrVersion) })

        let timeInflected = doc.tokens.first { $0.text == "14:30'da" }
        #expect(timeInflected?.kind == .apostropheWord(stem: "14:30", apostrophe: "'", suffix: "da"))
        #expect(timeInflected?.protection?.structuralKind == .numericOrVersion)

        let yearInflected = doc.tokens.first { $0.text == "2026'da" }
        #expect(yearInflected?.kind == .apostropheWord(stem: "2026", apostrophe: "'", suffix: "da"))
        #expect(yearInflected?.protection?.structuralKind == .numericOrVersion)
    }

    @Test("Tokenizes canonical target sentence cleanly with MaviKutu protected")
    func canonicalTargetSentence() {
        let doc = engine.analyze("Intel ekibinden MaviKutu icin cevap geldimi?")
        let words = doc.tokens.filter { $0.kind != .whitespace }

        #expect(words.map(\.text) == ["Intel", "ekibinden", "MaviKutu", "icin", "cevap", "geldimi", "?"])
        #expect(words[2].text == "MaviKutu")
        #expect(words[2].protection?.tier == .tier0Structural)
        #expect(words[2].protection?.structuralKind == .camelOrMixedIdentifier)
        #expect(words.last?.kind == .punctuation)
    }
}
