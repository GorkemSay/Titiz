import Foundation

/// Separates Turkish question clitics (`mi/mı/mu/mü` and conjugated suffixes) from fused invalid words,
/// optionally performing joint stem + clitic diacritic restoration in `.combined` mode.
public enum QuestionCliticSplitter {
    private struct CliticTemplate {
        let suffix: String
        let forms: (i: String, dotlessI: String, u: String, uUmlaut: String)
    }

    private enum VowelHarmonyClass {
        case frontUnrounded // e, i -> i
        case backUnrounded  // a, ı -> ı
        case backRounded    // o, u -> u
        case frontRounded   // ö, ü -> ü
    }

    private static let templates: [CliticTemplate] = {
        let baseSuffixes: [(String, String, String, String)] = [
            ("mi", "mı", "mu", "mü"),
            ("miyim", "mıyım", "muyum", "müyüm"),
            ("misin", "mısın", "musun", "müsün"),
            ("miyiz", "mıyız", "muyuz", "müyüz"),
            ("misiniz", "mısınız", "musunuz", "müsünüz"),
            ("miydi", "mıydı", "muydu", "müydü"),
            ("miydim", "mıydım", "muydum", "müydüm"),
            ("miydin", "mıydın", "muydun", "müydün"),
            ("miydik", "mıydık", "muyduk", "müydük"),
            ("miydiniz", "mıydınız", "muydunuz", "müydünüz"),
            ("miymiş", "mıymış", "muymuş", "müymüş"),
            ("miyse", "mıysa", "muysa", "müyse"),
            ("midir", "mıdır", "mudur", "müdür"),
        ]

        var all: [CliticTemplate] = []
        for forms in baseSuffixes {
            let entries = [forms.0, forms.1, forms.2, forms.3]
            for s in entries {
                all.append(CliticTemplate(suffix: s, forms: forms))
                let asciiVariant = TurkishLocale.asciiFolded(s)
                if asciiVariant != s {
                    all.append(CliticTemplate(suffix: asciiVariant, forms: forms))
                }
            }
        }
        // Sort longest suffix first so conjugated forms (e.g. `misiniz`) match before bare `mi`.
        return all.sorted { $0.suffix.count > $1.suffix.count }
    }()

    /// Known dictionary words ending in `-mi/-mı/-mu/-mü` that must never be split.
    private static let protectedWholeWords: Set<String> = [
        "ekonomi", "resmi", "samimi", "ilmi", "kimi", "yirmi", "acemi", "daimi",
        "isim", "isimi", "işimi", "yapımı", "bakımı", "alımı", "verimi", "durumu",
        "kurumu", "yorumu", "sunumu", "konumu", "bölümü", "çözümü", "ölümü",
        "bilimi", "üretimi", "tüketimi", "yönetimi", "eğitimi", "iletişimi",
        "denetimi", "iklimi", "mevsimi", "hakimi", "hekimi", "tahmini", "yüzümü"
    ]

    /// Loanword stems whose final orthographic vowel takes front harmony in Turkish pronunciation.
    private static let palatalLoanwordStems: [String: VowelHarmonyClass] = [
        "saat": .frontUnrounded,
        "hayal": .frontUnrounded,
        "kalp": .frontUnrounded,
        "hal": .frontUnrounded,
        "harf": .frontUnrounded,
        "alkol": .frontRounded,
        "kontrol": .frontRounded,
        "sembol": .frontRounded,
        "rol": .frontRounded,
        "gol": .frontRounded
    ]

    /// Known 1st-person possessive + accusative participle/noun endings that frequently collide with `-mi/-mı` stems.
    private static let participlePossessiveAccusativeSuffixes: [String] = [
        "diğimi", "dığımı", "duğumu", "düğümü",
        "tiğimi", "tığımı", "tuğumu", "tüğümü",
        "eceğimi", "acağımı"
    ]

    /// Over-permissive Hunspell verbal truncations (`varm`, `yokm`) that accept invalid fused clitics.
    /// None of these are valid Turkish single words in TDK orthography.
    private static let knownOverpermissiveClitics: Set<String> = [
        "varmı", "varmi", "yokmu"
    ]

