import Foundation

/// Precedence tier explaining why a token or span is protected from modification.
public enum ProtectionTier: String, Sendable, Equatable, Codable {
    case tier0Structural
    case tier1PersonalDictionary
    case tier2ANonCollidingEntity
    case tier2BCollidingEntity
    case tier3MultiWordEntity
}

/// Specific Tier 0 structural category for an automatically protected span.
public enum StructuralProtectionKind: String, Sendable, Equatable, Codable {
    case url
    case email
    case handle
    case hashtag
    case filePath
    case inlineCode
    case allCapsAcronym
    case camelOrMixedIdentifier
    case quotedUILabel
    case numericOrVersion
}

/// Metadata attached to a protected token.
public struct ProtectionInfo: Sendable, Equatable, Codable {
    public let tier: ProtectionTier
    public let reason: String
    public let structuralKind: StructuralProtectionKind?

    public init(
        tier: ProtectionTier,
        reason: String,
        structuralKind: StructuralProtectionKind? = nil
    ) {
        self.tier = tier
        self.reason = reason
        self.structuralKind = structuralKind
    }
}

/// Lexical category of a token emitted by `StructuralLexer`.
public enum TokenKind: Sendable, Equatable {
    case word
    case apostropheWord(stem: String, apostrophe: Character, suffix: String)
    case punctuation
    case whitespace
    case protectedSpan(StructuralProtectionKind)
}

/// Single lossless lexical unit covering a contiguous slice of normalized text.
public struct Token: Sendable, Equatable {
    public let text: String
    public let range: Range<String.Index>
    public let utf16Range: UTF16Range
    public let kind: TokenKind
    public var protection: ProtectionInfo?

    public init(
        text: String,
        range: Range<String.Index>,
        utf16Range: UTF16Range,
        kind: TokenKind,
        protection: ProtectionInfo? = nil
    ) {
        self.text = text
        self.range = range
        self.utf16Range = utf16Range
        self.kind = kind
        self.protection = protection
    }

    public var isProtected: Bool {
        protection != nil
    }

    /// Underlying stem string for apostrophe-inflected words, or the full token text otherwise.
    public var stemText: String {
        switch kind {
        case let .apostropheWord(stem, _, _):
            return stem
        case .word, .punctuation, .whitespace, .protectedSpan:
            return text
        }
    }
}

/// Analyzed document produced by Phase 1 normalization, lexing, and structural protection.
public struct AnalyzedDocument: Sendable, Equatable {
    public let normalized: NormalizedText
    public let tokens: [Token]

    public init(normalized: NormalizedText, tokens: [Token]) {
        self.normalized = normalized
        self.tokens = tokens
    }
}
