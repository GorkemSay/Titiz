import Foundation
import Testing
@testable import TitizCore

@Suite("SpellingEngine & Combined Mode (Düzelt)")
struct SpellingAndCombinedTests {
    private static let engine = TitizEngine()

    @Test("SpellingRuleCatalog loads rules.json with Turkish TDK explanations and links")
    func ruleCatalogLoads() {
        let catalog = TitizResources.shared.ruleCatalog
        let expectedIDs = [
            "spell.punctuation.space_before",
            "spell.punctuation.space_after",
            "spell.capitalization.sentence_start",
            "spell.question_particle.separate",
            "spell.joint.question_clitic",
            "spell.closed_tdk.lexicon",
            "spell.joint.closed_tdk",
            "char.bucket1",
            "char.bucket2"
        ]

        for id in expectedIDs {
            let meta = catalog.metadata(for: id)
            #expect(meta != nil, "Missing rule metadata for \(id)")
            #expect(meta?.explanationTR.isEmpty == false)
            #expect(meta?.tdkReferenceURL.hasPrefix("https://") == true)
        }
    }

    @Test("Punctuation spacing fixes before/after whitespace while protecting URLs, decimals, times, quotes, and ellipsis")
    func punctuationSpacing() {
        let basic = Self.engine.correct("Bugün toplantı var mı ?", mode: .spelling)
        #expect(basic.correctedText == "Bugün toplantı var mı?")

        let complex = Self.engine.correct("Merhaba ,dünya!Harika bir gün ;hemen başlayalım :", mode: .spelling)
        #expect(complex.correctedText == "Merhaba, dünya! Harika bir gün; hemen başlayalım:")

        let cleanProtected = "Dr. Can saat 14:30'da https://tdk.gov.tr adresinde 3.14 oranını paylaştı... \"Bitti.\" ve/veya mi/mı."
        let protectedResult = Self.engine.correct(cleanProtected, mode: .spelling)
        #expect(protectedResult.correctedText == cleanProtected)
        #expect(protectedResult.edits.isEmpty)
    }

    @Test("Sentence-start capitalization uses tr_TR locale and respects Intel/abbreviations/Tier 0-3")
    func sentenceStartCapitalization() {
        let turkishI = Self.engine.correct("istanbul çok güzel. ırmak kenarında yürüdük.", mode: .spelling)
        #expect(turkishI.correctedText == "İstanbul çok güzel. Irmak kenarında yürüdük.")

        let intelAndWord = Self.engine.correct("Intel yeni işlemci tanıttı. ikinci toplantı yarın.", mode: .spelling)
        #expect(intelAndWord.correctedText == "Intel yeni işlemci tanıttı. İkinci toplantı yarın.")

        let abbrevAndProtected = Self.engine.correct("Dr. benim arkadaşım vb. konular için iOS ve macOS kullandı.", mode: .spelling)
        #expect(abbrevAndProtected.correctedText == "Dr. benim arkadaşım vb. konular için iOS ve macOS kullandı.")
    }

    @Test("Question particle separation handles conjugated suffixes while protecting valid -mi words")
    func questionParticleSeparation() {
        let splitCases: [(String, String)] = [
            ("Bugün toplantı varmı?", "Bugün toplantı var mı?"),
            ("Yarın bizimle geliyormusun?", "Yarın bizimle geliyor musun?"),
            ("Haberi duydunmu ve hazır mısın?", "Haberi duydun mu ve hazır mısın?"),
            ("Biraz daha bekleyelimmi yoksa gidelim mi?", "Biraz daha bekleyelim mi yoksa gidelim mi?"),
            ("Film güzelmiydi ve siz hazırmısınız?", "Film güzel miydi ve siz hazır mısınız?"),
            ("Bugün dışarı çıkacakmıyız ve akşam buluşuyormuyuz?", "Bugün dışarı çıkacak mıyız ve akşam buluşuyor muyuz?")
        ]

        for (input, expected) in splitCases {
            let result = Self.engine.correct(input, mode: .spelling)
            #expect(result.correctedText == expected)
        }

        let protectedSentences = [
            "Ekonomi ve resmi yazışmalarda samimi ama ilmi bir dil kullanıldı.",
            "Kimi zaman yirmi acemi öğrenci daimi olarak aynı salonda çalışır.",
            "Ürünün yapımı, bakımı, durumu, kurumu ve çözümü hakkında sunumu beğendim."
        ]

        for sentence in protectedSentences {
            let result = Self.engine.correct(sentence, mode: .spelling)
            #expect(result.correctedText == sentence)
            #expect(result.edits.isEmpty)
        }
    }

