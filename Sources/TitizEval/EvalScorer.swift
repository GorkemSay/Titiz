import Foundation
import TitizCore

/// Minimal token-aligned diff hunk between an input string and a rewritten string.
public struct DiffHunk: Sendable, Equatable, Hashable {
    public let inputTokenRange: Range<Int>
    public let originalText: String
    public let replacementText: String

    public init(inputTokenRange: Range<Int>, originalText: String, replacementText: String) {
        self.inputTokenRange = inputTokenRange
        self.originalText = originalText
        self.replacementText = replacementText
    }
}

/// Per-tier protected entity/term retention counts.
public struct TierRetentionCounts: Codable, Sendable, Equatable {
    public var total: Int = 0
    public var retained: Int = 0

    public var rate: Double? {
        guard total > 0 else { return nil }
        return Double(retained) / Double(total)
    }

    public init(total: Int = 0, retained: Int = 0) {
        self.total = total
        self.retained = retained
    }
}

/// Raw counts and derived rates for an evaluation slice.
public struct AggregateMetrics: Codable, Sendable, Equatable {
    public let caseCount: Int
    public let exactMatches: Int

    public let originallyCorrectTokens: Int
    public let falsePositiveCorruptions: Int
    public let cleanOriginallyCorrectTokens: Int
    public let cleanFalsePositiveCorruptions: Int

    public let protectedSpansTotal: Int
    public let protectedSpansRetained: Int
    public let tierRetention: [String: TierRetentionCounts]

    public let expectedEditsTotal: Int
    public let recalledEditsTotal: Int
    public let expectedBucket1Edits: Int
    public let recalledBucket1Edits: Int

    public let proposedEdits: Int
    public let correctProposedEdits: Int

    public var exactMatchRate: Double? {
        guard caseCount > 0 else { return nil }
        return Double(exactMatches) / Double(caseCount)
    }

    public var falsePositiveCorruptionRate: Double? {
        guard originallyCorrectTokens > 0 else { return nil }
        return Double(falsePositiveCorruptions) / Double(originallyCorrectTokens)
    }

    public var cleanFalsePositiveCorruptionRate: Double? {
        guard cleanOriginallyCorrectTokens > 0 else { return nil }
        return Double(cleanFalsePositiveCorruptions) / Double(cleanOriginallyCorrectTokens)
    }

    public var protectedRetentionRate: Double? {
        guard protectedSpansTotal > 0 else { return nil }
        return Double(protectedSpansRetained) / Double(protectedSpansTotal)
    }

    public var tier1RetentionRate: Double? {
        tierRetention[EvalProtectionTier.tier1.rawValue]?.rate
    }

    public var tier2ARetentionRate: Double? {
        tierRetention[EvalProtectionTier.tier2A.rawValue]?.rate
    }

    public var trueErrorRecall: Double? {
        guard expectedEditsTotal > 0 else { return nil }
        return Double(recalledEditsTotal) / Double(expectedEditsTotal)
    }

    public var bucket1Recall: Double? {
        guard expectedBucket1Edits > 0 else { return nil }
        return Double(recalledBucket1Edits) / Double(expectedBucket1Edits)
    }

    /// Returns `nil` when `proposedEdits == 0` so zero-edit baselines never fake precision.
    public var editPrecision: Double? {
        guard proposedEdits > 0 else { return nil }
        return Double(correctProposedEdits) / Double(proposedEdits)
    }
}

/// Evaluation thresholds defined in `SPEC.md` Phase 2.
public enum EvalThresholds {
    public static let maxFalsePositiveRate: Double = 0.005
    public static let maxCleanFalsePositiveRate: Double = 0.0
    public static let minProtectedRetentionRate: Double = 0.99
    public static let minTier1RetentionRate: Double = 1.0
    public static let minTier2ARetentionRate: Double = 1.0
    public static let minBucket1Recall: Double = 0.92
    public static let minOverallRecall: Double = 0.75
    public static let minEditPrecision: Double = 0.95
    public static let maxP50LatencyMs: Double = 10.0
    public static let maxShortP95LatencyMs: Double = 25.0
    public static let maxLongP95LatencyMs: Double = 80.0
}

