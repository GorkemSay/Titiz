import Testing
@testable import TitizCore

@Suite("SemanticVersion Parsing & Ordering")
struct SemanticVersionTests {
    @Test("Parses standard, v-prefixed, two-segment, and prerelease semver strings")
    func parsesValidFormats() {
        #expect(SemanticVersion(parsing: "v0.1.0") == SemanticVersion(major: 0, minor: 1, patch: 0))
        #expect(SemanticVersion(parsing: "V1.2.3") == SemanticVersion(major: 1, minor: 2, patch: 3))
        #expect(SemanticVersion(parsing: "0.2") == SemanticVersion(major: 0, minor: 2, patch: 0))
        #expect(SemanticVersion(parsing: "0.1.0-dev") == SemanticVersion(major: 0, minor: 1, patch: 0, prerelease: "dev"))
        #expect(SemanticVersion(parsing: "  v1.10.2+build42 ") == SemanticVersion(major: 1, minor: 10, patch: 2))

        #expect(SemanticVersion(parsing: "") == nil)
        #expect(SemanticVersion(parsing: "v1") == nil)
        #expect(SemanticVersion(parsing: "1.2.3.4") == nil)
        #expect(SemanticVersion(parsing: "v0.1.0-") == nil)
        #expect(SemanticVersion(parsing: "v0.a.1") == nil)
    }

    @Test("Orders versions correctly across prerelease, minor, multi-digit, and major boundaries")
    func comparesVersionsAccurately() throws {
        let chain = try [
            "0.1.0-alpha",
            "0.1.0-dev",
            "0.1.0",
            "0.1.1",
            "v0.2.0",
            "v0.10.0",
            "v1.0.0"
        ].map { try #require(SemanticVersion(parsing: $0)) }

        for idx in 0..<(chain.count - 1) {
            #expect(chain[idx] < chain[idx + 1])
            #expect(!(chain[idx + 1] < chain[idx]))
        }
        #expect(SemanticVersion(parsing: "v0.2.0") == SemanticVersion(parsing: "0.2"))
    }
}