    /// Attempts to split a fused word ending in a Turkish question clitic.
    /// Returns `(replacement: "<stem> <clitic>", ruleID: ...)` when safe and high-confidence, or `nil`.
    public static func splitIfApplicable(
        word: String,
        inSentence sentence: String,
        wordRange: Range<String.Index>,
        followedByQuestionMark: Bool = false,
        enableJointDeasciify: Bool,
        dictionary: HunspellDictionary,
        gpaScorer: GPAScorer,
        englishWordlist: EnglishWordlist,
        frequencyTable: TurkishFrequencyTable
    ) -> (replacement: String, ruleID: String, isJoint: Bool)? {
        let nfc = word.precomposedStringWithCanonicalMapping
        guard nfc.count >= 4, nfc.allSatisfy(\.isLetter) else {
            return nil
        }

        // Preserve ALL-CAPS or unexpected mixed internal case (e.g. CamelCase is already Tier 0).
        let lowered = TurkishLocale.lowercased(nfc)
        let isAllLower = nfc == lowered
        let isTitleCase = nfc.first?.isUppercase == true && nfc.dropFirst().allSatisfy(\.isLowercase)
        guard isAllLower || isTitleCase else {
            return nil
        }

        if englishWordlist.contains(lowered) || protectedWholeWords.contains(lowered) {
            return nil
        }

        if Self.participlePossessiveAccusativeSuffixes.contains(where: { lowered.hasSuffix($0) }) {
            return nil
        }

        // Never split real Turkish whole words: when Hunspell accepts `nfc`, only split if:
        //  (a) it is a known over-permissive Hunspell verbal truncation (`varmı`, `varmi`, `yokmu`), OR
        //  (b) the token is immediately followed by `?` and completely unseen in 8M clean corpus (`unigram <= -7.5`, catching `çıktımı ?`).
        let isHunspellValid = CandidateGenerator.isValidTurkishWord(nfc, dictionary: dictionary)
        if isHunspellValid && !Self.knownOverpermissiveClitics.contains(lowered) {
            let unigram = frequencyTable.unigramLog10(lowered)
            let stemWithoutFinalVowel = String(nfc.dropLast())
            let looksLikePossessiveMStem = CandidateGenerator.isValidTurkishWord(stemWithoutFinalVowel, dictionary: dictionary)

            let allowSplitForNonPossessive = !looksLikePossessiveMStem && unigram <= -5.5
            let allowSplitForQuestionMarkedUnseen = followedByQuestionMark && unigram <= -7.5
            guard allowSplitForNonPossessive || allowSplitForQuestionMarkedUnseen else {
                return nil
            }
        }

        if enableJointDeasciify && !isHunspellValid {
            // Protect unsplit ASCII Turkish words missing diacritics (e.g. `uretimi` -> `üretimi`, `cozumu` -> `çözümü`).
            let unsplitPredictions = gpaScorer.predictions(for: nfc, inSentence: sentence, wordRange: wordRange)
            let unsplitCandidates = CandidateGenerator.generate(
                for: nfc,
                gpaPredictions: unsplitPredictions,
                dictionary: dictionary
            )
            if unsplitCandidates.originalIsValid || !unsplitCandidates.validAlternatives.isEmpty {
                return nil
            }
        }

        for template in templates {
            guard lowered.hasSuffix(template.suffix) else { continue }
            let suffixCharCount = template.suffix.count
            guard nfc.count - suffixCharCount >= 2 else { continue }

            // Non-joint Spelling mode requires exact valid Turkish clitic orthography (not ASCII-folded fallback).
            let rawSuffix = String(lowered.suffix(suffixCharCount))
            if !enableJointDeasciify &&
                rawSuffix != template.forms.i &&
                rawSuffix != template.forms.dotlessI &&
                rawSuffix != template.forms.u &&
                rawSuffix != template.forms.uUmlaut {
                continue
            }

            let rawStem = String(nfc.dropLast(suffixCharCount))

            if CandidateGenerator.isValidTurkishWord(rawStem, dictionary: dictionary) {
                guard let harmony = harmonyClass(for: rawStem) else { continue }
                let expectedClitic = cliticForm(for: template, harmony: harmony)
                if !enableJointDeasciify && rawSuffix != expectedClitic {
                    continue
                }
                let isJoint = rawSuffix != expectedClitic
                let ruleID = isJoint ? "spell.joint.question_clitic" : "spell.question_particle.separate"
                return ("\(rawStem) \(expectedClitic)", ruleID, isJoint)
            }

            guard enableJointDeasciify,
                  !englishWordlist.contains(TurkishLocale.lowercased(rawStem)) else {
                continue
            }

            // Joint split-and-deasciify: restore missing diacritics on the split stem and harmonize the clitic.
            let stemEnd = sentence.index(wordRange.lowerBound, offsetBy: rawStem.count)
            let stemRange = wordRange.lowerBound..<stemEnd
            let stemPredictions = gpaScorer.predictions(for: rawStem, inSentence: sentence, wordRange: stemRange)
            let stemResult = CandidateGenerator.generate(
                for: rawStem,
                gpaPredictions: stemPredictions,
                dictionary: dictionary
            )
            guard !stemResult.validAlternatives.isEmpty else { continue }

            let chosenStem: String?
            if stemResult.validAlternatives.count == 1 {
                chosenStem = stemResult.validAlternatives[0]
            } else {
                let scored = stemResult.validAlternatives.map { cand -> (candidate: String, score: Double) in
                    let uni = frequencyTable.unigramLog10(cand)
                    let gpa = gpaScorer.agreementScore(candidate: cand, original: rawStem, predictions: stemPredictions)
                    return (cand, uni + 1.10 * gpa)
                }.sorted { lhs, rhs in
                    if lhs.score != rhs.score { return lhs.score > rhs.score }
                    return lhs.candidate < rhs.candidate
                }

                if scored.count >= 2 && (scored[0].score - scored[1].score) >= 0.45 {
                    chosenStem = scored[0].candidate
                } else {
                    chosenStem = nil
                }
            }

            guard let restoredStem = chosenStem,
                  let harmony = harmonyClass(for: restoredStem) else {
                continue
            }

            let harmonizedClitic = cliticForm(for: template, harmony: harmony)
            return ("\(restoredStem) \(harmonizedClitic)", "spell.joint.question_clitic", true)
        }

        return nil
    }

    // MARK: - Vowel Harmony Helpers

    private static func harmonyClass(for stem: String) -> VowelHarmonyClass? {
        let lower = TurkishLocale.lowercased(stem)
        if let override = palatalLoanwordStems[lower] {
            return override
        }

        for ch in lower.reversed() {
            switch ch {
            case "e", "i":
                return .frontUnrounded
            case "a", "ı":
                return .backUnrounded
            case "o", "u":
                return .backRounded
            case "ö", "ü":
                return .frontRounded
            default:
                continue
            }
        }
        return nil
    }

    private static func cliticForm(for template: CliticTemplate, harmony: VowelHarmonyClass) -> String {
        switch harmony {
        case .frontUnrounded:
            return template.forms.i
        case .backUnrounded:
            return template.forms.dotlessI
        case .backRounded:
            return template.forms.u
        case .frontRounded:
            return template.forms.uUmlaut
        }
    }
}
