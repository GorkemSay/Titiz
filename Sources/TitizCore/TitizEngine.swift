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

    /// Runs Phase 1 UTF-8 NFC normalization, structural lexing, and Tier 0 protection.
    public func analyze(_ text: String) -> AnalyzedDocument {
        let normalized = TextNormalizer.normalize(text)
        let lexed = StructuralLexer.tokenize(normalized)
        let protectedTokens = Tier0Protector.apply(to: lexed)
        return AnalyzedDocument(normalized: normalized, tokens: protectedTokens)
    }

    /// Processes input text under the specified correction mode.
    ///
    /// Character and spelling rewrite engines arrive in Phases 3–5; currently runs analysis and preserves input untouched.
    public func correct(_ text: String, mode: CorrectionMode = .combined) -> CorrectionResult {
        _ = analyze(text)
        return CorrectionResult(
            originalText: text,
            correctedText: text,
            mode: mode
        )
    }
}
