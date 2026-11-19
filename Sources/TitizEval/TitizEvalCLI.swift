import Foundation
import TitizCore

private struct CLIOptions {
    var datasetPath: String = "Datasets/dev_cases.json"
    var blindPath: String?
    var blindOnly: Bool = false
    var modeFilter: CorrectionMode?
    var latencyIterations: Int = 50
    var skipLatency: Bool = false
    var jsonOutput: Bool = false
    var verbose: Bool = false
    var enforceGates: Bool = false
    var showHelp: Bool = false
}

private enum CLIError: Error, CustomStringConvertible {
    case invalidArguments(String)
    case invalidDataset(String, [String])

    var description: String {
        switch self {
        case let .invalidArguments(message):
            return "Argument error: \(message)"
        case let .invalidDataset(path, issues):
            return "Dataset validation failed for '\(path)':\n" + issues.map { "  - \($0)" }.joined(separator: "\n")
        }
    }
}

@main
struct TitizEvalCLI {
    static func main() {
        do {
            let options = try parseArguments(Array(CommandLine.arguments.dropFirst()))
            if options.showHelp {
                printUsage()
                return
            }

            let engine = TitizEngine()
            let latencyReport = options.skipLatency
                ? nil
                : LatencyBenchmarker.measure(using: engine, iterations: options.latencyIterations)

            var exitCode: Int32 = 0

            if !options.blindOnly {
                let devURL = URL(fileURLWithPath: options.datasetPath)
                let devDataset = try EvalDataset.load(from: devURL)
                let devIssues = EvalScorer.validateDataset(devDataset)
                if !devIssues.isEmpty {
                    throw CLIError.invalidDataset(options.datasetPath, devIssues)
                }

                let report = EvalScorer.evaluate(
                    dataset: devDataset,
                    using: engine,
                    modeFilter: options.modeFilter,
                    latency: latencyReport
                )

                if options.jsonOutput {
                    print(try ReportFormatter.formatJSON(report: report, isBlind: false))
                } else {
                    print(ReportFormatter.formatText(report: report, verbose: options.verbose, isBlind: false))
                }

                if options.enforceGates && !report.allGatesPass {
                    exitCode = 2
                }
            }

            if let blindPath = options.blindPath {
                let blindURL = URL(fileURLWithPath: blindPath)
                let blindDataset = try EvalDataset.load(from: blindURL)
                let blindIssues = EvalScorer.validateDataset(blindDataset)
                if !blindIssues.isEmpty {
                    throw CLIError.invalidDataset(blindPath, blindIssues)
                }

                let blindReport = EvalScorer.evaluate(
                    dataset: blindDataset,
                    using: engine,
                    modeFilter: options.modeFilter,
                    latency: options.blindOnly ? latencyReport : nil
                )

                if options.jsonOutput {
                    print(try ReportFormatter.formatJSON(report: blindReport, isBlind: true))
                } else {
                    if !options.blindOnly {
                        print("")
                    }
                    print(ReportFormatter.formatText(report: blindReport, verbose: options.verbose, isBlind: true))
                }

                if options.enforceGates && !blindReport.allGatesPass {
                    exitCode = 2
                }
            }

            if exitCode != 0 {
                Foundation.exit(exitCode)
            }
        } catch let error as CLIError {
            FileHandle.standardError.write(Data((error.description + "\n").utf8))
            Foundation.exit(1)
        } catch {
            FileHandle.standardError.write(Data(("Error: \(error.localizedDescription)\n").utf8))
            Foundation.exit(1)
        }
    }

    private static func parseArguments(_ args: [String]) throws -> CLIOptions {
        var options = CLIOptions()
        var index = 0

        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--dataset":
                index += 1
                guard index < args.count else {
                    throw CLIError.invalidArguments("--dataset requires a file path.")
                }
                options.datasetPath = args[index]
            case "--blind":
                index += 1
                guard index < args.count else {
                    throw CLIError.invalidArguments("--blind requires a file path.")
                }
                options.blindPath = args[index]
            case "--blind-only":
                options.blindOnly = true
            case "--mode":
                index += 1
                guard index < args.count else {
                    throw CLIError.invalidArguments("--mode requires character, spelling, combined, or all.")
                }
                let raw = args[index]
                if raw == "all" {
                    options.modeFilter = nil
                } else if let mode = CorrectionMode(rawValue: raw) {
                    options.modeFilter = mode
                } else {
                    throw CLIError.invalidArguments("Unknown mode '\(raw)'. Expected character, spelling, combined, or all.")
                }
            case "--latency-iterations":
                index += 1
                guard index < args.count, let count = Int(args[index]), count > 0 else {
                    throw CLIError.invalidArguments("--latency-iterations requires a positive integer.")
                }
                options.latencyIterations = count
            case "--skip-latency":
                options.skipLatency = true
            case "--json":
                options.jsonOutput = true
            case "--verbose":
                options.verbose = true
            case "--enforce-gates":
                options.enforceGates = true
            case "--help", "-h":
                options.showHelp = true
            default:
                throw CLIError.invalidArguments("Unknown option '\(arg)'. Pass --help for usage.")
            }
            index += 1
        }

        if options.blindOnly && options.blindPath == nil {
            throw CLIError.invalidArguments("--blind-only requires --blind <path>.")
        }

        return options
    }

    private static func printUsage() {
        let usage = """
        TitizEval — Offline Turkish Proofreading Evaluation & Latency Harness

        Usage:
          swift run TitizEval [options]

        Options:
          --dataset <path>              Path to dev dataset (default: Datasets/dev_cases.json)
          --blind <path>                Evaluate a held-out blind dataset (summary-only output)
          --blind-only                  Evaluate only the dataset passed to --blind
          --mode <mode>                 Filter cases: character | spelling | combined | all (default: all)
          --latency-iterations <int>    Timed runs per latency sample (default: 50)
          --skip-latency                Skip latency benchmarking
          --json                        Emit JSON report instead of plain text
          --verbose                     Print mismatched dev cases (suppressed for blind datasets)
          --enforce-gates               Exit with code 2 if any quality or latency gate fails
          -h, --help                    Show this help message
        """
        print(usage)
    }
}