/// Detailed scoring result for a single `EvalCase`.
public struct CaseEvaluation: Codable, Sendable, Equatable {
    public let id: String
    public let mode: CorrectionMode
    public let category: EvalCategory
    public let isCleanSentence: Bool
    public let input: String
    public let expected: String
    public let actual: String
    public let exactMatch: Bool

    public let originallyCorrectTokens: Int
    public let falsePositiveCorruptions: Int
    public let expectedEditsTotal: Int
    public let recalledEditsTotal: Int
    public let expectedBucket1Edits: Int
    public let recalledBucket1Edits: Int
    public let proposedEdits: Int
    public let correctProposedEdits: Int
    public let protectedSpansTotal: Int
    public let protectedSpansRetained: Int
}

/// Full dataset evaluation report including per-mode and per-category breakdowns.
public struct DatasetEvaluationReport: Codable, Sendable, Equatable {
    public let titizCoreVersion: String
    public let hunspellVersion: String
    public let datasetName: String
    public let schemaVersion: String
    public let overall: AggregateMetrics
    public let byMode: [String: AggregateMetrics]
    public let byCategory: [String: AggregateMetrics]
    public let cases: [CaseEvaluation]
    public let latency: LatencyReport?

    /// Returns `true` only when every applicable quality and latency gate passes.
    public var allGatesPass: Bool {
        let qualityPasses =
            (overall.falsePositiveCorruptionRate ?? 1.0) <= EvalThresholds.maxFalsePositiveRate &&
            (overall.cleanFalsePositiveCorruptionRate ?? 1.0) <= EvalThresholds.maxCleanFalsePositiveRate &&
            (overall.protectedRetentionRate ?? 0.0) >= EvalThresholds.minProtectedRetentionRate &&
            (overall.tier1RetentionRate ?? 1.0) >= EvalThresholds.minTier1RetentionRate &&
            (overall.tier2ARetentionRate ?? 1.0) >= EvalThresholds.minTier2ARetentionRate &&
            (overall.bucket1Recall ?? 0.0) >= EvalThresholds.minBucket1Recall &&
            (overall.trueErrorRecall ?? 0.0) >= EvalThresholds.minOverallRecall &&
            (overall.editPrecision ?? 0.0) >= EvalThresholds.minEditPrecision

        guard let latency else {
            return qualityPasses
        }
        return qualityPasses && latency.allGatesPass
    }
}

/// Deterministic token-aligned evaluator and dataset validator.
public enum EvalScorer {
    /// Evaluates a full dataset using the provided `TitizEngine`.
    public static func evaluate(
        dataset: EvalDataset,
        using engine: TitizEngine,
        modeFilter: CorrectionMode? = nil,
        latency: LatencyReport? = nil
    ) -> DatasetEvaluationReport {
        let filteredCases = modeFilter.map { filter in
            dataset.cases.filter { $0.mode == filter }
        } ?? dataset.cases

        let evaluated = filteredCases.map { testCase -> (CaseEvaluation, [String: TierRetentionCounts]) in
            let result = engine.correct(
                testCase.input,
                mode: testCase.mode,
                additionalPersonalTerms: testCase.personalDictionary ?? []
            )
            return scoreCase(testCase, actual: result.correctedText)
        }

        let overall = aggregate(evaluated)

        var byMode: [String: AggregateMetrics] = [:]
        for mode in CorrectionMode.allCases {
            let slice = evaluated.filter { $0.0.mode == mode }
            if !slice.isEmpty {
                byMode[mode.rawValue] = aggregate(slice)
            }
        }

        var byCategory: [String: AggregateMetrics] = [:]
        for category in EvalCategory.allCases {
            let slice = evaluated.filter { $0.0.category == category }
            if !slice.isEmpty {
                byCategory[category.rawValue] = aggregate(slice)
            }
        }

        return DatasetEvaluationReport(
            titizCoreVersion: TitizEngine.version,
            hunspellVersion: TitizEngine.hunspellBridgeVersion,
            datasetName: dataset.datasetName,
            schemaVersion: dataset.schemaVersion,
            overall: overall,
            byMode: byMode,
            byCategory: byCategory,
            cases: evaluated.map(\.0),
            latency: latency
        )
    }

