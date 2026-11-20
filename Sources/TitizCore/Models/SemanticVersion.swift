import Foundation

/// Parsed Semantic Versioning (`major.minor.patch[-prerelease]`) value used by `AppUpdater`
/// to compare local app versions against GitHub Releases tags (with or without leading `v`).
public struct SemanticVersion: Comparable, Sendable, Equatable, Hashable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?

    public init(major: Int, minor: Int, patch: Int, prerelease: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    public init?(parsing raw: String) {
        var working = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !working.isEmpty else { return nil }

        if working.first == "v" || working.first == "V" {
            working.removeFirst()
        }

        if let plusIndex = working.firstIndex(of: "+") {
            working = String(working[..<plusIndex])
        }

        let corePart: String
        let prePart: String?
        if let dashIndex = working.firstIndex(of: "-") {
            corePart = String(working[..<dashIndex])
            let suffix = String(working[working.index(after: dashIndex)...])
            guard !suffix.isEmpty else { return nil }
            prePart = suffix
        } else {
            corePart = working
            prePart = nil
        }

        let segments = corePart.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 2 || segments.count == 3 else {
            return nil
        }
        guard segments.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else {
            return nil
        }

        guard let parsedMajor = Int(segments[0]),
              let parsedMinor = Int(segments[1]),
              let parsedPatch = segments.count == 3 ? Int(segments[2]) : 0,
              parsedMajor >= 0,
              parsedMinor >= 0,
              parsedPatch >= 0 else {
            return nil
        }

        self.major = parsedMajor
        self.minor = parsedMinor
        self.patch = parsedPatch
        self.prerelease = prePart
    }

    public var description: String {
        if let prerelease {
            return "\(major).\(minor).\(patch)-\(prerelease)"
        }
        return "\(major).\(minor).\(patch)"
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil):
            return false
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case let (.some(lPre), .some(rPre)):
            return lPre < rPre
        }
    }
}
