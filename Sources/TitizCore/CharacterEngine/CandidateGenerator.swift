import Foundation

/// Output of one-way Turkish diacritic candidate generation for a single stem token.
public struct CandidateGenerationResult: Sendable, Equatable {
    public let original: String
    public let originalIsValid: Bool
    /// Valid Turkish dictionary candidates generated solely via one-way ASCII -> diacritic conversion.
    public let validAlternatives: [String]
    /// Number of ASCII mutable positions evaluated.
    public let mutableCount: Int

    public init(
        original: String,
        originalIsValid: Bool,
        validAlternatives: [String],
        mutableCount: Int = 0
    ) {
        self.original = original
        self.originalIsValid = originalIsValid
        self.validAlternatives = validAlternatives
        self.mutableCount = mutableCount
    }
}

/// Strictly one-way candidate generator with Turkish phonological pruning and combinatorial caps.
public enum CandidateGenerator {
    public static let maxDictionaryProbes = 128

    private static let oneWayMap: [Character: Character] = [
        "c": "ç", "C": "Ç",
        "g": "ğ", "G": "Ğ",
        "i": "ı", "I": "İ",
        "o": "ö", "O": "Ö",
        "s": "ş", "S": "Ş",
        "u": "ü", "U": "Ü"
    ]

    private static let frontVowels: Set<Character> = ["e", "i", "ö", "ü", "E", "İ", "Ö", "Ü"]
    private static let backVowels: Set<Character> = ["a", "ı", "o", "u", "A", "I", "O", "U"]

    public static func turkishCounterpart(for character: Character) -> Character? {
        oneWayMap[character]
    }

    /// Counts ASCII mutable positions (`c, g, i, o, s, u, C, G, I, O, S, U`, skipping initial `g/G`).
    public static func mutablePositions(in chars: [Character]) -> [Int] {
        var mutableIndices: [Int] = []
        mutableIndices.reserveCapacity(chars.count)
        for index in chars.indices {
            let ch = chars[index]
            guard oneWayMap[ch] != nil else { continue }
            if index == 0 && (ch == "g" || ch == "G") {
                continue
            }
            mutableIndices.append(index)
        }
        return mutableIndices
    }

    /// Validates `candidate` against Hunspell, handling TitleCase words (`Dışarı` -> `dışarı`).
    public static func isValidTurkishWord(_ candidate: String, dictionary: HunspellDictionary) -> Bool {
        if dictionary.contains(candidate) {
            return true
        }
        if isTitleCase(candidate) {
            let lowered = TurkishLocale.lowercased(candidate)
            if lowered != candidate && dictionary.contains(lowered, assumeNFC: true) {
                return true
            }
        }
        return false
    }

    /// Generates valid Turkish diacritic candidates for `word` without ever removing existing Turkish diacritics.
    public static func generate(
        for word: String,
        gpaPredictions: [GPACharPrediction],
        dictionary: HunspellDictionary
    ) -> CandidateGenerationResult {
        let chars = Array(word)
        guard chars.count >= 2 else {
            return CandidateGenerationResult(original: word, originalIsValid: false, validAlternatives: [], mutableCount: 0)
        }

        let mutableIndices = mutablePositions(in: chars)
        guard !mutableIndices.isEmpty else {
            return CandidateGenerationResult(original: word, originalIsValid: false, validAlternatives: [], mutableCount: 0)
        }

        let candidateStrings: [String]
        if mutableIndices.count <= 7 {
            candidateStrings = enumerateExhaustive(chars: chars, mutableIndices: mutableIndices)
        } else {
            candidateStrings = generateBoundedCandidates(
                chars: chars,
                mutableIndices: mutableIndices,
                gpaPredictions: gpaPredictions,
                limit: maxDictionaryProbes
            )
        }

        let titleCase = isTitleCase(word)
        let probePool = [word] + candidateStrings.filter { $0 != word }

        if titleCase {
            var expanded: [String] = []
            expanded.reserveCapacity(probePool.count * 2)
            for item in probePool {
                expanded.append(item)
                expanded.append(TurkishLocale.lowercased(item))
            }
            let batchFlags = dictionary.containsBatch(expanded, assumeNFC: true)
            let origValid = batchFlags[0] || batchFlags[1]
            var validAlternatives: [String] = []
            for idx in 1..<probePool.count {
                if batchFlags[idx * 2] || batchFlags[idx * 2 + 1] {
                    validAlternatives.append(probePool[idx])
                }
            }
            return CandidateGenerationResult(
                original: word,
                originalIsValid: origValid,
                validAlternatives: validAlternatives,
                mutableCount: mutableIndices.count
            )
        }

        let batchFlags = dictionary.containsBatch(probePool, assumeNFC: true)
        let origValid = batchFlags[0]
        var validAlternatives: [String] = []
        for idx in 1..<probePool.count where batchFlags[idx] {
            validAlternatives.append(probePool[idx])
        }

        return CandidateGenerationResult(
            original: word,
            originalIsValid: origValid,
            validAlternatives: validAlternatives,
            mutableCount: mutableIndices.count
        )
    }