    /// Scores a single `EvalCase` against an engine's actual output string.
    public static func scoreCase(
        _ testCase: EvalCase,
        actual: String
    ) -> (CaseEvaluation, [String: TierRetentionCounts]) {
        let inputTokens = tokenize(testCase.input)
        let expectedTokens = tokenize(testCase.expected)
        let actualTokens = tokenize(actual)

        let goldHunks = diffHunks(from: inputTokens, to: expectedTokens)
        let actualHunks = diffHunks(from: inputTokens, to: actualTokens)

        let originallyCorrectIndices = Set(
            inputTokens.indices.filter { index in
                guard inputTokens[index].kind != .whitespace else { return false }
                return !goldHunks.contains { $0.inputTokenRange.contains(index) }
            }
        )

        var falsePositives = originallyCorrectIndices.filter { index in
            actualHunks.contains { $0.inputTokenRange.contains(index) }
        }.count

        // Count spurious pure insertions that do not match any gold insertion hunk
        // so clean-sentence modifications never score zero corruptions.
        for hunk in actualHunks where hunk.inputTokenRange.isEmpty {
            if !goldHunks.contains(hunk) {
                falsePositives += 1
            }
        }

        let matchedGoldIndices = matchExpectedEdits(testCase.expectedEdits, against: goldHunks)
        let actualHunkSet = Set(actualHunks)

        var recalledTotal = 0
        var expectedBucket1 = 0
        var recalledBucket1 = 0

        for (editIndex, edit) in testCase.expectedEdits.enumerated() {
            let isBucket1 = edit.bucket == .bucket1
            if isBucket1 {
                expectedBucket1 += 1
            }
            if let goldIndex = matchedGoldIndices[editIndex],
               actualHunkSet.contains(goldHunks[goldIndex]) {
                recalledTotal += 1
                if isBucket1 {
                    recalledBucket1 += 1
                }
            }
        }

        let goldHunkSet = Set(goldHunks)
        let correctProposed = actualHunks.filter { goldHunkSet.contains($0) }.count

        let (protectedTotal, protectedRetained, perTier) = scoreProtectedSpans(
            testCase.protectedSpans ?? [],
            in: actualTokens
        )

        let eval = CaseEvaluation(
            id: testCase.id,
            mode: testCase.mode,
            category: testCase.category,
            isCleanSentence: testCase.isCleanSentence,
            input: testCase.input,
            expected: testCase.expected,
            actual: actual,
            exactMatch: actual == testCase.expected,
            originallyCorrectTokens: originallyCorrectIndices.count,
            falsePositiveCorruptions: falsePositives,
            expectedEditsTotal: testCase.expectedEdits.count,
            recalledEditsTotal: recalledTotal,
            expectedBucket1Edits: expectedBucket1,
            recalledBucket1Edits: recalledBucket1,
            proposedEdits: actualHunks.count,
            correctProposedEdits: correctProposed,
            protectedSpansTotal: protectedTotal,
            protectedSpansRetained: protectedRetained
        )

        return (eval, perTier)
    }

    /// Computes minimal token-aligned diff hunks from `source` to `target`.
    public static func diffHunks(from source: String, to target: String) -> [DiffHunk] {
        diffHunks(from: tokenize(source), to: tokenize(target))
    }

    /// Computes the minimal edit signature `(original, replacement)` for an `ExpectedEdit` pair.
    public static func minimalEditSignature(original: String, expected: String) -> (original: String, replacement: String)? {
        let hunks = diffHunks(from: original, to: expected)
        guard hunks.count == 1, let only = hunks.first else {
            return nil
        }
        return (only.originalText, only.replacementText)
    }

