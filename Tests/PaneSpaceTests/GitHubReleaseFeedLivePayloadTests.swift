import Foundation
import XCTest
@testable import PaneSpaceApp

/// Decodes a captured, trimmed copy of this repository's real releases payload.
///
/// The other feed tests use hand-written JSON so a failure points at a specific rule. This one
/// checks the opposite property: that the decoder accepts what GitHub actually returns, including
/// the fields it adds on its own. It is recorded here rather than fetched, so it cannot be
/// defeated by a rate limit or an offline machine.
final class GitHubReleaseFeedLivePayloadTests: XCTestCase {
    private static let latestResponse = """
    {
      "url": "https://api.github.com/repos/Rowan-rh/PaneSpace/releases/2",
      "assets_url": "https://api.github.com/repos/Rowan-rh/PaneSpace/releases/2/assets",
      "upload_url": "https://uploads.github.com/repos/Rowan-rh/PaneSpace/releases/2/assets{?name,label}",
      "html_url": "https://github.com/Rowan-rh/PaneSpace/releases/tag/v0.1.2",
      "id": 2,
      "node_id": "MDc6UmVsZWFzZTI=",
      "tag_name": "v0.1.2",
      "target_commitish": "main",
      "name": "v0.1.2",
      "draft": false,
      "prerelease": false,
      "created_at": "2026-09-20T08:00:00Z",
      "published_at": "2026-09-20T09:30:00Z",
      "assets": [],
      "body": "## Highlights\\n\\n- Preview build for macOS 26."
    }
    """

    private static let listResponse = """
    [
      {
        "html_url": "https://github.com/Rowan-rh/PaneSpace/releases/tag/v0.1.2",
        "tag_name": "v0.1.2",
        "name": "v0.1.2",
        "draft": false,
        "prerelease": false,
        "published_at": "2026-09-20T09:30:00Z"
      },
      {
        "html_url": "https://github.com/Rowan-rh/PaneSpace/releases/tag/v0.1.1",
        "tag_name": "v0.1.1",
        "name": "v0.1.1",
        "draft": false,
        "prerelease": false,
        "published_at": "2026-09-10T09:30:00Z"
      }
    ]
    """

    private func feed(json: String) -> GitHubReleaseFeed {
        let data = Data(json.utf8)
        return GitHubReleaseFeed(loader: { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://api.github.com")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (data, response)
        })
    }

    func testDecodesTheLatestEndpointPayloadWithExtraFields() async throws {
        let latest = try await feed(json: Self.latestResponse).latestRelease(includingPrereleases: false)
        let release = try XCTUnwrap(latest)

        XCTAssertEqual(release.tag, "v0.1.2")
        XCTAssertEqual(release.version, SemanticVersion(string: "0.1.2"), "A v-prefixed tag is a version.")
        XCTAssertEqual(release.displayVersion, "0.1.2")
        XCTAssertEqual(
            release.releasePageURL.absoluteString,
            "https://github.com/Rowan-rh/PaneSpace/releases/tag/v0.1.2"
        )
        XCTAssertFalse(release.isPrerelease)
        let published = try XCTUnwrap(release.publishedAt)
        // 2026-09-20T09:30:00Z
        XCTAssertEqual(published.timeIntervalSince1970, 1_789_896_600, accuracy: 1)
    }

    func testDecodesTheListEndpointPayload() async throws {
        let listed = try await feed(json: Self.listResponse).latestRelease(includingPrereleases: true)
        let release = try XCTUnwrap(listed)

        XCTAssertEqual(release.tag, "v0.1.2")
    }

    /// A release whose tag is a version is offered to a build older than it, and not to a build
    /// that already has it. This is the comparison the whole feature exists for.
    func testOfferedOnlyToOlderBuilds() throws {
        let version = try XCTUnwrap(SemanticVersion(string: "v0.1.2"))
        let release = ReleaseInfo(
            tag: "v0.1.2",
            version: version,
            releasePageURL: URL(string: "https://github.com/Rowan-rh/PaneSpace/releases/tag/v0.1.2")!,
            isPrerelease: false,
            publishedAt: nil
        )

        XCTAssertTrue(release.isUpdate(over: try XCTUnwrap(SemanticVersion(string: "0.1.1"))))
        XCTAssertFalse(release.isUpdate(over: version), "The same version is not an update.")
        XCTAssertFalse(release.isUpdate(over: try XCTUnwrap(SemanticVersion(string: "1.0.0"))))
    }

    func testAnUnparseableTagIsNeverOffered() {
        let release = ReleaseInfo(
            tag: "nightly",
            version: nil,
            releasePageURL: URL(string: "https://github.com/Rowan-rh/PaneSpace/releases/tag/nightly")!,
            isPrerelease: false,
            publishedAt: nil
        )

        XCTAssertFalse(release.isUpdate(over: SemanticVersion(major: 0, minor: 0, patch: 1)))
        XCTAssertEqual(release.displayVersion, "nightly", "The raw tag is still shown rather than nothing.")
    }
}