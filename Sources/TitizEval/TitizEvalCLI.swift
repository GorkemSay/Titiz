import Foundation
import TitizCore

@main
struct TitizEvalCLI {
    static func main() {
        print("TitizEval — Offline Turkish Proofreading Evaluation Harness")
        print("TitizCore version: \(TitizEngine.version)")
        print("CHunspell bridge version: \(TitizEngine.hunspellBridgeVersion)")
        print("Status: Phase 0 bootstrap skeleton (evaluation harness arrives in Phase 2).")
    }
}