    /// Validates dataset structural integrity (unique IDs, NFC expected strings, protected spans, 1-to-1 gold hunks).
    public static func validateDataset(_ dataset: EvalDataset) -> [String] {
        var issues: [String] = []
        var seenIDs: Set<String> = []

        for testCase in dataset.cases {
            if !seenIDs.insert(testCase.id).inserted {
                issues.append("Duplicate case id '\(testCase.id)'.")
            }

            if testCase.input.isEmpty || testCase.expected.isEmpty {
                issues.append("Case '\(testCase.id)' has empty input or expected string.")
            }

            let expectedNFC = testCase.expected.precomposedStringWithCanonicalMapping
            if !testCase.expected.utf8.elementsEqual(expectedNFC.utf8) {
                issues.append("Case '\(testCase.id)' expected text is not UTF-8 NFC normalized.")
            }

            if testCase.isCleanSentence {
                if testCase.input != testCase.expected {
                    issues.append("Clean case '\(testCase.id)' has input != expected.")
                }
                if !testCase.expectedEdits.isEmpty {
                    issues.append("Clean case '\(testCase.id)' must have empty expectedEdits.")
                }
            }

            let inputTokens = tokenize(testCase.input)
            let expectedTokens = tokenize(testCase.expected)
            let goldHunks = diffHunks(from: inputTokens, to: expectedTokens)

            if goldHunks.count != testCase.expectedEdits.count {
                issues.append(
                    "Case '\(testCase.id)' has \(goldHunks.count) gold diff hunk(s) but \(testCase.expectedEdits.count) expectedEdits."
                )
            } else {
                let matched = matchExpectedEdits(testCase.expectedEdits, against: goldHunks)
                if matched.count != testCase.expectedEdits.count {
                    issues.append("Case '\(testCase.id)' expectedEdits do not align 1-to-1 with gold diff hunks.")
                }
            }

            for span in testCase.protectedSpans ?? [] {
                if span.text.isEmpty {
                    issues.append("Case '\(testCase.id)' has empty protectedSpan text.")
                    continue
                }
                if countOccurrences(of: span.text, in: inputTokens) == 0 {
                    issues.append("Case '\(testCase.id)' protectedSpan '\(span.text)' not found in input tokens.")
                }
                if countOccurrences(of: span.text, in: expectedTokens) == 0 {
                    issues.append("Case '\(testCase.id)' protectedSpan '\(span.text)' not found in expected tokens.")
                }
            }
        }

        return issues
    }

    // MARK: - Private Alignment & Aggregation Helpers

    private static func tokenize(_ string: String) -> [Token] {
        StructuralLexer.tokenize(TextNormalizer.normalize(string))
    }

