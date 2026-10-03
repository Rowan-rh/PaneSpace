import Foundation
import XCTest
@testable import PaneSpaceApp

/// Feeds a `GitHubReleaseFeed` fixed JSON and records what it was asked for, so the endpoint
/// choice, the request headers, and the error mapping are all observable without a network.
private final class RecordedRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [URLRequest] = []

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func record(_ request: URLRequest) {
        lock.lock()
        stored.append(request)
        lock.unlock()
    }
}

final class GitHubReleaseFeedTests: XCTestCase {
    private func releaseJSON(
        tag: String,
        prerelease: Bool = false,
        draft: Bool = false,
        publishedAt: String? = "2026-10-01T10:00:00Z"
    ) -> String {
        """
        {
          "tag_name": "\(tag)",
          "name": "\(tag)",
          "html_url": "https://github.com/Rowan-rh/PaneSpace/releases/tag/\(tag)",
          "draft": \(draft),
          "prerelease": \(prerelease),
          "published_at": \(publishedAt.map { "\"\($0)\"" } ?? "null")
        }
        """
    }

    private func makeFeed(
        json: String,
        statusCode: Int = 200,
        recorded: RecordedRequest? = nil
    ) -> GitHubReleaseFeed {
        let data = Data(json.utf8)
        return GitHubReleaseFeed(loader: { request in
            recorded?.record(request)
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://api.github.com")!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (data, response)
        })
    }

