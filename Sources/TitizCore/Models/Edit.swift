import Foundation

/// Pipeline stage that originated a proofreading edit.
public enum EditOrigin: String, Sendable, Equatable, Codable {
    case character
    case spelling
}

/// Decision bucket assigned by the 3-bucket character restoration engine.
public enum CharacterBucket: String, Sendable, Equatable, Codable {
    case bucket0
    case bucket1
    case bucket2
}

/// Provenance record describing a single applied edit and its UTF-16 ranges in both source and output text.
public struct Edit: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public let origin: EditOrigin
    public let ruleID: String
    public let bucket: CharacterBucket?
    public let confidence: Double
    public let original: String
    public let replacement: String
    public let alternatives: [String]
    public let originalRange: UTF16Range
    public let correctedRange: UTF16Range

    public init(
        id: UUID = UUID(),
        origin: EditOrigin,
        ruleID: String,
        bucket: CharacterBucket? = nil,
        confidence: Double,
        original: String,
        replacement: String,
        alternatives: [String] = [],
        originalRange: UTF16Range,
        correctedRange: UTF16Range
    ) {
        self.id = id
        self.origin = origin
        self.ruleID = ruleID
        self.bucket = bucket
        self.confidence = confidence
        self.original = original
        self.replacement = replacement
        self.alternatives = alternatives
        self.originalRange = originalRange
        self.correctedRange = correctedRange
    }
}

/// Ranked candidate alternatives attached when a Bucket 2 token is preserved conservatively.
public struct AmbiguousTokenSuggestion: Sendable, Equatable, Codable {
    public let original: String
    public let originalRange: UTF16Range
    public let correctedRange: UTF16Range
    public let candidates: [String]

    public init(
        original: String,
        originalRange: UTF16Range,
        correctedRange: UTF16Range? = nil,
        candidates: [String]
    ) {
        self.original = original
        self.originalRange = originalRange
        self.correctedRange = correctedRange ?? originalRange
        self.candidates = candidates
    }
}
