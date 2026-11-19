import Foundation

/// One-way GPA prediction for a single ASCII candidate character inside a word.
public struct GPACharPrediction: Sendable, Equatable {
    /// Character index within the word (`0..<word.count`).
    public let index: Int
    /// Whether the GPA decision list predicts the Turkish diacritic (`true`) or ASCII (`false`) form.
    public let wantsDiacritic: Bool
    /// Signed rule rank from the decision list (smaller `abs(rank)` indicates stronger rule priority).
    public let rank: Int

    public init(index: Int, wantsDiacritic: Bool, rank: Int) {
        self.index = index
        self.wantsDiacritic = wantsDiacritic
        self.rank = rank
    }
}

/// Strictly one-way Swift implementation of Deniz Yüret's GPA Turkish deasciifier decision-list scorer
/// (MIT-licensed algorithm & pattern tables from `denizyuret/deasciify`).
///
/// - Important: Evaluates ONLY ASCII candidate characters (`c, g, i, o, s, u, C, G, I, O, S, U`).
///   Existing Turkish diacritics (`ç, ğ, ı, İ, ö, ş, ü`) are never evaluated or reversed.
public struct GPAScorer: Sendable {
    private static let contextSize = 10
    private static let fnvOffsetBasis: UInt64 = 14695981039346656037
    private static let fnvPrime: UInt64 = 1099511628211

    private static let asciiCandidateBase: [Character: Character] = [
        "c": "c", "C": "c",
        "g": "g", "G": "g",
        "i": "i", "I": "i",
        "o": "o", "O": "o",
        "s": "s", "S": "s",
        "u": "u", "U": "u"
    ]

    private static let downcaseAsciifyBytes: [Character: UInt8] = {
        var map: [Character: UInt8] = [
            "ç": UInt8(ascii: "c"), "Ç": UInt8(ascii: "c"),
            "ğ": UInt8(ascii: "g"), "Ğ": UInt8(ascii: "g"),
            "ı": UInt8(ascii: "i"), "İ": UInt8(ascii: "i"),
            "ö": UInt8(ascii: "o"), "Ö": UInt8(ascii: "o"),
            "ş": UInt8(ascii: "s"), "Ş": UInt8(ascii: "s"),
            "ü": UInt8(ascii: "u"), "Ü": UInt8(ascii: "u")
        ]
        for b in UInt8(ascii: "a")...UInt8(ascii: "z") {
            map[Character(UnicodeScalar(b))] = b
        }
        for b in UInt8(ascii: "A")...UInt8(ascii: "Z") {
            map[Character(UnicodeScalar(b))] = b + 32
        }
        return map
    }()

    private static let upcaseAccentsBytes: [Character: UInt8] = {
        var map: [Character: UInt8] = [
            "ç": UInt8(ascii: "C"), "Ç": UInt8(ascii: "C"),
            "ğ": UInt8(ascii: "G"), "Ğ": UInt8(ascii: "G"),
            "ö": UInt8(ascii: "O"), "Ö": UInt8(ascii: "O"),
            "ş": UInt8(ascii: "S"), "Ş": UInt8(ascii: "S"),
            "ü": UInt8(ascii: "U"), "Ü": UInt8(ascii: "U"),
            "İ": UInt8(ascii: "i"),
            "ı": UInt8(ascii: "I")
        ]
        for b in UInt8(ascii: "a")...UInt8(ascii: "z") {
            map[Character(UnicodeScalar(b))] = b
        }
        for b in UInt8(ascii: "A")...UInt8(ascii: "Z") {
            map[Character(UnicodeScalar(b))] = b + 32
        }
        map["i"] = UInt8(ascii: "i")
        map["I"] = UInt8(ascii: "I")
        return map
    }()

    private let hashedPatternTables: [Character: [UInt64: Int]]
    private let patternCounts: [Character: Int]
    private let maxLeftRadius: Int
    private let maxRightRadius: Int