    @Test("Closed TDK spelling lexicon fixes indisputable errors and preserves v1 out-of-scope words")
    func closedTDKAndOutOfScopeGuards() {
        let tdk1 = Self.engine.correct("Bence herşey yolunda ve birşey eksik değil, hiçbirşey gizli kalmaz.", mode: .spelling)
        #expect(tdk1.correctedText == "Bence her şey yolunda ve bir şey eksik değil, hiçbir şey gizli kalmaz.")

        let tdk2 = Self.engine.correct("Toplantıya herkez katıldı ama yanlız sen yalnış bilgi verdin.", mode: .spelling)
        #expect(tdk2.correctedText == "Toplantıya herkes katıldı ama yalnız sen yanlış bilgi verdin.")

        let tdk3 = Self.engine.correct("Yardımın için sağol, şimdilik hoşçakal. İki hata ardarda geldi.", mode: .spelling)
        #expect(tdk3.correctedText == "Yardımın için sağ ol, şimdilik hoşça kal. İki hata art arda geldi.")

        let tdk4 = Self.engine.correct("Herşey güzelmiş. Yanlız birşey soracağım.", mode: .spelling)
        #expect(tdk4.correctedText == "Her şey güzelmiş. Yalnız bir şey soracağım.")

        // v1 out-of-scope: de/da, ki, kar/kâr, and no stylistic rewriting
        let outOfScope = "Sen de gel ki kar yağışını görelim; Gönder."
        let outOfScopeRes = Self.engine.correct(outOfScope, mode: .spelling)
        #expect(outOfScopeRes.correctedText == outOfScope)
        #expect(outOfScopeRes.edits.isEmpty)
    }

