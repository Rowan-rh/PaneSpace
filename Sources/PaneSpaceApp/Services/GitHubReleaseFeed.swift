import Foundation

/// A source of published releases.
///
/// The protocol exists so the update check can be tested without a network, and so a future feed —
/// a different host, a bundled channel file — replaces only the implementation.
protocol UpdateFeed: Sendable {
    /// The newest release the user should be offered, or nil when the feed has nothing to report.
    /// Implementations return nil for a genuinely empty answer and throw when the question could
    /// not be answered.
    func latestRelease(includingPrereleases: Bool) async throws -> ReleaseInfo?
}

/// A `URLSession`-shaped seam for the feed, so tests can answer without a server.
///
/// Kept as a closure rather than a protocol: there is one implementation, and a test only needs to
/// substitute a different response for the same request.
typealias UpdateFeedLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

enum UpdateFeedError: LocalizedError, Equatable, Sendable {
    /// A non-2xx response. The status code is kept because 403 and 429 mean the request was rate
    /// limited and the user should be told to wait, which differs from a server failure.
    case httpStatus(Int)
    /// The body was not the JSON the endpoint documents.
    case invalidResponse
    /// The check was replaced by a newer one or switched off before it finished.
    case cancelled
    /// The request never produced a response. The underlying reason is deliberately coarse: it can
    /// name hosts and paths, and this project's logs must not.
    case unreachable

    var errorDescription: String? {
        switch self {
        case .httpStatus(403), .httpStatus(429):
            return L10n.text("The update service is rate limiting requests. Try again later.")
        case .httpStatus, .unreachable:
            return L10n.text("The update service could not be reached.")
        case .invalidResponse:
            return L10n.text("The update service returned an unexpected response.")
        case .cancelled:
            return L10n.text("The update check was cancelled.")
        }
    }

    /// Whether the user is being told to wait rather than that something is wrong.
    var isRateLimited: Bool {
        if case .httpStatus(let code) = self { return code == 403 || code == 429 }
        return false
    }
}

/// Reads releases from this project's GitHub repository.
///
/// The unauthenticated GitHub API is used on purpose: an update check must not require a token, and
/// must not store one. Rate limiting is therefore the reason failures are normalized into a few
/// cases instead of retried.
struct GitHubReleaseFeed: UpdateFeed {
    static let owner = "Rowan-rh"
    static let repository = "PaneSpace"
    /// GitHub's documentation requires this version header on API requests.
    static let apiVersion = "2022-11-28"
    /// How many releases to inspect when pre-releases are allowed.
    static let prereleasePageSize = 20

    private static let apiBase = URL(string: "https://api.github.com/repos/\(owner)/\(repository)")!

    private let loader: UpdateFeedLoader?
    private let session: URLSession
    private let userAgent: String

    init(
        loader: UpdateFeedLoader? = nil,
        session: URLSession = .shared,
        userAgent: String = "PaneSpace/\(AppVersion.currentVersionString ?? "dev")"
    ) {
        self.loader = loader
        self.session = session
        self.userAgent = userAgent
    }

    /// The release the user should be offered.
    ///
    /// With pre-releases off, `/releases/latest` already excludes drafts and pre-releases and
    /// answers with one release. With them on, the list endpoint is used and the highest version
    /// wins, because that list is ordered by publication date: a pre-release published today can
    /// belong to an older version line than a stable release published last month. Releases without
    /// a parseable version are ignored, since there is no way to rank them.
    func latestRelease(includingPrereleases: Bool) async throws -> ReleaseInfo? {
        let releases = try await fetch(includingPrereleases: includingPrereleases)
        // Drafts are never installable, and `/releases/latest` already drops them; filtering in both
        // paths keeps that guarantee from depending on the endpoint.
        let published = releases.filter { !$0.isDraft }
        // Without pre-releases the endpoint returned a single stable release, and GitHub already
        // ranked it. With them on, versions have to be compared because publication order is not
        // version order. A release whose tag is not a version cannot be ranked, so it is dropped.
        let best = includingPrereleases
            ? published.filter { $0.version != nil }.max { left, right in
                guard let leftVersion = left.version, let rightVersion = right.version else { return false }
                return leftVersion < rightVersion
            }
            : published.first
        guard let best else { return nil }
        return ReleaseInfo(
            tag: best.tag,
            version: best.version,
            releasePageURL: best.releasePageURL,
            isPrerelease: best.isPrerelease,
            publishedAt: best.publishedAt
        )
    }

    private func fetch(includingPrereleases: Bool) async throws -> [GitHubRelease] {
        if includingPrereleases {
            var components = URLComponents(
                url: Self.apiBase.appendingPathComponent("releases"),
                resolvingAgainstBaseURL: false
            )
            components?.queryItems = [URLQueryItem(name: "per_page", value: String(Self.prereleasePageSize))]
            guard let url = components?.url else { throw UpdateFeedError.invalidResponse }
            let data = try await send(URLRequest(url: url))
            do {
                return try JSONDecoder().decode([GitHubRelease].self, from: data)
            } catch {
                throw UpdateFeedError.invalidResponse
            }
        }

        let data = try await send(URLRequest(url: Self.apiBase.appendingPathComponent("releases/latest")))
        do {
            return [try JSONDecoder().decode(GitHubRelease.self, from: data)]
        } catch {
            throw UpdateFeedError.invalidResponse
        }
    }

    /// Adds the headers GitHub asks for, sends the request, and turns every non-2xx or transport
    /// failure into a normalized error.
    private func send(_ request: URLRequest) async throws -> Data {
        var request = request
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await performRequest(request)
        } catch is CancellationError {
            throw UpdateFeedError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw UpdateFeedError.cancelled
        } catch let error as UpdateFeedError {
            throw error
        } catch {
            throw UpdateFeedError.unreachable
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UpdateFeedError.httpStatus(http.statusCode)
        }
        return data
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        if let loader {
            return try await loader(request)
        }
        return try await session.data(for: request)
    }
}

/// The subset of the GitHub releases payload this app reads.
private struct GitHubRelease: Decodable {
    let tag: String
    let releasePageURL: URL
    let isDraft: Bool
    let isPrerelease: Bool
    let publishedAt: Date?
    let version: SemanticVersion?

    private enum CodingKeys: String, CodingKey {
        case tag = "tag_name"
        case htmlURL = "html_url"
        case draft
        case prerelease
        case publishedAt = "published_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // A release without a tag or a release page is not something the UI could act on, so it is
        // rejected here rather than surfaced half-built.
        tag = try container.decode(String.self, forKey: .tag)
        let htmlURL = try container.decode(String.self, forKey: .htmlURL)
        guard let url = URL(string: htmlURL) else {
            throw DecodingError.dataCorruptedError(
                forKey: .htmlURL,
                in: container,
                debugDescription: "Release page URL is not a URL."
            )
        }
        releasePageURL = url
        isDraft = try container.decodeIfPresent(Bool.self, forKey: .draft) ?? false
        isPrerelease = try container.decodeIfPresent(Bool.self, forKey: .prerelease) ?? false
        publishedAt = try container.decodeIfPresent(String.self, forKey: .publishedAt).flatMap(Self.parseDate)
        version = SemanticVersion(string: tag)
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