    private static func httpResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.github.com/repos/Rowan-rh/PaneSpace/releases")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
    }

    // MARK: Request shape

    func testRequestsTheLatestEndpointWhenPrereleasesAreExcluded() async throws {
        let recorded = RecordedRequest()
        let feed = makeFeed(json: releaseJSON(tag: "0.2.0"), recorded: recorded)

        _ = try await feed.latestRelease(includingPrereleases: false)

        let request = try XCTUnwrap(recorded.requests.first)
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://api.github.com/repos/Rowan-rh/PaneSpace/releases/latest"
        )
        XCTAssertEqual(request.httpMethod, "GET")
    }

    func testRequestsTheListEndpointWithPageSizeWhenPrereleasesAreIncluded() async throws {
        let recorded = RecordedRequest()
        let feed = makeFeed(json: "[\(releaseJSON(tag: "0.3.0-beta.1", prerelease: true))]", recorded: recorded)

        _ = try await feed.latestRelease(includingPrereleases: true)

        let request = try XCTUnwrap(recorded.requests.first)
        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/repos/Rowan-rh/PaneSpace/releases")
        let expectedQuery = [URLQueryItem(name: "per_page", value: "20")]
        XCTAssertEqual(components.queryItems, expectedQuery)
    }

    func testSendsGitHubRequiredHeadersAndNoToken() async throws {
        let recorded = RecordedRequest()
        let feed = makeFeed(json: releaseJSON(tag: "0.2.0"), recorded: recorded)

        _ = try await feed.latestRelease(includingPrereleases: false)

        let request = try XCTUnwrap(recorded.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-GitHub-Api-Version"), GitHubReleaseFeed.apiVersion)
        XCTAssertNotNil(request.value(forHTTPHeaderField: "User-Agent"))
        // The feed is unauthenticated, so no credential may be attached to the request.
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    // MARK: Release selection

    func testReturnsTheLatestReleaseWithoutPrereleases() async throws {
        let feed = makeFeed(json: releaseJSON(tag: "v0.2.0"))

        let releaseValue = try await feed.latestRelease(includingPrereleases: false)
        let release = try XCTUnwrap(releaseValue)

        XCTAssertEqual(release.tag, "v0.2.0")
        let expected = try XCTUnwrap(SemanticVersion(string: "0.2.0"))
        XCTAssertEqual(release.version, expected)
        XCTAssertEqual(
            release.releasePageURL.absoluteString,
            "https://github.com/Rowan-rh/PaneSpace/releases/tag/v0.2.0"
        )
        XCTAssertFalse(release.isPrerelease)
        XCTAssertNotNil(release.publishedAt)
    }

    func testPicksTheHighestVersionNotTheNewestPublicationWhenPrereleasesAreAllowed() async throws {
        // A beta published today can belong to an older version line than a stable published
        // earlier, so the list order must not decide the answer.
        let json = """
        [
          \(releaseJSON(tag: "0.3.0-beta.1", prerelease: true, publishedAt: "2026-10-03T10:00:00Z")),
          \(releaseJSON(tag: "0.2.0", publishedAt: "2026-09-01T10:00:00Z")),
          \(releaseJSON(tag: "0.2.1-rc.1", prerelease: true, publishedAt: "2026-09-20T10:00:00Z"))
        ]
        """
        let feed = makeFeed(json: json)

        let releaseValue = try await feed.latestRelease(includingPrereleases: true)
        let release = try XCTUnwrap(releaseValue)

        XCTAssertEqual(release.tag, "0.3.0-beta.1")
    }

    func testPrefersAStableReleaseOverAPrereleaseOfTheSameCoreVersion() async throws {
        let json = """
        [
          \(releaseJSON(tag: "0.4.0-rc.2", prerelease: true)),
          \(releaseJSON(tag: "0.4.0"))
        ]
        """
        let feed = makeFeed(json: json)

        let releaseValue = try await feed.latestRelease(includingPrereleases: true)
        let release = try XCTUnwrap(releaseValue)

        XCTAssertEqual(release.tag, "0.4.0")
        XCTAssertFalse(release.isPrerelease)
    }

    func testIgnoresDrafts() async throws {
        let json = """
        [
          \(releaseJSON(tag: "9.9.9", draft: true, publishedAt: "2026-10-03T10:00:00Z")),
          \(releaseJSON(tag: "0.2.0", publishedAt: "2026-09-01T10:00:00Z"))
        ]
        """
        let feed = makeFeed(json: json)

        let releaseValue = try await feed.latestRelease(includingPrereleases: true)
        let release = try XCTUnwrap(releaseValue)

        XCTAssertEqual(release.tag, "0.2.0", "A draft is not installable and must never be offered.")
    }

    func testIgnoresReleasesWithoutAParseableVersion() async throws {
        let json = """
        [
          \(releaseJSON(tag: "nightly-build")),
          \(releaseJSON(tag: "0.2.0"))
        ]
        """
        let feed = makeFeed(json: json)

        let releaseValue = try await feed.latestRelease(includingPrereleases: true)
        let release = try XCTUnwrap(releaseValue)

        XCTAssertEqual(release.tag, "0.2.0", "An unrankable tag cannot be compared with anything.")
    }

    func testReturnsNilWhenNothingIsPublished() async throws {
        let feed = makeFeed(json: "[]")

        let release = try await feed.latestRelease(includingPrereleases: true)

        XCTAssertNil(release)
    }

    // MARK: Failures

    func testMapsNonSuccessStatusCodes() async {
        // 404 is excluded on purpose: the stable-release endpoint answers 404 when the repository has
        // published none, which is an empty feed rather than a failure, and
        // `testTreatsA404FromTheLatestEndpointAsAnEmptyFeed` covers that case.
        for status in [403, 429, 500, 503] {
            let feed = GitHubReleaseFeed(loader: { request in
                (Data(), Self.httpResponse(statusCode: status))
            })
            do {
                _ = try await feed.latestRelease(includingPrereleases: false)
                XCTFail("Expected a failure for HTTP \(status).")
            } catch let error as UpdateFeedError {
                XCTAssertEqual(error, .httpStatus(status), "HTTP \(status)")
            } catch {
                XCTFail("Unexpected error for HTTP \(status): \(error)")
            }
        }
    }

    /// GitHub answers 404 on `/releases/latest` when no stable release exists. Reporting that as
    /// "could not be reached" would send the user to a connection error for a repository that simply
    /// has not shipped yet, and the list endpoint already reports the same situation as `[]`.
    func testTreatsA404FromTheLatestEndpointAsAnEmptyFeed() async throws {
        let feed = GitHubReleaseFeed(loader: { _ in
            (Data(), Self.httpResponse(statusCode: 404))
        })

        let release = try await feed.latestRelease(includingPrereleases: false)

        XCTAssertNil(release, "No stable release yet is an empty feed, not a failure.")
    }

    /// Only the stable-release endpoint gets that reading. On the list endpoint a 404 is the request
    /// itself failing — a moved or renamed repository looks exactly like this — so it stays an error
    /// rather than being quietly reported as "no releases".
    func testStillReportsA404FromTheListEndpointAsAFailure() async {
        let feed = GitHubReleaseFeed(loader: { _ in
            (Data(), Self.httpResponse(statusCode: 404))
        })

        do {
            _ = try await feed.latestRelease(includingPrereleases: true)
            XCTFail("Expected a failure.")
        } catch let error as UpdateFeedError {
            XCTAssertEqual(error, .httpStatus(404))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRateLimitStatusCodesAreDistinguishableFromOtherFailures() async throws {
        let limited = GitHubReleaseFeed(loader: { _ in (Data(), Self.httpResponse(statusCode: 429)) })
        let serverError = GitHubReleaseFeed(loader: { _ in (Data(), Self.httpResponse(statusCode: 500)) })

        do {
            _ = try await limited.latestRelease(includingPrereleases: false)
            XCTFail("Expected a failure.")
        } catch let error as UpdateFeedError {
            XCTAssertTrue(error.isRateLimited)
        }

        do {
            _ = try await serverError.latestRelease(includingPrereleases: false)
            XCTFail("Expected a failure.")
        } catch let error as UpdateFeedError {
            XCTAssertFalse(error.isRateLimited)
        }
    }

    func testMapsUndecodableBodies() async {
        let feed = makeFeed(json: "{ not json")
        do {
            _ = try await feed.latestRelease(includingPrereleases: false)
            XCTFail("Expected a decoding failure.")
        } catch let error as UpdateFeedError {
            XCTAssertEqual(error, .invalidResponse)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRejectsAReleaseWithoutAReleasePage() async {
        let feed = makeFeed(json: """
        { "tag_name": "0.2.0", "draft": false, "prerelease": false }
        """)
        do {
            _ = try await feed.latestRelease(includingPrereleases: false)
            XCTFail("Expected a decoding failure.")
        } catch let error as UpdateFeedError {
            XCTAssertEqual(error, .invalidResponse)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMapsTransportFailuresWithoutLeakingTheUnderlyingDescription() async {
        let feed = GitHubReleaseFeed(loader: { _ in
            throw URLError(.cannotConnectToHost)
        })
        do {
            _ = try await feed.latestRelease(includingPrereleases: false)
            XCTFail("Expected a transport failure.")
        } catch let error as UpdateFeedError {
            XCTAssertEqual(error, .unreachable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMapsCancellation() async {
        let feed = GitHubReleaseFeed(loader: { _ in
            throw URLError(.cancelled)
        })
        do {
            _ = try await feed.latestRelease(includingPrereleases: false)
            XCTFail("Expected a cancellation.")
        } catch let error as UpdateFeedError {
            XCTAssertEqual(error, .cancelled)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}