    private static func diffHunks(from sourceTokens: [Token], to targetTokens: [Token]) -> [DiffHunk] {
        let sourceNWIndices = sourceTokens.indices.filter { sourceTokens[$0].kind != .whitespace }
        let targetNWIndices = targetTokens.indices.filter { targetTokens[$0].kind != .whitespace }

        let sourceNW = sourceNWIndices.map { sourceTokens[$0].text }
        let targetNW = targetNWIndices.map { targetTokens[$0].text }
        let sourceNWFolded = sourceNW.map { TurkishLocale.lowercased(TurkishLocale.asciiFolded($0)) }
        let targetNWFolded = targetNW.map { TurkishLocale.lowercased(TurkishLocale.asciiFolded($0)) }

        let m = sourceNW.count
        let n = targetNW.count

        var prefix = 0
        while prefix < m, prefix < n, sourceNW[prefix] == targetNW[prefix] {
            prefix += 1
        }

        var suffix = 0
        while suffix < (m - prefix), suffix < (n - prefix),
              sourceNW[m - 1 - suffix] == targetNW[n - 1 - suffix] {
            suffix += 1
        }

        struct NWMatch {
            let sTokenIdx: Int
            let tTokenIdx: Int
            let isExact: Bool
        }

        var matches: [NWMatch] = []
        matches.reserveCapacity(m)

        for idx in 0..<prefix {
            matches.append(NWMatch(sTokenIdx: sourceNWIndices[idx], tTokenIdx: targetNWIndices[idx], isExact: true))
        }

        let midM = m - prefix - suffix
        let midN = n - prefix - suffix
        if midM > 0 && midN > 0 {
            let cols = midN + 1
            var dp = Array(repeating: 0, count: (midM + 1) * cols)

            for i in stride(from: midM - 1, through: 0, by: -1) {
                for j in stride(from: midN - 1, through: 0, by: -1) {
                    let sIdx = prefix + i
                    let tIdx = prefix + j
                    let score: Int
                    if sourceNW[sIdx] == targetNW[tIdx] {
                        score = 10_000
                    } else if sourceNWFolded[sIdx] == targetNWFolded[tIdx] {
                        score = 1_000
                    } else {
                        score = 0
                    }

                    let diag = score > 0 ? dp[(i + 1) * cols + (j + 1)] + score : -1
                    let skipS = dp[(i + 1) * cols + j]
                    let skipT = dp[i * cols + (j + 1)]
                    dp[i * cols + j] = max(diag, max(skipS, skipT))
                }
            }

            var i = 0
            var j = 0
            while i < midM && j < midN {
                let sIdx = prefix + i
                let tIdx = prefix + j
                let exact = sourceNW[sIdx] == targetNW[tIdx]
                let folded = !exact && sourceNWFolded[sIdx] == targetNWFolded[tIdx]
                let score = exact ? 10_000 : (folded ? 1_000 : 0)

                if score > 0 && dp[i * cols + j] == dp[(i + 1) * cols + (j + 1)] + score {
                    matches.append(NWMatch(sTokenIdx: sourceNWIndices[sIdx], tTokenIdx: targetNWIndices[tIdx], isExact: exact))
                    i += 1
                    j += 1
                } else if dp[(i + 1) * cols + j] >= dp[i * cols + (j + 1)] {
                    i += 1
                } else {
                    j += 1
                }
            }
        }

        for offset in 0..<suffix {
            let sIdx = m - suffix + offset
            let tIdx = n - suffix + offset
            matches.append(NWMatch(sTokenIdx: sourceNWIndices[sIdx], tTokenIdx: targetNWIndices[tIdx], isExact: true))
        }

        var hunks: [DiffHunk] = []
        var sCursor = 0
        var tCursor = 0

        for match in matches {
            hunks.append(
                contentsOf: gapHunks(
                    sourceTokens: sourceTokens,
                    targetTokens: targetTokens,
                    sRange: sCursor..<match.sTokenIdx,
                    tRange: tCursor..<match.tTokenIdx
                )
            )
            if !match.isExact {
                let sTok = sourceTokens[match.sTokenIdx]
                let tTok = targetTokens[match.tTokenIdx]
                hunks.append(
                    DiffHunk(
                        inputTokenRange: match.sTokenIdx..<(match.sTokenIdx + 1),
                        originalText: sTok.text,
                        replacementText: tTok.text
                    )
                )
            }
            sCursor = match.sTokenIdx + 1
            tCursor = match.tTokenIdx + 1
        }

        hunks.append(
            contentsOf: gapHunks(
                sourceTokens: sourceTokens,
                targetTokens: targetTokens,
                sRange: sCursor..<sourceTokens.count,
                tRange: tCursor..<targetTokens.count
            )
        )

        return hunks
    }

