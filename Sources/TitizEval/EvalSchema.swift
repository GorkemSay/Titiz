import Foundation
import TitizCore

/// Classification of an expected edit for bucket-level recall reporting.
public enum EditBucket: String, Codable, Sendable, CaseIterable {
    case bucket1
    case bucket2
    case spelling
    case spellingJoint = "spelling_joint"
}

/// Pipeline stage that owns an expected edit.
public enum EditOrigin: String, Codable, Sendable, CaseIterable {
    case character
    case spelling
}

/// Protection tier expected to preserve a span untouched.
public enum EvalProtectionTier: String, Codable, Sendable, CaseIterable {
    case tier0
    case tier1
    case tier2A
    case tier2B
    case tier3
    case foreignTerm = "foreign_term"
}

/// Linguistic / functional test slice category.
public enum EvalCategory: String, Codable, Sendable, CaseIterable {
    case clean
    case asciiTurkish = "ascii_turkish"
    case mixedDiacritics = "mixed_diacritics"
    case codeSwitched = "code_switched"
    case collidingEntities = "colliding_entities"
    case minimalPairs = "minimal_pairs"
    case punctuationSpacing = "punctuation_spacing"
    case capitalization
    case questionParticle = "question_particle"
    case closedTDK = "closed_tdk"
    case fusedClitics = "fused_clitics"
    case outOfScopeGuard = "out_of_scope_guard"
    case structuralTier0 = "structural_tier0"
    case personalDictionary = "personal_dictionary"
}

/// Expected token/phrase rewrite inside an evaluation case.
public struct ExpectedEdit: Codable, Sendable, Equatable {
    public let original: String
    public let expected: String
    public let bucket: EditBucket
    public let origin: EditOrigin

    public init(original: String, expected: String, bucket: EditBucket, origin: EditOrigin) {
        self.original = original
        self.expected = expected
        self.bucket = bucket
        self.origin = origin
    }
}

/// Expected preserved span and its protection tier.
public struct ProtectedSpanExpectation: Codable, Sendable, Equatable {
    public let text: String
    public let tier: EvalProtectionTier

    public init(text: String, tier: EvalProtectionTier) {
        self.text = text
        self.tier = tier
    }
}

/// Single evaluation fixture inside a dev or held-out blind dataset.
public struct EvalCase: Codable, Sendable, Equatable {
    public let id: String
    public let mode: CorrectionMode
    public let category: EvalCategory
    public let isCleanSentence: Bool
    public let input: String
    public let expected: String
    public let personalDictionary: [String]?
    public let expectedEdits: [ExpectedEdit]
    public let protectedSpans: [ProtectedSpanExpectation]?
    public let notes: String?

    public init(
        id: String,
        mode: CorrectionMode,
        category: EvalCategory,
        isCleanSentence: Bool,
        input: String,
        expected: String,
        personalDictionary: [String]? = nil,
        expectedEdits: [ExpectedEdit],
        protectedSpans: [ProtectedSpanExpectation]? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.mode = mode
        self.category = category
        self.isCleanSentence = isCleanSentence
        self.input = input
        self.expected = expected
        self.personalDictionary = personalDictionary
        self.expectedEdits = expectedEdits
        self.protectedSpans = protectedSpans
        self.notes = notes
    }
}

/// Root JSON container for `Datasets/dev_cases.json` and blind evaluation sets.
public struct EvalDataset: Codable, Sendable, Equatable {
    public let schemaVersion: String
    public let datasetName: String
    public let description: String
    public let cases: [EvalCase]

    public init(schemaVersion: String, datasetName: String, description: String, cases: [EvalCase]) {
        self.schemaVersion = schemaVersion
        self.datasetName = datasetName
        self.description = description
        self.cases = cases
    }

    public static func load(from url: URL) throws -> EvalDataset {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(EvalDataset.self, from: data)
    }
}
