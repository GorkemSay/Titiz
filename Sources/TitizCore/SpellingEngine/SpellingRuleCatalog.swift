import Foundation

/// Example pair illustrating a deterministic proofreading rule.
public struct RuleExample: Codable, Sendable, Equatable {
    public let before: String
    public let after: String

    public init(before: String, after: String) {
        self.before = before
        self.after = after
    }
}

/// Human-readable metadata for a deterministic rule displayed in the Titiz UI popover.
public struct SpellingRuleMetadata: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let explanationTR: String
    public let tdkReferenceURL: String
    public let examples: [RuleExample]

    public init(
        id: String,
        name: String,
        explanationTR: String,
        tdkReferenceURL: String,
        examples: [RuleExample]
    ) {
        self.id = id
        self.name = name
        self.explanationTR = explanationTR
        self.tdkReferenceURL = tdkReferenceURL
        self.examples = examples
    }
}

/// Closed-set high-precision TDK spelling fix loaded from `rules.json`.
public struct ClosedTDKFixEntry: Codable, Sendable, Equatable {
    public let wrong: String
    public let correct: String
    public let ruleID: String
    public let asciiVariantOnly: Bool

    public init(wrong: String, correct: String, ruleID: String, asciiVariantOnly: Bool) {
        self.wrong = wrong
        self.correct = correct
        self.ruleID = ruleID
        self.asciiVariantOnly = asciiVariantOnly
    }
}

/// Catalog of rule explanations and closed TDK spelling fixes loaded from `rules.json`.
public struct SpellingRuleCatalog: Sendable, Equatable {
    private struct Payload: Codable {
        let schemaVersion: String
        let rules: [SpellingRuleMetadata]
        let closedTDKFixes: [ClosedTDKFixEntry]
    }

    public let rulesByID: [String: SpellingRuleMetadata]
    public let closedTDKFixesByWrongLower: [String: ClosedTDKFixEntry]

    public init(rules: [SpellingRuleMetadata], closedTDKFixes: [ClosedTDKFixEntry]) {
        self.rulesByID = Dictionary(uniqueKeysWithValues: rules.map { ($0.id, $0) })
        self.closedTDKFixesByWrongLower = Dictionary(
            uniqueKeysWithValues: closedTDKFixes.map { ($0.wrong.precomposedStringWithCanonicalMapping, $0) }
        )
    }

    /// Loads `rules.json` from `TitizCore` module resources.
    public static func loadBundled() throws -> SpellingRuleCatalog {
        guard let url = Bundle.module.url(forResource: "rules", withExtension: "json") else {
            throw CharacterEngineResourceError.missingResource(name: "rules", extension: "json")
        }
        let data = try Data(contentsOf: url)
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return SpellingRuleCatalog(rules: payload.rules, closedTDKFixes: payload.closedTDKFixes)
    }

    public func metadata(for ruleID: String) -> SpellingRuleMetadata? {
        rulesByID[ruleID]
    }

    /// Looks up a closed-set TDK replacement preserving initial sentence/TitleCase capitalization.
    public func closedFix(for word: String, includeASCIIJointVariants: Bool) -> (replacement: String, ruleID: String)? {
        let nfc = word.precomposedStringWithCanonicalMapping
        guard !nfc.isEmpty else { return nil }

        let lowered = TurkishLocale.lowercased(nfc)
        guard let entry = closedTDKFixesByWrongLower[lowered] else {
            return nil
        }

        if entry.asciiVariantOnly && !includeASCIIJointVariants {
            return nil
        }

        let isTitleCase = nfc.first?.isUppercase == true && nfc.dropFirst().allSatisfy(\.isLowercase)
        let isAllLower = nfc == lowered

        guard isTitleCase || isAllLower else {
            // Preserve unexpected mixed/all-caps casing conservatively.
            return nil
        }

        let rendered = isTitleCase
            ? TurkishLocale.capitalizedFirstCharacter(entry.correct)
            : entry.correct
        return (rendered, entry.ruleID)
    }
}
