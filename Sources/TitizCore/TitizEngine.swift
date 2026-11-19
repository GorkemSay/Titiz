import CHunspell
import Foundation

/// Pure Swift, deterministic Turkish proofreading engine.
public struct TitizEngine: Sendable {
    /// Semantic development version of the TitizCore engine.
    public static let version = "0.1.0-dev"

    /// Version string exposed by the underlying `CHunspell` bridge.
    public static var hunspellBridgeVersion: String {
        String(cString: chunspell_bridge_version())
    }

    public init() {}

    /// Processes input text under the specified correction mode.
    ///
    /// Phase 0 bootstrap implementation returns the original text untouched.
    public func correct(_ text: String, mode: CorrectionMode = .combined) -> CorrectionResult {
        CorrectionResult(
            originalText: text,
            correctedText: text,
            mode: mode
        )
    }
}
