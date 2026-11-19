import Foundation

/// Available proofreading operating modes in Titiz.
public enum CorrectionMode: String, Sendable, CaseIterable, Codable {
    /// Restores missing Turkish diacritics from ASCII input (one-way).
    case character
    /// Fixes deterministic high-confidence TDK spelling and punctuation errors.
    case spelling
    /// Runs character restoration and spelling rules together, including joint split-and-deasciify.
    case combined
}

/// Result returned by `TitizEngine` for a proofreading pass.
public struct CorrectionResult: Sendable, Equatable {
    public let originalText: String
    public let correctedText: String
    public let mode: CorrectionMode

    public init(originalText: String, correctedText: String, mode: CorrectionMode) {
        self.originalText = originalText
        self.correctedText = correctedText
        self.mode = mode
    }
}
