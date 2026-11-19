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

    public let resources: TitizResources
    private let characterEngine: CharacterEngine

    public init(
        resources: TitizResources = .shared,
        characterConfig: CharacterEngineConfiguration = .default
    ) {
        self.resources = resources
        self.characterEngine = CharacterEngine(
            dictionary: resources.dictionary,
            gpaScorer: resources.gpaScorer,
            englishWordlist: resources.englishWordlist,
            frequencyTable: resources.frequencyTable,
            config: characterConfig
        )
    }

    /// Runs Phase 1 UTF-8 NFC normalization, structural lexing, and Tier 0 protection.
    public func analyze(_ text: String) -> AnalyzedDocument {
        let normalized = TextNormalizer.normalize(text)
        let lexed = StructuralLexer.tokenize(normalized)
        let protectedTokens = Tier0Protector.apply(to: lexed)
        return AnalyzedDocument(normalized: normalized, tokens: protectedTokens)
    }

    /// Processes input text under the specified correction mode.
    public func correct(_ text: String, mode: CorrectionMode = .combined) -> CorrectionResult {
        let analyzed = analyze(text)

        switch mode {
        case .character:
            return characterEngine.process(analyzed)
        case .spelling:
            // Deterministic TDK spelling & punctuation rules arrive in Phase 5.
            return CorrectionResult(
                originalText: analyzed.normalized.original,
                correctedText: analyzed.normalized.original,
                mode: .spelling
            )
        case .combined:
            // Phase 4 adds Tier 1-3 protection and Phase 5 adds Spelling + Joint split-and-deasciify.
            let charResult = characterEngine.process(analyzed)
            return CorrectionResult(
                originalText: charResult.originalText,
                correctedText: charResult.correctedText,
                mode: .combined,
                edits: charResult.edits,
                ambiguousSuggestions: charResult.ambiguousSuggestions
            )
        }
    }
}