    private static func gapHunks(
        sourceTokens: [Token],
        targetTokens: [Token],
        sRange initialSRange: Range<Int>,
        tRange initialTRange: Range<Int>
    ) -> [DiffHunk] {
        var sStart = initialSRange.lowerBound
        var sEnd = initialSRange.upperBound
        var tStart = initialTRange.lowerBound
        var tEnd = initialTRange.upperBound

        while sStart < sEnd, tStart < tEnd, sourceTokens[sStart].text == targetTokens[tStart].text {
            sStart += 1
            tStart += 1
        }

        while sStart < sEnd, tStart < tEnd, sourceTokens[sEnd - 1].text == targetTokens[tEnd - 1].text {
            sEnd -= 1
            tEnd -= 1
        }

        guard sStart < sEnd || tStart < tEnd else {
            return []
        }

        // If both trimmed gaps have the same number of internal single-whitespace-separated segments
        // and no leading/trailing whitespace, split into independent per-word hunks (e.g. "herkez yanlız").
        let sTrimmed = sStart..<sEnd
        let tTrimmed = tStart..<tEnd
        if let sSegments = splitByInternalWhitespace(tokens: sourceTokens, range: sTrimmed),
           let tSegments = splitByInternalWhitespace(tokens: targetTokens, range: tTrimmed),
           sSegments.count > 1,
           sSegments.count == tSegments.count,
           sSegments.map(\.separatorAfter) == tSegments.map(\.separatorAfter) {
            return zip(sSegments, tSegments).compactMap { sSeg, tSeg in
                let orig = sourceTokens[sSeg.range].map(\.text).joined()
                let repl = targetTokens[tSeg.range].map(\.text).joined()
                guard orig != repl else { return nil }
                return DiffHunk(inputTokenRange: sSeg.range, originalText: orig, replacementText: repl)
            }
        }

        return [
            DiffHunk(
                inputTokenRange: sTrimmed,
                originalText: sourceTokens[sTrimmed].map(\.text).joined(),
                replacementText: targetTokens[tTrimmed].map(\.text).joined()
            )
        ]
    }

    private static func splitByInternalWhitespace(
        tokens: [Token],
        range: Range<Int>
    ) -> [(range: Range<Int>, separatorAfter: String?)]? {
        guard !range.isEmpty,
              tokens[range.lowerBound].kind != .whitespace,
              tokens[range.upperBound - 1].kind != .whitespace else {
            return nil
        }

        var segments: [(range: Range<Int>, separatorAfter: String?)] = []
        var segStart = range.lowerBound
        var idx = range.lowerBound
        while idx < range.upperBound {
            if tokens[idx].kind == .whitespace {
                guard idx > segStart else { return nil }
                segments.append((segStart..<idx, tokens[idx].text))
                segStart = idx + 1
            }
            idx += 1
        }
        guard segStart < range.upperBound else { return nil }
        segments.append((segStart..<range.upperBound, nil))
        return segments
    }

    private static func matchExpectedEdits(
        _ expectedEdits: [ExpectedEdit],
        against goldHunks: [DiffHunk]
    ) -> [Int: Int] {
        var matched: [Int: Int] = [:]
        var usedGoldIndices: Set<Int> = []

        for (editIndex, edit) in expectedEdits.enumerated() {
            let targetSig: (original: String, replacement: String)
            if let minimized = minimalEditSignature(original: edit.original, expected: edit.expected) {
                targetSig = minimized
            } else {
                targetSig = (edit.original, edit.expected)
            }

            if let goldIndex = goldHunks.indices.first(where: { idx in
                !usedGoldIndices.contains(idx) &&
                goldHunks[idx].originalText == targetSig.original &&
                goldHunks[idx].replacementText == targetSig.replacement
            }) {
                usedGoldIndices.insert(goldIndex)
                matched[editIndex] = goldIndex
            }
        }

        return matched
    }

    private static func scoreProtectedSpans(
        _ spans: [ProtectedSpanExpectation],
        in actualTokens: [Token]
    ) -> (total: Int, retained: Int, perTier: [String: TierRetentionCounts]) {
        guard !spans.isEmpty else {
            return (0, 0, [:])
        }

        struct SpanKey: Hashable {
            let text: String
            let tier: EvalProtectionTier
        }

        var groupedCounts: [SpanKey: Int] = [:]
        for span in spans {
            groupedCounts[SpanKey(text: span.text, tier: span.tier), default: 0] += 1
        }

        var total = 0
        var retained = 0
        var perTier: [String: TierRetentionCounts] = [:]

        for (key, expectedCount) in groupedCounts {
            let actualCount = min(expectedCount, countOccurrences(of: key.text, in: actualTokens))
            total += expectedCount
            retained += actualCount

            var tierCounts = perTier[key.tier.rawValue, default: TierRetentionCounts()]
            tierCounts.total += expectedCount
            tierCounts.retained += actualCount
            perTier[key.tier.rawValue] = tierCounts
        }

        return (total, retained, perTier)
    }

