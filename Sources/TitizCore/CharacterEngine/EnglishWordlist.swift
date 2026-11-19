import Foundation

/// Errors thrown when loading bundled `CharacterEngine` resources.
public enum CharacterEngineResourceError: Error, Sendable, Equatable {
    case missingResource(name: String, extension: String)
    case invalidResourceFormat(name: String, reason: String)
}

/// Bundled ~40k common and technical English wordlist used to guard against false Turkish deasciification.
public struct EnglishWordlist: Sendable {
    private static let turkishInflectionalSuffixes: Set<String> = [
        "lar", "ler", "lari", "leri", "larin", "lerin", "larini", "lerini", "larina", "lerine",
        "larda", "lerde", "lardan", "lerden", "larla", "lerle", "im", "in", "un", "um",
        "imiz", "iniz", "umuz", "unuz", "i", "u", "a", "e", "da", "de", "ta", "te",
        "dan", "den", "tan", "ten", "la", "le", "yla", "yle",
        "si", "su", "sin", "sun", "sini", "sunu", "sina", "suna", "sinda", "sunda",
        "sindan", "sundan", "ini", "unu", "ina", "una", "inda", "unda", "indan", "undan",
        "li", "lu", "lik", "luk", "siz", "suz"
    ]

    private let words: Set<String>

    public var count: Int {
        words.count
    }

    public init(words: Set<String>) {
        self.words = words
    }

    /// Loads `en_common_tech.txt` from `TitizCore` module resources.
    public static func loadBundled() throws -> EnglishWordlist {
        guard let url = Bundle.module.url(forResource: "en_common_tech", withExtension: "txt") else {
            throw CharacterEngineResourceError.missingResource(name: "en_common_tech", extension: "txt")
        }
        let content = try String(contentsOf: url, encoding: .utf8)
        var parsed: Set<String> = []
        parsed.reserveCapacity(42_000)

        content.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                parsed.insert(trimmed)
            }
        }

        return EnglishWordlist(words: parsed)
    }

    /// Returns `true` if `word` is an ASCII word matching the English common+tech wordlist (case-insensitive).
    public func contains(_ word: String) -> Bool {
        guard !word.isEmpty, word.allSatisfy(\.isASCII) else {
            return false
        }
        return words.contains(word.lowercased())
    }

    /// Returns `true` when an ASCII word consists of an English stem (length >= 3) followed by
    /// a productive Turkish inflectional suffix (e.g., `loglarini` = `log` + `larini`).
    public func containsForeignStemWithTurkishSuffix(_ word: String) -> Bool {
        guard word.count >= 5, word.allSatisfy(\.isASCII) else {
            return false
        }
        let lower = word.lowercased()
        let chars = Array(lower)
        let maxStemLen = chars.count - 1
        guard maxStemLen >= 3 else { return false }

        for splitIdx in 3...maxStemLen {
            let suffix = String(chars[splitIdx...])
            guard Self.turkishInflectionalSuffixes.contains(suffix) else { continue }
            let stem = String(chars[0..<splitIdx])
            if words.contains(stem) {
                return true
            }
        }
        return false
    }
}
