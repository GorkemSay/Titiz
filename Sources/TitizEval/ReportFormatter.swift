import Foundation
import TitizCore

/// Formats evaluation reports as human-readable terminal summaries or structured JSON.
public enum ReportFormatter {
    /// Renders an English text summary. When `isBlind` is `true`, per-case text payloads are strictly omitted.
    public static func formatText(
        report: DatasetEvaluationReport,
        verbose: Bool = false,
        isBlind: Bool = false
    ) -> String {
        var lines: [String] = []
        let label = isBlind ? "\(report.datasetName) [BLIND SUMMARY-ONLY]" : report.datasetName

        lines.append("TitizEval Report — \(label)")
        lines.append(
            "TitizCore: \(report.titizCoreVersion) | CHunspell: \(report.hunspellVersion) | Schema: \(report.schemaVersion) | Cases: \(report.overall.caseCount)"
        )
        lines.append(String(repeating: "=", count: 88))
        lines.append("Core Quality Gates:")

        lines.append(
            formatGateLine(
                name: "False-Positive Corruption (Overall)",
                value: formatRate(report.overall.falsePositiveCorruptionRate, numerator: report.overall.falsePositiveCorruptions, denominator: report.overall.originallyCorrectTokens),
                target: "<= 0.50%",
                passed: report.overall.falsePositiveCorruptionRate.map { $0 <= EvalThresholds.maxFalsePositiveRate }
            )
        )
        lines.append(
            formatGateLine(
                name: "False-Positive Corruption (Clean Subset)",
                value: formatRate(report.overall.cleanFalsePositiveCorruptionRate, numerator: report.overall.cleanFalsePositiveCorruptions, denominator: report.overall.cleanOriginallyCorrectTokens),
                target: "== 0.00%",
                passed: report.overall.cleanFalsePositiveCorruptionRate.map { $0 <= EvalThresholds.maxCleanFalsePositiveRate }
            )
        )
        lines.append(
            formatGateLine(
                name: "Protected Entity / Foreign Retention",
                value: formatRate(report.overall.protectedRetentionRate, numerator: report.overall.protectedSpansRetained, denominator: report.overall.protectedSpansTotal),
                target: ">= 99.00%",
                passed: report.overall.protectedRetentionRate.map { $0 >= EvalThresholds.minProtectedRetentionRate }
            )
        )
        lines.append(
            formatGateLine(
                name: "  - Tier 1 (Personal Dictionary)",
                value: formatTierRate(report.overall.tierRetention[EvalProtectionTier.tier1.rawValue]),
                target: "== 100.00%",
                passed: report.overall.tier1RetentionRate.map { $0 >= EvalThresholds.minTier1RetentionRate }
            )
        )
        lines.append(
            formatGateLine(
                name: "  - Tier 2A (Non-Colliding Entities)",
                value: formatTierRate(report.overall.tierRetention[EvalProtectionTier.tier2A.rawValue]),
                target: "== 100.00%",
                passed: report.overall.tier2ARetentionRate.map { $0 >= EvalThresholds.minTier2ARetentionRate }
            )
        )
        lines.append(
            formatGateLine(
                name: "True Error Recall (Bucket 1)",
                value: formatRate(report.overall.bucket1Recall, numerator: report.overall.recalledBucket1Edits, denominator: report.overall.expectedBucket1Edits),
                target: ">= 92.00%",
                passed: report.overall.bucket1Recall.map { $0 >= EvalThresholds.minBucket1Recall }
            )
        )
        lines.append(
            formatGateLine(
                name: "True Error Recall (Overall In-Scope)",
                value: formatRate(report.overall.trueErrorRecall, numerator: report.overall.recalledEditsTotal, denominator: report.overall.expectedEditsTotal),
                target: ">= 75.00%",
                passed: report.overall.trueErrorRecall.map { $0 >= EvalThresholds.minOverallRecall }
            )
        )
        lines.append(
            formatGateLine(
                name: "Edit Precision",
                value: formatRate(report.overall.editPrecision, numerator: report.overall.correctProposedEdits, denominator: report.overall.proposedEdits, nilLabel: "N/A (0 edits)"),
                target: ">= 95.00%",
                passed: report.overall.editPrecision.map { $0 >= EvalThresholds.minEditPrecision }
            )
        )

        lines.append("")
        lines.append("Protected Span Retention by Tier:")
        for tier in EvalProtectionTier.allCases {
            if let counts = report.overall.tierRetention[tier.rawValue] {
                lines.append("  \(tier.rawValue.padding(toLength: 14, withPad: " ", startingAt: 0)): \(formatTierRate(counts))")
            }
        }

        lines.append("")
        lines.append("Breakdown by Mode:")
        for mode in CorrectionMode.allCases {
            if let m = report.byMode[mode.rawValue] {
                let exactStr = formatPercent(m.exactMatchRate)
                let fpStr = formatPercent(m.falsePositiveCorruptionRate)
                let recStr = formatPercent(m.trueErrorRecall)
                let precStr = formatPercent(m.editPrecision, nilLabel: "N/A")
                lines.append(
                    "  \(mode.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)) (\(String(format: "%2d", m.caseCount)) cases): exact \(exactStr) | FP \(fpStr) | recall \(recStr) | prec \(precStr)"
                )
            }
        }

        lines.append("")
        lines.append("Breakdown by Category:")
        for category in EvalCategory.allCases {
            if let c = report.byCategory[category.rawValue] {
                let exactStr = formatPercent(c.exactMatchRate)
                let fpStr = formatPercent(c.falsePositiveCorruptionRate)
                let recStr = formatPercent(c.trueErrorRecall, nilLabel: "N/A")
                lines.append(
                    "  \(category.rawValue.padding(toLength: 22, withPad: " ", startingAt: 0)) (\(String(format: "%2d", c.caseCount)) cases): exact \(exactStr) | FP \(fpStr) | recall \(recStr)"
                )
            }
        }

        if let latency = report.latency {
            lines.append("")
            lines.append("Latency Benchmarks (ContinuousClock, .combined mode):")
            lines.append(
                String(
                    format: "  Short (%d chars, %d runs): p50 = %.3f ms (< 10 ms) | p95 = %.3f ms (< 25 ms) | min %.3f / max %.3f ms [%@]",
                    latency.short.characterCount,
                    latency.short.iterations,
                    latency.short.p50Ms,
                    latency.short.p95Ms,
                    latency.short.minMs,
                    latency.short.maxMs,
                    latency.shortPasses ? "PASS" : "FAIL"
                )
            )
            lines.append(
                String(
                    format: "  Long  (%d chars, %d runs): p50 = %.3f ms (< 10 ms) | p95 = %.3f ms (< 80 ms) | min %.3f / max %.3f ms [%@]",
                    latency.long.characterCount,
                    latency.long.iterations,
                    latency.long.p50Ms,
                    latency.long.p95Ms,
                    latency.long.minMs,
                    latency.long.maxMs,
                    latency.longPasses ? "PASS" : "FAIL"
                )
            )
        }

        if verbose && !isBlind {
            let mismatches = report.cases.filter { !$0.exactMatch }
            if !mismatches.isEmpty {
                lines.append("")
                lines.append("Mismatched Cases (showing up to 25 of \(mismatches.count)):")
                for entry in mismatches.prefix(25) {
                    lines.append("  [\(entry.id)] (\(entry.mode.rawValue)/\(entry.category.rawValue))")
                    lines.append("    input   : \(entry.input)")
                    lines.append("    expected: \(entry.expected)")
                    lines.append("    actual  : \(entry.actual)")
                }
            }
        } else if verbose && isBlind {
            lines.append("")
            lines.append("Note: Per-case blind examples are suppressed to preserve held-out evaluation discipline.")
        }

        return lines.joined(separator: "\n")
    }

