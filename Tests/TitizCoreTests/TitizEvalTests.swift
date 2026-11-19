import Foundation
import Testing
@testable import TitizCore
@testable import TitizEval

@Suite("TitizEval Harness & Datasets")
struct TitizEvalTests {
    private static var repoRootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // TitizCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // Repo root
    }

    @Test("EvalScorer scores clean pass-through with zero corruptions and catches synthetic corruptions")
    func cleanPassThroughAndSyntheticCorruption() {
        let cleanCase = EvalCase(
            id: "test-clean",
            mode: .combined,
            category: .clean,
            isCleanSentence: true,
            input: "Intel ekibinden teşekkür geldi.",
            expected: "Intel ekibinden teşekkür geldi.",
            expectedEdits: [],
            protectedSpans: [
                ProtectedSpanExpectation(text: "Intel", tier: .tier2A)
            ]
        )

        let (passEval, passTiers) = EvalScorer.scoreCase(cleanCase, actual: cleanCase.input)
        #expect(passEval.exactMatch)
        #expect(passEval.falsePositiveCorruptions == 0)
        #expect(passEval.proposedEdits == 0)
        #expect(passEval.protectedSpansRetained == 1)
        #expect(passTiers[EvalProtectionTier.tier2A.rawValue]?.rate == 1.0)

        // Synthetic entity corruption ("Intel" -> "İntel")
        let (corruptEval, corruptTiers) = EvalScorer.scoreCase(cleanCase, actual: "İntel ekibinden teşekkür geldi.")
        #expect(!corruptEval.exactMatch)
        #expect(corruptEval.falsePositiveCorruptions == 1)
        #expect(corruptEval.proposedEdits == 1)
        #expect(corruptEval.correctProposedEdits == 0)
        #expect(corruptEval.protectedSpansRetained == 0)
        #expect(corruptTiers[EvalProtectionTier.tier2A.rawValue]?.rate == 0.0)

        // Spurious pure insertion on a clean sentence must still count as a corruption
        let (insertionEval, _) = EvalScorer.scoreCase(cleanCase, actual: "Intel ekibinden teşekkür geldi .")
        #expect(insertionEval.falsePositiveCorruptions >= 1)
        #expect(insertionEval.correctProposedEdits == 0)
    }

    @Test("EvalScorer aligns splits, punctuation spacing, and penalizes partial edits")
    func splitsAndSpacingAlignment() {
        let splitCase = EvalCase(
            id: "test-split",
            mode: .combined,
            category: .fusedClitics,
            isCleanSentence: false,
            input: "Bugün toplantı varmı ? Merhaba,dünya geldimi?",
            expected: "Bugün toplantı var mı? Merhaba, dünya geldi mi?",
            expectedEdits: [
                ExpectedEdit(original: "varmı ?", expected: "var mı?", bucket: .spellingJoint, origin: .spelling),
                ExpectedEdit(original: ",dünya", expected: ", dünya", bucket: .spelling, origin: .spelling),
                ExpectedEdit(original: "geldimi", expected: "geldi mi", bucket: .spelling, origin: .spelling)
            ]
        )

        let (perfectEval, _) = EvalScorer.scoreCase(splitCase, actual: splitCase.expected)
        #expect(perfectEval.exactMatch)
        #expect(perfectEval.falsePositiveCorruptions == 0)
        #expect(perfectEval.recalledEditsTotal == 3)
        #expect(perfectEval.proposedEdits == 3)
        #expect(perfectEval.correctProposedEdits == 3)

        // Partial/wrong edit: only fixes ",dünya" -> ", dünya" and corrupts "Bugün" -> "Bugun"
        let (partialEval, _) = EvalScorer.scoreCase(splitCase, actual: "Bugun toplantı varmı ? Merhaba, dünya geldimi?")
        #expect(!partialEval.exactMatch)
        #expect(partialEval.recalledEditsTotal == 1)
        #expect(partialEval.proposedEdits == 2)
        #expect(partialEval.correctProposedEdits == 1)
        #expect(partialEval.falsePositiveCorruptions == 1)
    }

    @Test("EvalScorer separates Bucket 1 vs Bucket 2 recall and reports nil precision when 0 edits proposed")
    func bucketSeparationAndZeroEditPrecision() {
        let testCase = EvalCase(
            id: "test-buckets",
            mode: .character,
            category: .asciiTurkish,
            isCleanSentence: false,
            input: "yarin disari cikacagim",
            expected: "yarın dışarı çıkacağım",
            expectedEdits: [
                ExpectedEdit(original: "yarin", expected: "yarın", bucket: .bucket2, origin: .character),
                ExpectedEdit(original: "disari", expected: "dışarı", bucket: .bucket1, origin: .character),
                ExpectedEdit(original: "cikacagim", expected: "çıkacağım", bucket: .bucket1, origin: .character)
            ]
        )

        let cleanOnlyDataset = EvalDataset(
            schemaVersion: "1.0.0",
            datasetName: "unit-zero-edit-test",
            description: "Clean sentence test",
            cases: [
                EvalCase(
                    id: "unit-clean-01",
                    mode: .character,
                    category: .clean,
                    isCleanSentence: true,
                    input: "Bugün dışarı çıkacağım.",
                    expected: "Bugün dışarı çıkacağım.",
                    expectedEdits: []
                )
            ]
        )

        // Clean input causes 0 proposed edits -> editPrecision must be nil (never faked as 100%)
        let zeroEditReport = EvalScorer.evaluate(dataset: cleanOnlyDataset, using: TitizEngine())
        #expect(zeroEditReport.overall.proposedEdits == 0)
        #expect(zeroEditReport.overall.editPrecision == nil)

        // Bucket 1 only engine output vs Bucket 1 + Bucket 2 dataset
        let dataset = EvalDataset(
            schemaVersion: "1.0.0",
            datasetName: "unit-bucket-test",
            description: "Synthetic bucket test",
            cases: [testCase]
        )
        let report = EvalScorer.evaluate(dataset: dataset, using: TitizEngine())
        #expect(report.overall.expectedBucket1Edits == 2)
        #expect(report.overall.expectedEditsTotal == 3)
        #expect(report.overall.recalledBucket1Edits == 2)

        // Direct scoreCase solving both Bucket 1 edits while leaving Bucket 2 untouched
        let (bucket1OnlyEval, _) = EvalScorer.scoreCase(testCase, actual: "yarin dışarı çıkacağım")
        #expect(bucket1OnlyEval.expectedBucket1Edits == 2)
        #expect(bucket1OnlyEval.recalledBucket1Edits == 2)
        #expect(bucket1OnlyEval.expectedEditsTotal == 3)
        #expect(bucket1OnlyEval.recalledEditsTotal == 2)
        #expect(bucket1OnlyEval.falsePositiveCorruptions == 0)
    }

    @Test("LatencyBenchmarker computes exact percentiles and provides ~300c and ~2000c samples")
    func latencyPercentilesAndSamples() {
        let values = [10.0, 2.0, 4.0, 8.0, 6.0, 12.0, 14.0, 16.0, 18.0, 20.0]
        #expect(LatencyBenchmarker.percentile(values, p: 50.0) == 10.0)
        #expect(LatencyBenchmarker.percentile(values, p: 95.0) == 20.0)
        #expect(LatencyBenchmarker.percentile([5.0], p: 50.0) == 5.0)
        #expect(LatencyBenchmarker.percentile([5.0], p: 95.0) == 5.0)

        let shortLen = LatencyBenchmarker.shortSample.count
        let longLen = LatencyBenchmarker.longSample.count
        #expect((270...330).contains(shortLen), "Expected shortSample near 300 chars, got \(shortLen)")
        #expect((1900...2150).contains(longLen), "Expected longSample near 2000 chars, got \(longLen)")

        let report = LatencyBenchmarker.measure(using: TitizEngine(), iterations: 10, warmup: 2)
        #expect(report.short.iterations == 10)
        #expect(report.long.iterations == 10)
        #expect(report.short.minMs <= report.short.p50Ms)
        #expect(report.short.p50Ms <= report.short.p95Ms)
        #expect(report.short.p95Ms <= report.short.maxMs)
        #expect(report.long.minMs <= report.long.p50Ms)
        #expect(report.long.p50Ms <= report.long.p95Ms)
        #expect(report.long.p95Ms <= report.long.maxMs)
    }

    @Test("Datasets/dev_cases.json passes validation and verifies Bucket 1 forms against bundled tr_TR")
    func devDatasetIntegrityAndDictionaryGrounding() throws {
        let devURL = Self.repoRootURL.appendingPathComponent("Datasets/dev_cases.json")
        let dataset = try EvalDataset.load(from: devURL)

        let issues = EvalScorer.validateDataset(dataset)
        #expect(issues.isEmpty, "Dataset validation issues: \(issues)")

        #expect(dataset.cases.count >= 50)
        for mode in CorrectionMode.allCases {
            let count = dataset.cases.filter { $0.mode == mode }.count
            #expect(count >= 15, "Expected >= 15 cases for mode \(mode.rawValue), got \(count)")
        }
        #expect(dataset.cases.contains { $0.isCleanSentence })

        let dictionary = try HunspellDictionary.loadBundledTurkish()
        for testCase in dataset.cases {
            for edit in testCase.expectedEdits where edit.origin == .character && edit.bucket == .bucket1 {
                let sig = EvalScorer.minimalEditSignature(original: edit.original, expected: edit.expected)
                let origWord = sig?.original ?? edit.original
                let expectedWord = sig?.replacement ?? edit.expected

                #expect(
                    !dictionary.contains(origWord),
                    "Bucket 1 edit '\(origWord)' in case '\(testCase.id)' is already accepted by tr_TR.dic — reclassify as bucket2"
                )
                #expect(
                    dictionary.contains(expectedWord),
                    "Bucket 1 expected target '\(expectedWord)' in case '\(testCase.id)' was not accepted by tr_TR.dic"
                )
            }
        }
    }

    @Test("Datasets/blind_cases.schema.json parses as a valid JSON Schema")
    func blindSchemaValidity() throws {
        let schemaURL = Self.repoRootURL.appendingPathComponent("Datasets/blind_cases.schema.json")
        let data = try Data(contentsOf: schemaURL)
        let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(jsonObject != nil)
        #expect(jsonObject?["$schema"] as? String == "https://json-schema.org/draft/2020-12/schema")
        let required = jsonObject?["required"] as? [String] ?? []
        #expect(Set(required) == Set(["schemaVersion", "datasetName", "description", "cases"]))
        #expect((jsonObject?["properties"] as? [String: Any]) != nil)
    }

    @Test("ReportFormatter suppresses individual case text in blind mode")
    func blindReportSuppressesCaseStrings() throws {
        let secretInput = "gizli kor test cumlesi disari cikacagim"
        let blindCase = EvalCase(
            id: "blind-01",
            mode: .character,
            category: .asciiTurkish,
            isCleanSentence: false,
            input: secretInput,
            expected: "gizli kor test cumlesi dışarı çıkacağım",
            expectedEdits: [
                ExpectedEdit(original: "disari", expected: "dışarı", bucket: .bucket1, origin: .character),
                ExpectedEdit(original: "cikacagim", expected: "çıkacağım", bucket: .bucket1, origin: .character)
            ]
        )

        let dataset = EvalDataset(
            schemaVersion: "1.0.0",
            datasetName: "local-blind",
            description: "Blind test",
            cases: [blindCase]
        )
        let report = EvalScorer.evaluate(dataset: dataset, using: TitizEngine())

        let textOutput = ReportFormatter.formatText(report: report, verbose: true, isBlind: true)
        #expect(!textOutput.contains(secretInput))
        #expect(!textOutput.contains("blind-01"))
        #expect(textOutput.contains("BLIND SUMMARY-ONLY"))

        let jsonOutput = try ReportFormatter.formatJSON(report: report, isBlind: true)
        #expect(!jsonOutput.contains(secretInput))
        #expect(!jsonOutput.contains("blind-01"))
    }
}