    @Test("Combined mode solves canonical SPEC.md target and joint split-and-deasciify cases without breaking -mi stems")
    func combinedAndJointSplitDeasciify() {
        let canonical = Self.engine.correct(
            "Intel ekibinden MaviKutu icin cevap geldimi?",
            mode: .combined,
            additionalPersonalTerms: ["MaviKutu"]
        )
        #expect(canonical.correctedText == "Intel ekibinden MaviKutu için cevap geldi mi?")

        let jointCases: [(String, String)] = [
            ("Disari ciktimi ?", "Dışarı çıktı mı?"),
            ("yarin toplantida yeni gelisme varmi?", "Yarın toplantıda yeni gelişme var mı?"),
            ("Dun aksam yeni filmi gordunmu?", "Dün akşam yeni filmi gördün mü?"),
            ("Guncelleme sorunsuz olmusmu?", "Güncelleme sorunsuz olmuş mu?"),
            ("Bence hersey hazir ama birsey daha var.", "Bence her şey hazır ama bir şey daha var."),
            ("Bugun disari cikacakmisin?", "Bugün dışarı çıkacak mısın?"),
            ("istanbul'da yasayan arkadasim icin guzel bir hediye aldim.", "İstanbul'da yaşayan arkadaşım için güzel bir hediye aldım.")
        ]

        for (input, expected) in jointCases {
            let result = Self.engine.correct(input, mode: .combined)
            #expect(result.correctedText == expected)
            verifyEditRanges(result)
        }

        // Combined punctuation + Bucket 2 conservative preservation (`isim` valid; suggests `işim`)
        let punctBucket2 = Self.engine.correct("Yarin erken kalkacagim,cunku cok isim var .", mode: .combined)
        #expect(punctBucket2.correctedText == "Yarın erken kalkacağım, çünkü çok isim var.")
        #expect(punctBucket2.ambiguousSuggestions.contains { $0.original == "isim" && $0.candidates.contains("işim") })
        verifyEditRanges(punctBucket2)

        // Unsplit ASCII words whose whole diacritic restoration is valid must NOT be split as question clitics
        let wholeWords = Self.engine.correct("uretimi ve cozumu ile bolumu gelistirdik.", mode: .combined)
        #expect(wholeWords.correctedText == "Üretimi ve çözümü ile bölümü geliştirdik.")
        verifyEditRanges(wholeWords)

        // Participle & 1st-person possessive+accusative forms (-diğimi/-tığımı/-ımı) must NEVER split as question clitics
        let userReportedInput = "Arkadaslarimla konusurken Intel islemci almaya karar verdigimi soyledim ama emin olamadim."
        let userReportedExpected = "Arkadaşlarımla konuşurken Intel işlemci almaya karar verdiğimi söyledim ama emin olamadım."
        let userCombined = Self.engine.correct(userReportedInput, mode: .combined)
        #expect(userCombined.correctedText == userReportedExpected)
        verifyEditRanges(userCombined)

        let preservedPossessives = [
            "Arkadaşlarımla konuşurken Intel işlemci almaya karar verdiğimi söyledim ama emin olamadım.",
            "Yazıcıdan çıktımı aldım.",
            "Ne söylediğimi ve ne yaptığımı biliyorum.",
            "Kararımı ve arkadaşımı aradım.",
            "Geleceğimi ve gördüğümü anlattım.",
            "Benim doğrumu kimse değiştiremez.",
            "Yazıcıdan çıktımı aldın mı?",
            "Bu sorunumu nasıl çözerim?",
            "Benim telefonumu gördün?",
            "Benim bilgisayarımı gördün?"
        ]
        for sentence in preservedPossessives {
            let spellResult = Self.engine.correct(sentence, mode: .spelling)
            #expect(spellResult.correctedText == sentence)
            #expect(spellResult.edits.isEmpty)

            let combResult = Self.engine.correct(sentence, mode: .combined)
            #expect(combResult.correctedText == sentence)
        }

        // Mid-sentence fused question clitics inside `?`-terminated clauses (even with Hunspell ghost `-m` stems)
        let midSentenceQuestionCases: [(String, String)] = [
            (
                "Arkadasimla konustuktan sonra Intel islemci almaya karar verdim ama sence dogrumu yapiyorum?",
                "Arkadaşımla konuştuktan sonra Intel işlemci almaya karar verdim ama sence doğru mu yapıyorum?"
            ),
            ("Sence iyimi oldu?", "Sence iyi mi oldu?"),
            ("Bu kotumu gorunuyor?", "Bu kötü mü görünüyor?"),
            ("Sence bu yeterlimi oldu?", "Sence bu yeterli mi oldu?"),
            ("Bunu yenimi aldin?", "Bunu yeni mi aldın?"),
            (
                "Ne soyledigimi biliyorsun ama sence dogrumu yapiyorum?",
                "Ne söylediğimi biliyorsun ama sence doğru mu yapıyorum?"
            )
        ]
        for (input, expected) in midSentenceQuestionCases {
            let combResult = Self.engine.correct(input, mode: .combined)
            #expect(combResult.correctedText == expected)
            verifyEditRanges(combResult)
        }

        let spellMidSentence = Self.engine.correct(
            "Arkadaşımla konuştuktan sonra Intel işlemci almaya karar verdim ama sence doğrumu yapıyorum?",
            mode: .spelling
        )
        #expect(
            spellMidSentence.correctedText ==
                "Arkadaşımla konuştuktan sonra Intel işlemci almaya karar verdim ama sence doğru mu yapıyorum?"
        )
        verifyEditRanges(spellMidSentence)