    // MARK: - Private Enumeration & Bounded Search

    private static func enumerateExhaustive(chars: [Character], mutableIndices: [Int]) -> [String] {
        let count = mutableIndices.count
        let totalMasks = 1 << count
        var results: [String] = []
        results.reserveCapacity(totalMasks - 1)

        var buffer = chars
        for mask in 1..<totalMasks {
            for bit in 0..<count {
                let idx = mutableIndices[bit]
                if (mask & (1 << bit)) != 0, let tr = oneWayMap[chars[idx]] {
                    buffer[idx] = tr
                } else {
                    buffer[idx] = chars[idx]
                }
            }
            results.append(String(buffer))
        }
        return results
    }

    private static func generateBoundedCandidates(
        chars: [Character],
        mutableIndices: [Int],
        gpaPredictions: [GPACharPrediction],
        limit: Int
    ) -> [String] {
        let predByIndex = Dictionary(uniqueKeysWithValues: gpaPredictions.map { ($0.index, $0) })

        var gpaChars = chars
        for idx in mutableIndices {
            if let pred = predByIndex[idx], pred.wantsDiacritic, let tr = oneWayMap[chars[idx]] {
                gpaChars[idx] = tr
            }
        }

        var seen: Set<String> = [String(chars)]
        var ordered: [String] = []

        func appendIfNew(_ candidateChars: [Character]) {
            guard ordered.count < limit else { return }
            let s = String(candidateChars)
            if seen.insert(s).inserted {
                ordered.append(s)
            }
        }

        appendIfNew(gpaChars)

        // Sort mutable positions by weakest GPA priority first (largest abs(rank)) so uncertain characters flip first.
        let orderedPositions = mutableIndices.sorted { lhs, rhs in
            let r1 = abs(predByIndex[lhs]?.rank ?? 0)
            let r2 = abs(predByIndex[rhs]?.rank ?? 0)
            return r1 > r2
        }

        func toggled(_ base: [Character], at index: Int) -> [Character] {
            var copy = base
            if copy[index] == chars[index] {
                if let tr = oneWayMap[chars[index]] {
                    copy[index] = tr
                }
            } else {
                copy[index] = chars[index]
            }
            return copy
        }

        // 1-flip neighbors of GPA prediction
        for idx in orderedPositions {
            if ordered.count >= limit { break }
            appendIfNew(toggled(gpaChars, at: idx))
        }

        // 2-flip neighbors of GPA prediction
        for i in 0..<orderedPositions.count {
            if ordered.count >= limit { break }
            let first = toggled(gpaChars, at: orderedPositions[i])
            for j in (i + 1)..<orderedPositions.count {
                if ordered.count >= limit { break }
                appendIfNew(toggled(first, at: orderedPositions[j]))
            }
        }

        // Vowel-harmony templates (front vs back vowels) seeded from existing Turkish vowels
        let hasExistingFront = chars.contains { frontVowels.contains($0) }
        let hasExistingBack = chars.contains { backVowels.contains($0) }

        if !hasExistingBack {
            appendIfNew(applyHarmony(base: gpaChars, orig: chars, mutableIndices: mutableIndices, front: true))
        }
        if !hasExistingFront {
            appendIfNew(applyHarmony(base: gpaChars, orig: chars, mutableIndices: mutableIndices, front: false))
        }

        let frontBase = applyHarmony(base: gpaChars, orig: chars, mutableIndices: mutableIndices, front: true)
        let backBase = applyHarmony(base: gpaChars, orig: chars, mutableIndices: mutableIndices, front: false)
        for idx in orderedPositions {
            if ordered.count >= limit { break }
            appendIfNew(toggled(frontBase, at: idx))
            appendIfNew(toggled(backBase, at: idx))
        }

        return ordered
    }

    private static func applyHarmony(
        base: [Character],
        orig: [Character],
        mutableIndices: [Int],
        front: Bool
    ) -> [Character] {
        var result = base
        for idx in mutableIndices {
            switch orig[idx] {
            case "i":
                result[idx] = front ? "i" : "ı"
            case "I":
                result[idx] = front ? "İ" : "I"
            case "o":
                result[idx] = front ? "ö" : "o"
            case "O":
                result[idx] = front ? "Ö" : "O"
            case "u":
                result[idx] = front ? "ü" : "u"
            case "U":
                result[idx] = front ? "Ü" : "U"
            default:
                break
            }
        }
        return result
    }

    private static func isTitleCase(_ word: String) -> Bool {
        guard let first = word.first, first.isUppercase else {
            return false
        }
        let tail = word.dropFirst()
        return !tail.isEmpty && tail.allSatisfy { !$0.isUppercase }
    }
}