    /// Encodes the evaluation report as pretty-printed sorted JSON.
    /// When `isBlind` is `true`, strips individual case payloads so blind examples are never emitted.
    public static func formatJSON(
        report: DatasetEvaluationReport,
        isBlind: Bool = false
    ) throws -> String {
        let sanitized: DatasetEvaluationReport
        if isBlind {
            sanitized = DatasetEvaluationReport(
                titizCoreVersion: report.titizCoreVersion,
                hunspellVersion: report.hunspellVersion,
                datasetName: report.datasetName,
                schemaVersion: report.schemaVersion,
                overall: report.overall,
                byMode: report.byMode,
                byCategory: report.byCategory,
                cases: [],
                latency: report.latency
            )
        } else {
            sanitized = report
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(sanitized)
        return String(decoding: data, as: UTF8.self)
    }

    private static func formatGateLine(
        name: String,
        value: String,
        target: String,
        passed: Bool?
    ) -> String {
        let status: String
        if let passed {
            status = passed ? "PASS" : "FAIL"
        } else {
            status = "N/A"
        }
        return "  \(name.padding(toLength: 42, withPad: " ", startingAt: 0)): \(value.padding(toLength: 22, withPad: " ", startingAt: 0)) | target \(target.padding(toLength: 10, withPad: " ", startingAt: 0)) [\(status)]"
    }

    private static func formatRate(
        _ rate: Double?,
        numerator: Int,
        denominator: Int,
        nilLabel: String = "N/A"
    ) -> String {
        guard let rate else { return nilLabel }
        return String(format: "%6.2f%% (%d/%d)", rate * 100.0, numerator, denominator)
    }

    private static func formatTierRate(_ counts: TierRetentionCounts?) -> String {
        guard let counts, let rate = counts.rate else { return "N/A (0/0)" }
        return String(format: "%6.2f%% (%d/%d)", rate * 100.0, counts.retained, counts.total)
    }

    private static func formatPercent(_ rate: Double?, nilLabel: String = "N/A") -> String {
        guard let rate else { return nilLabel }
        return String(format: "%.2f%%", rate * 100.0)
    }
}