    /// Loads `gpa_patterns.json` from `TitizCore` module resources.
    public static func loadBundled() throws -> GPAScorer {
        guard let url = Bundle.module.url(forResource: "gpa_patterns", withExtension: "json") else {
            throw CharacterEngineResourceError.missingResource(name: "gpa_patterns", extension: "json")
        }
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode([String: [String: Int]].self, from: data)
        var tables: [Character: [String: Int]] = [:]
        for (key, value) in decoded where key.count == 1 {
            if let ch = key.first {
                tables[ch] = value
            }
        }
        return GPAScorer(patternTables: tables)
    }

    public init(patternTables: [Character: [String: Int]]) {
        var hashed: [Character: [UInt64: Int]] = [:]
        var counts: [Character: Int] = [:]
        var maxLeft = 0
        var maxRight = 0

        for (letter, table) in patternTables {
            counts[letter] = table.count
            var hTable: [UInt64: Int] = [:]
            hTable.reserveCapacity(table.count)
            for (pattern, rank) in table {
                let hash = Self.fnv1a64ASCII(pattern)
                if let existing = hTable[hash] {
                    if abs(rank) < abs(existing) {
                        hTable[hash] = rank
                    }
                } else {
                    hTable[hash] = rank
                }
                if let xIdx = pattern.firstIndex(of: "X") {
                    let left = pattern.distance(from: pattern.startIndex, to: xIdx)
                    let right = pattern.distance(from: pattern.index(after: xIdx), to: pattern.endIndex)
                    maxLeft = max(maxLeft, left)
                    maxRight = max(maxRight, right)
                }
            }
            hashed[letter] = hTable
        }

        self.hashedPatternTables = hashed
        self.patternCounts = counts
        self.maxLeftRadius = min(Self.contextSize, maxLeft)
        self.maxRightRadius = min(Self.contextSize, maxRight)
    }

    public func patternCount(for baseLetter: Character) -> Int {
        patternCounts[baseLetter] ?? 0
    }

    /// Evaluates every ASCII candidate character (`c, g, i, o, s, u, C, G, I, O, S, U`) in `word`
    /// using its surrounding sentence context. Never evaluates already-Turkish diacritics.
    public func predictions(
        for word: String,
        inSentence sentence: String,
        wordRange: Range<String.Index>
    ) -> [GPACharPrediction] {
        var results: [GPACharPrediction] = []
        var charOffset = 0
        var cursor = wordRange.lowerBound
        var contextBuffer = Array(repeating: UInt8(ascii: " "), count: 2 * Self.contextSize + 1)

        while cursor < wordRange.upperBound {
            let ch = sentence[cursor]
            if let base = Self.asciiCandidateBase[ch], let table = hashedPatternTables[base] {
                let contextCount = fillContext(in: sentence, at: cursor, buffer: &contextBuffer)
                let fallback = 2 * max(1, patternCounts[base] ?? 1)
                let bestRank = matchBestRank(in: contextBuffer, count: contextCount, table: table, fallbackRank: fallback)
                let m = bestRank > 0
                // In Turkish GPA, positive polarity means dotless 'ı'/'I', negative means dotted 'i'/'İ'.
                // Thus ASCII uppercase 'I' requires conversion to 'İ' only when m == false.
                let wantsDiacritic = (ch == "I") ? !m : m
                results.append(GPACharPrediction(index: charOffset, wantsDiacritic: wantsDiacritic, rank: bestRank))
            }
            cursor = sentence.index(after: cursor)
            charOffset += 1
        }

        return results
    }

    /// Returns the direct one-way GPA prediction for `word` without checking Hunspell validity.
    public func oneWayPredictedWord(
        for word: String,
        inSentence sentence: String,
        wordRange: Range<String.Index>
    ) -> String {
        let preds = predictions(for: word, inSentence: sentence, wordRange: wordRange)
        guard !preds.isEmpty else {
            return word
        }

        var chars = Array(word)
        for pred in preds where pred.wantsDiacritic {
            if let replacement = CandidateGenerator.turkishCounterpart(for: chars[pred.index]) {
                chars[pred.index] = replacement
            }
        }
        return String(chars)
    }

