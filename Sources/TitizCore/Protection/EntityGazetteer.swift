import Foundation

/// Loads bundled Wikidata CC0 collision-filtered proper-noun tiers (`Tier2A`, `Tier2B`, `Tier3`).
public struct EntityGazetteer: Sendable, Equatable {
    public let tier2A: Set<String>
    public let tier2B: Set<String>
    public let tier3Trie: MultiWordEntityTrie
    /// ASCII-folded TitleCase forms of Turkish-diacritic Tier 2A proper nouns (e.g. `Istanbul` for `İstanbul`,
    /// `Izmir` for `İzmir`, `Turkiye` for `Türkiye`) so they are restored rather than treated as English tokens.
    public let asciiFoldedTurkishTier2A: Set<String>

    public init(
        tier2A: Set<String>,
        tier2B: Set<String>,
        tier3Phrases: [String]
    ) {
        self.tier2A = tier2A
        self.tier2B = tier2B
        self.tier3Trie = MultiWordEntityTrie(phrases: tier3Phrases, caseSensitive: true)
        var foldedSet: Set<String> = []
        for entry in tier2A {
            let folded = TurkishLocale.asciiFolded(entry)
            if folded != entry {
                foldedSet.insert(folded)
            }
        }
        self.asciiFoldedTurkishTier2A = foldedSet
    }

    /// Returns `true` when `stem` matches the exact ASCII-folded form of a diacritic-bearing Tier 2A entity.
    public func isASCIIFoldedTurkishEntity(_ stem: String) -> Bool {
        asciiFoldedTurkishTier2A.contains(stem)
    }

    /// Loads `tier2a_entities.txt`, `tier2b_entities.txt`, and `tier3_entities.txt` from `TitizCore` resources.
    public static func loadBundled() throws -> EntityGazetteer {
        let t2a = try loadWordSet(named: "tier2a_entities")
        let t2b = try loadWordSet(named: "tier2b_entities")
        let t3 = try loadPhraseList(named: "tier3_entities")
        return EntityGazetteer(tier2A: t2a, tier2B: t2b, tier3Phrases: t3)
    }

    private static func loadWordSet(named name: String) throws -> Set<String> {
        guard let url = Bundle.module.url(forResource: name, withExtension: "txt") else {
            throw CharacterEngineResourceError.missingResource(name: name, extension: "txt")
        }
        let content = try String(contentsOf: url, encoding: .utf8)
        var words: Set<String> = []
        content.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                words.insert(trimmed.precomposedStringWithCanonicalMapping)
            }
        }
        return words
    }

    private static func loadPhraseList(named name: String) throws -> [String] {
        guard let url = Bundle.module.url(forResource: name, withExtension: "txt") else {
            throw CharacterEngineResourceError.missingResource(name: name, extension: "txt")
        }
        let content = try String(contentsOf: url, encoding: .utf8)
        var phrases: [String] = []
        content.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                phrases.append(trimmed.precomposedStringWithCanonicalMapping)
            }
        }
        return phrases
    }
}
