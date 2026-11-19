import Foundation

/// Compact Turkish unigram and quantized bigram frequency table backed by `tr_freq.bin`.
///
/// Binary layout (`"TZFQ"`, v1, little-endian):
/// - 16-byte header: magic (`4B`), version (`UInt16`), reserved (`UInt16`), `unigramCount` (`UInt32`), `bigramCount` (`UInt32`)
/// - Sorted unigram records (`unigramCount * 9B`): `UInt64` FNV-1a UTF-8 hash + `UInt8` quantized `log10 P(w)`
/// - Sorted bigram records (`bigramCount * 9B`): `UInt64` FNV-1a UTF-8 hash of `"w1\tw2"` + `UInt8` quantized `log10 P(w2 | w1)`
public struct TurkishFrequencyTable: Sendable {
    private static let magic: [UInt8] = [0x54, 0x5A, 0x46, 0x51] // "TZFQ"
    private static let headerSize = 16
    private static let recordSize = 9

    private static let unigramMinLog10 = -8.0
    private static let unigramMaxLog10 = -1.0
    private static let unseenUnigramLog10 = -8.2
    private static let bigramMinLog10 = -6.0
    private static let bigramMaxLog10 = 0.0

    private let data: Data
    public let unigramEntryCount: Int
    public let bigramEntryCount: Int
    private let bigramBaseOffset: Int

    /// Loads `tr_freq.bin` from `TitizCore` module resources.
    public static func loadBundled() throws -> TurkishFrequencyTable {
        guard let url = Bundle.module.url(forResource: "tr_freq", withExtension: "bin") else {
            throw CharacterEngineResourceError.missingResource(name: "tr_freq", extension: "bin")
        }
        let data = try Data(contentsOf: url)
        return try TurkishFrequencyTable(data: data)
    }

    public init(data: Data) throws {
        guard data.count >= Self.headerSize else {
            throw CharacterEngineResourceError.invalidResourceFormat(
                name: "tr_freq.bin",
                reason: "File smaller than 16-byte header."
            )
        }

        let headerBytes = Array(data.prefix(Self.headerSize))
        guard Array(headerBytes[0..<4]) == Self.magic else {
            throw CharacterEngineResourceError.invalidResourceFormat(
                name: "tr_freq.bin",
                reason: "Unexpected magic bytes."
            )
        }

        let version = Self.readUInt16LE(headerBytes, at: 4)
        guard version == 1 else {
            throw CharacterEngineResourceError.invalidResourceFormat(
                name: "tr_freq.bin",
                reason: "Unsupported format version \(version)."
            )
        }

        let uniCount = Int(Self.readUInt32LE(headerBytes, at: 8))
        let biCount = Int(Self.readUInt32LE(headerBytes, at: 12))
        let expectedBytes = Self.headerSize + (uniCount + biCount) * Self.recordSize

        guard data.count >= expectedBytes else {
            throw CharacterEngineResourceError.invalidResourceFormat(
                name: "tr_freq.bin",
                reason: "Truncated payload: expected \(expectedBytes) bytes, got \(data.count)."
            )
        }

        self.data = data
        self.unigramEntryCount = uniCount
        self.bigramEntryCount = biCount
        self.bigramBaseOffset = Self.headerSize + uniCount * Self.recordSize
    }

    /// Returns dequantized `log10 P(word)` using Turkish locale lowercasing, or `-8.2` if unseen.
    public func unigramLog10(_ word: String) -> Double {
        let key = Self.fnv1a64(TurkishLocale.lowercased(word))
        guard let q = binarySearch(hash: key, baseOffset: Self.headerSize, count: unigramEntryCount) else {
            return Self.unseenUnigramLog10
        }
        return Self.dequantize(q, minValue: Self.unigramMinLog10, maxValue: Self.unigramMaxLog10)
    }

    /// Returns dequantized `log10 P(current | previous)` when `(previous, current)` is in the table, or `nil`.
    public func bigramConditionalLog10(previous: String, current: String) -> Double? {
        let joined = "\(TurkishLocale.lowercased(previous))\t\(TurkishLocale.lowercased(current))"
        let key = Self.fnv1a64(joined)
        guard let q = binarySearch(hash: key, baseOffset: bigramBaseOffset, count: bigramEntryCount) else {
            return nil
        }
        return Self.dequantize(q, minValue: Self.bigramMinLog10, maxValue: Self.bigramMaxLog10)
    }

    /// Computes a clamped pointwise mutual information boost `log10(P(current | previous) / P(current))`.
    public func pmiBoost(previous: String, current: String) -> Double {
        guard let conditional = bigramConditionalLog10(previous: previous, current: current) else {
            return 0.0
        }
        let rawPMI = conditional - unigramLog10(current)
        return min(max(rawPMI, -1.5), 3.5)
    }

    // MARK: - Private Binary Lookup & Hashing

    private func binarySearch(hash: UInt64, baseOffset: Int, count: Int) -> UInt8? {
        guard count > 0 else { return nil }

        return data.withUnsafeBytes { rawBuffer in
            var low = 0
            var high = count - 1
            while low <= high {
                let mid = low + ((high - low) >> 1)
                let offset = baseOffset + mid * Self.recordSize
                let midHash = UInt64(littleEndian: rawBuffer.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
                if midHash == hash {
                    return rawBuffer[offset + 8]
                } else if midHash < hash {
                    low = mid + 1
                } else {
                    high = mid - 1
                }
            }
            return nil
        }
    }

    private static func fnv1a64(_ text: String) -> UInt64 {
        var hash: UInt64 = 14695981039346656037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return hash
    }

    private static func dequantize(_ q: UInt8, minValue: Double, maxValue: Double) -> Double {
        minValue + (Double(q) / 255.0) * (maxValue - minValue)
    }

    private static func readUInt16LE(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readUInt32LE(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}