    private static func countOccurrences(of spanText: String, in documentTokens: [Token]) -> Int {
        let spanTokens = tokenize(spanText)
        let spanTexts = spanTokens.map(\.text)
        guard !spanTexts.isEmpty, spanTexts.count <= documentTokens.count else {
            return 0
        }

        // Single-word span without apostrophe also matches apostropheWord stem (e.g., "Intel" in "Intel'den").
        if spanTexts.count == 1, !spanTexts[0].contains("'"), !spanTexts[0].contains("’") {
            let target = spanTexts[0]
            return documentTokens.reduce(into: 0) { count, token in
                if token.text == target || token.stemText == target {
                    count += 1
                }
            }
        }

        var matches = 0
        let limit = documentTokens.count - spanTexts.count
        var index = 0
        while index <= limit {
            var matched = true
            for offset in 0..<spanTexts.count {
                if documentTokens[index + offset].text != spanTexts[offset] {
                    matched = false
                    break
                }
            }
            if matched {
                matches += 1
                index += spanTexts.count
            } else {
                index += 1
            }
        }
        return matches
    }

    private static func aggregate(
        _ entries: [(CaseEvaluation, [String: TierRetentionCounts])]
    ) -> AggregateMetrics {
        var exactMatches = 0
        var originallyCorrect = 0
        var falsePositives = 0
        var cleanOriginallyCorrect = 0
        var cleanFalsePositives = 0
        var protectedTotal = 0
        var protectedRetained = 0
        var mergedTiers: [String: TierRetentionCounts] = [:]
        var expectedEdits = 0
        var recalledEdits = 0
        var expectedBucket1 = 0
        var recalledBucket1 = 0
        var proposedEdits = 0
        var correctProposed = 0

        for (eval, tiers) in entries {
            if eval.exactMatch { exactMatches += 1 }
            originallyCorrect += eval.originallyCorrectTokens
            falsePositives += eval.falsePositiveCorruptions
            if eval.isCleanSentence {
                cleanOriginallyCorrect += eval.originallyCorrectTokens
                cleanFalsePositives += eval.falsePositiveCorruptions
            }
            protectedTotal += eval.protectedSpansTotal
            protectedRetained += eval.protectedSpansRetained
            for (tierKey, counts) in tiers {
                var acc = mergedTiers[tierKey, default: TierRetentionCounts()]
                acc.total += counts.total
                acc.retained += counts.retained
                mergedTiers[tierKey] = acc
            }
            expectedEdits += eval.expectedEditsTotal
            recalledEdits += eval.recalledEditsTotal
            expectedBucket1 += eval.expectedBucket1Edits
            recalledBucket1 += eval.recalledBucket1Edits
            proposedEdits += eval.proposedEdits
            correctProposed += eval.correctProposedEdits
        }

        return AggregateMetrics(
            caseCount: entries.count,
            exactMatches: exactMatches,
            originallyCorrectTokens: originallyCorrect,
            falsePositiveCorruptions: falsePositives,
            cleanOriginallyCorrectTokens: cleanOriginallyCorrect,
            cleanFalsePositiveCorruptions: cleanFalsePositives,
            protectedSpansTotal: protectedTotal,
            protectedSpansRetained: protectedRetained,
            tierRetention: mergedTiers,
            expectedEditsTotal: expectedEdits,
            recalledEditsTotal: recalledEdits,
            expectedBucket1Edits: expectedBucket1,
            recalledBucket1Edits: recalledBucket1,
            proposedEdits: proposedEdits,
            correctProposedEdits: correctProposed
        )
    }
}