        // Cross-layer audit regressions:
        // 1) Merged apostrophe combined edit preserves full `original` (`turkiye'de`) for safe per-edit revert.
        let apostropheCombined = Self.engine.correct(
            "turkiye'de yazilim gelistirmek cok keyifli.",
            mode: .combined
        )
        #expect(apostropheCombined.correctedText == "Türkiye'de yazılım geliştirmek çok keyifli.")
        #expect(apostropheCombined.edits.first?.original == "turkiye'de")
        #expect(apostropheCombined.edits.first?.replacement == "Türkiye'de")
        verifyEditRanges(apostropheCombined)

        // 2) ASCII closed TDK fixes (`yanliz`, `yalnis`) + 3) ASCII Turkish city proper nouns (`Istanbul`, `Izmir`)
        //    vs foreign apostrophe protection (`Apple'da`, `Docker'dan`, `GitHub'ta`) + 4) short-stem `actim -> açtım`.
        let auditCases: [(String, String)] = [
            (
                "bence herkez yanliz kalmaktan korkar ama bu yalnis bir dusunce.",
                "Bence herkes yalnız kalmaktan korkar ama bu yanlış bir düşünce."
            ),
            (
                "Istanbul'dan Ankara'ya ucakla gittim, Izmir'de toplantiya katildim.",
                "İstanbul'dan Ankara'ya uçakla gittim, İzmir'de toplantıya katıldım."
            ),
            (
                "Apple'da calisan arkadasim Docker'dan container acip GitHub'ta paylasti.",
                "Apple'da çalışan arkadaşım Docker'dan container açıp GitHub'ta paylaştı."
            ),
            (
                "GitHub uzerinden pull request actim, loglarini kontrol edip commitleri pushladim.",
                "GitHub üzerinden pull request açtım, loglarini kontrol edip commitleri pushladim."
            )
        ]
        for (input, expected) in auditCases {
            let result = Self.engine.correct(input, mode: .combined)
            #expect(result.correctedText == expected)
            verifyEditRanges(result)
        }
    }

    @Test("Exact UTF-16 Edit provenance ranges hold under NFD input across all modes")
    func utf16RangesWithNFDAndCombined() {
        let nfdInput = "istanbul\u{0307}'da yarin   toplanti varmi ?".decomposedStringWithCanonicalMapping
        // Pure NFD Turkish + combined punctuation & joint clitic
        let nfdSentence = "İ".decomposedStringWithCanonicalMapping + "stanbul'da yarin toplanti varmi ? Disari ciktimi ?"
        for mode in CorrectionMode.allCases {
            let result = Self.engine.correct(nfdSentence, mode: mode)
            verifyEditRanges(result)
        }
        _ = nfdInput
    }

    private func verifyEditRanges(_ result: CorrectionResult) {
        let origNS = result.originalText as NSString
        let corrNS = result.correctedText as NSString

        for edit in result.edits {
            #expect(edit.originalRange.location >= 0)
            #expect(edit.originalRange.location + edit.originalRange.length <= origNS.length)
            #expect(edit.correctedRange.location >= 0)
            #expect(edit.correctedRange.location + edit.correctedRange.length <= corrNS.length)

            let origSlice = origNS.substring(with: NSRange(location: edit.originalRange.location, length: edit.originalRange.length))
            let corrSlice = corrNS.substring(with: NSRange(location: edit.correctedRange.location, length: edit.correctedRange.length))
            #expect(origSlice == edit.original, "Mismatch origSlice '\(origSlice)' vs '\(edit.original)'")
            #expect(corrSlice == edit.replacement, "Mismatch corrSlice '\(corrSlice)' vs '\(edit.replacement)'")
        }
    }
}
