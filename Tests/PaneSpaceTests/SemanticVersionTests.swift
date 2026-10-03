import XCTest
@testable import PaneSpaceApp

final class SemanticVersionTests: XCTestCase {
    func testParsesStableTaggedAndPrereleaseVersions() throws {
        let stable = try XCTUnwrap(SemanticVersion(string: "0.2.0"))
        XCTAssertEqual(stable.major, 0)
        XCTAssertEqual(stable.minor, 2)
        XCTAssertEqual(stable.patch, 0)
        XCTAssertFalse(stable.isPrerelease)

        let tagged = try XCTUnwrap(SemanticVersion(string: "v0.2.0"))
        XCTAssertEqual(tagged, stable, "A v prefix is a tag convention, not a different version.")

        let prerelease = try XCTUnwrap(SemanticVersion(string: "0.2.0-beta.1"))
        XCTAssertEqual(prerelease.prereleaseIdentifiers, ["beta", "1"])
        XCTAssertTrue(prerelease.isPrerelease)
    }

    func testParsesBuildMetadataWithoutUsingItForPrecedence() throws {
        let withBuild = try XCTUnwrap(SemanticVersion(string: "1.2.3+build.45"))
        let withoutBuild = try XCTUnwrap(SemanticVersion(string: "1.2.3"))
        XCTAssertEqual(withBuild.buildMetadataIdentifiers, ["build", "45"])
        XCTAssertEqual(withBuild, withoutBuild, "Build metadata is excluded from precedence.")
        XCTAssertFalse(withBuild > withoutBuild)
        XCTAssertFalse(withBuild < withoutBuild)
    }

    func testRejectsMalformedInput() {
        for input in [
            "",
            "1",
            "1.2",
            "1.2.3.4",
            "v",
            "nightly",
            "1.2.x",
            "01.2.3",
            "1.2.3-",
            "1.2.3+",
            "1.2.3-beta..1",
            "1.2.3-beta_1",
            "-1.2.3",
        ] {
            XCTAssertNil(SemanticVersion(string: input), input)
        }
    }

    /// A release tag is copied by hand often enough that surrounding whitespace is not a reason to
    /// reject the whole update; the trim is deliberate, and `testTrimsSurroundingWhitespace` covers it.
    func testTrimsSurroundingWhitespace() throws {
        XCTAssertEqual(SemanticVersion(string: " 1.0.0 "), try XCTUnwrap(SemanticVersion(string: "1.0.0")))
    }

    func testComparesCoreVersionsNumerically() throws {
        let ordered = ["0.0.1", "0.1.0", "0.2.0", "0.10.0", "1.0.0", "2.0.0", "10.0.0"]
        let versions = try ordered.map { try XCTUnwrap(SemanticVersion(string: $0)) }
        for (lower, higher) in zip(versions, versions.dropFirst()) {
            XCTAssertLessThan(lower, higher, "\(lower) < \(higher)")
            XCTAssertGreaterThan(higher, lower)
        }
    }

    func testStableOutranksPrereleaseOfTheSameCoreVersion() throws {
        let stable = try XCTUnwrap(SemanticVersion(string: "1.0.0"))
        let prerelease = try XCTUnwrap(SemanticVersion(string: "1.0.0-rc.1"))
        XCTAssertLessThan(prerelease, stable)
    }

    func testPrereleaseIdentifiersFollowSemVerPrecedence() throws {
        // SemVer 2.0 §11.4: identifiers compare field by field, numeric ones numerically, and
        // numeric identifiers rank below alphanumeric ones.
        let ordered = [
            "1.0.0-alpha",
            "1.0.0-alpha.1",
            "1.0.0-alpha.beta",
            "1.0.0-beta",
            "1.0.0-beta.2",
            "1.0.0-beta.11",
            "1.0.0-rc.1",
            "1.0.0",
        ]
        let versions = try ordered.map { try XCTUnwrap(SemanticVersion(string: $0)) }
        for (lower, higher) in zip(versions, versions.dropFirst()) {
            XCTAssertLessThan(lower, higher, "\(lower) < \(higher)")
        }
    }

    func testFewerPrereleaseIdentifiersRankLower() throws {
        let shorter = try XCTUnwrap(SemanticVersion(string: "1.0.0-alpha"))
        let longer = try XCTUnwrap(SemanticVersion(string: "1.0.0-alpha.1"))
        XCTAssertLessThan(shorter, longer)
    }

    func testDescriptionRoundTrips() throws {
        for input in ["1.0.0", "v1.0.0", "1.0.0-beta.1", "1.0.0+build.5", "1.0.0-beta.1+build.5"] {
            let version = try XCTUnwrap(SemanticVersion(string: input), input)
            XCTAssertEqual(SemanticVersion(string: version.description), version, input)
        }
    }
}