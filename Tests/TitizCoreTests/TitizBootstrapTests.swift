import Testing
@testable import TitizCore

@Suite("Titiz Bootstrap")
struct TitizBootstrapTests {
    @Test("CHunspell C++ bridge links cleanly and reports pinned Hunspell version")
    func hunspellBridgeVersion() {
        #expect(TitizEngine.hunspellBridgeVersion == "1.7.6")
    }

    @Test("CorrectionMode exposes all three required modes")
    func correctionModeCases() {
        #expect(CorrectionMode.allCases == [.character, .spelling, .combined])
    }

    @Test("Bootstrap pass-through preserves Turkish text across all modes")
    func bootstrapPassThrough() {
        let engine = TitizEngine()
        let sample = "İstanbul'da yağmur yağıyor; Intel ekibinden MaviKutu için haber var."

        for mode in CorrectionMode.allCases {
            let result = engine.correct(sample, mode: mode)
            #expect(result.originalText == sample)
            #expect(result.correctedText == sample)
            #expect(result.mode == mode)
        }
    }
}