    /// Computes a rank-weighted agreement score between `candidate` and the GPA predictions recorded
    /// for `original`, preserving rule-strength magnitude (weak fallback rules near rank ~3,000 do
    /// not get inflated to full +/-1.0 confidence).
    public func agreementScore(
        candidate: String,
        original: String,
        predictions: [GPACharPrediction]
    ) -> Double {
        guard !predictions.isEmpty else {
            return 0.0
        }

        let origChars = Array(original)
        let candChars = Array(candidate)
        guard origChars.count == candChars.count else {
            return 0.0
        }

        var weightedSum = 0.0
        for pred in predictions where pred.index < origChars.count {
            let weight = 1.0 / log2(Double(abs(pred.rank)) + 2.0)
            let turnedTurkish = candChars[pred.index] != origChars[pred.index]
            let agrees = turnedTurkish == pred.wantsDiacritic
            weightedSum += agrees ? weight : -weight
        }

        return weightedSum / Double(predictions.count)
    }

    // MARK: - Private Zero-Allocation GPA Context & Hash Matching

    private func fillContext(
        in sentence: String,
        at targetIndex: String.Index,
        buffer: inout [UInt8]
    ) -> Int {
        for i in 0..<Self.contextSize {
            buffer[i] = UInt8(ascii: " ")
        }
        buffer[Self.contextSize] = UInt8(ascii: "X")

        var leftSlot = Self.contextSize - 1
        var sawSpace = false
        var backCursor = targetIndex

        while leftSlot >= 0, backCursor > sentence.startIndex {
            backCursor = sentence.index(before: backCursor)
            let ch = sentence[backCursor]
            if let mapped = Self.upcaseAccentsBytes[ch] {
                buffer[leftSlot] = mapped
                leftSlot -= 1
                sawSpace = false
            } else if !sawSpace {
                buffer[leftSlot] = UInt8(ascii: " ")
                leftSlot -= 1
                sawSpace = true
            }
        }

        var rightCursor = Self.contextSize + 1
        var fwdCursor = sentence.index(after: targetIndex)
        let limit = 2 * Self.contextSize + 1

        while rightCursor < limit, fwdCursor < sentence.endIndex {
            let ch = sentence[fwdCursor]
            if let mapped = Self.downcaseAsciifyBytes[ch] {
                buffer[rightCursor] = mapped
                rightCursor += 1
                fwdCursor = sentence.index(after: fwdCursor)
            } else {
                buffer[rightCursor] = UInt8(ascii: " ")
                rightCursor += 1
                break
            }
        }

        return rightCursor
    }

    private func matchBestRank(
        in contextBytes: [UInt8],
        count: Int,
        table: [UInt64: Int],
        fallbackRank: Int
    ) -> Int {
        let xIndex = Self.contextSize
        let minStart = max(0, xIndex - maxLeftRadius)
        let maxEnd = min(count, xIndex + 1 + maxRightRadius)

        var bestRank = fallbackRank

        for start in minStart...xIndex {
            var hash = Self.fnvOffsetBasis
            for idx in start..<xIndex {
                hash ^= UInt64(contextBytes[idx])
                hash &*= Self.fnvPrime
            }
            for idx in xIndex..<maxEnd {
                hash ^= UInt64(contextBytes[idx])
                hash &*= Self.fnvPrime
                if let rank = table[hash], abs(rank) < abs(bestRank) {
                    bestRank = rank
                }
            }
        }

        return bestRank
    }

    private static func fnv1a64ASCII(_ string: String) -> UInt64 {
        var hash = fnvOffsetBasis
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= fnvPrime
        }
        return hash
    }
}
