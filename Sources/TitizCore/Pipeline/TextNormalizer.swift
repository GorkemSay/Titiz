import Foundation

/// UTF-16 offset range corresponding to `NSRange` without requiring AppKit/Foundation bridge types in callers.
public struct UTF16Range: Sendable, Equatable, Hashable, Codable {
    public let location: Int
    public let length: Int

    public var upperBound: Int { location + length }
    public var isEmpty: Bool { length == 0 }

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }
}

/// UTF-8 NFC normalized text paired with an exact mapping back to original UTF-16 and `String.Index` offsets.
public struct NormalizedText: Sendable, Equatable {
    public let original: String
    public let text: String
    public let wasAlreadyNFC: Bool

    /// Maps each UTF-16 code-unit boundary `0...text.utf16.count` to its corresponding UTF-16 boundary in `original`.
    /// Empty when `wasAlreadyNFC` is `true` (identity mapping).
    private let normalizedUTF16BoundaryToOriginalUTF16: [Int]

    fileprivate init(
        original: String,
        text: String,
        wasAlreadyNFC: Bool,
        boundaryMap: [Int]
    ) {
        self.original = original
        self.text = text
        self.wasAlreadyNFC = wasAlreadyNFC
        self.normalizedUTF16BoundaryToOriginalUTF16 = boundaryMap
    }

    /// Computes the UTF-16 range inside the NFC-normalized `text` for a `Range<String.Index>` in `text`.
    public func normalizedUTF16Range(for range: Range<String.Index>) -> UTF16Range {
        let start = text.utf16.distance(from: text.utf16.startIndex, to: range.lowerBound)
        let length = text[range].utf16.count
        return UTF16Range(location: start, length: length)
    }

    /// Maps a UTF-16 range in `text` back to the exact UTF-16 range in `original`.
    public func originalUTF16Range(for normalizedUTF16Range: UTF16Range) -> UTF16Range {
        if wasAlreadyNFC {
            return normalizedUTF16Range
        }

        let maxIndex = max(0, normalizedUTF16BoundaryToOriginalUTF16.count - 1)
        let clampedStart = min(max(0, normalizedUTF16Range.location), maxIndex)
        let clampedEnd = min(max(clampedStart, normalizedUTF16Range.upperBound), maxIndex)

        let origStart = normalizedUTF16BoundaryToOriginalUTF16[clampedStart]
        let origEnd = normalizedUTF16BoundaryToOriginalUTF16[clampedEnd]
        return UTF16Range(location: origStart, length: max(0, origEnd - origStart))
    }

    /// Maps a `Range<String.Index>` in `text` back to the corresponding `Range<String.Index>` in `original`.
    public func originalRange(for normalizedRange: Range<String.Index>) -> Range<String.Index> {
        let normUTF16 = normalizedUTF16Range(for: normalizedRange)
        let origUTF16 = originalUTF16Range(for: normUTF16)
        let start = original.utf16.index(original.utf16.startIndex, offsetBy: origUTF16.location)
        let end = original.utf16.index(start, offsetBy: origUTF16.length)
        return start..<end
    }
}

/// Normalizes input strings to UTF-8 NFC while preserving exact source offset mapping.
public enum TextNormalizer {
    /// Normalizes `input` to UTF-8 NFC and builds an exact UTF-16 offset map when transformations occur.
    public static func normalize(_ input: String) -> NormalizedText {
        let nfcWhole = input.precomposedStringWithCanonicalMapping

        // Compare UTF-8 bytes directly rather than `==` because Swift `==` treats NFD and NFC as canonically equal.
        if input.utf8.elementsEqual(nfcWhole.utf8) {
            return NormalizedText(
                original: input,
                text: input,
                wasAlreadyNFC: true,
                boundaryMap: []
            )
        }

        var rebuilt = String()
        rebuilt.reserveCapacity(nfcWhole.utf8.count)

        var boundaryMap: [Int] = [0]
        boundaryMap.reserveCapacity(nfcWhole.utf16.count + 1)

        var originalUTF16Cursor = 0
        for cluster in input {
            let origCluster = String(cluster)
            let normCluster = origCluster.precomposedStringWithCanonicalMapping
            let origClusterUTF16Count = origCluster.utf16.count
            let normClusterUTF16Count = normCluster.utf16.count

            rebuilt.append(normCluster)

            if normClusterUTF16Count > 0 {
                for _ in 0..<(normClusterUTF16Count - 1) {
                    boundaryMap.append(originalUTF16Cursor)
                }
                originalUTF16Cursor += origClusterUTF16Count
                boundaryMap.append(originalUTF16Cursor)
            } else {
                originalUTF16Cursor += origClusterUTF16Count
            }
        }

        if rebuilt.utf8.elementsEqual(nfcWhole.utf8), boundaryMap.count == rebuilt.utf16.count + 1 {
            return NormalizedText(
                original: input,
                text: rebuilt,
                wasAlreadyNFC: false,
                boundaryMap: boundaryMap
            )
        }

        // Defensive fallback for pathological cross-cluster canonical compositions.
        let normUTF16Total = nfcWhole.utf16.count
        let origUTF16Total = input.utf16.count
        var fallbackMap = Array(repeating: 0, count: normUTF16Total + 1)
        fallbackMap[normUTF16Total] = origUTF16Total

        return NormalizedText(
            original: input,
            text: nfcWhole,
            wasAlreadyNFC: false,
            boundaryMap: fallbackMap
        )
    }
}
