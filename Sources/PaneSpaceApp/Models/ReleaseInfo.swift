import Foundation

/// A published GitHub release that the running application can be compared against.
struct ReleaseInfo: Hashable, Sendable, Identifiable {
    /// The release tag, for example `v0.2.0` or `0.2.0-beta.1`.
    let tag: String
    /// The version parsed from `tag`, or nil when the tag is not a version at all.
    let version: SemanticVersion?
    /// Where the user can read about and download the release.
    let releasePageURL: URL
    let isPrerelease: Bool
    let publishedAt: Date?

    var id: String { tag }

    /// The version to show in UI. Falls back to the raw tag so an unparseable tag is still visible
    /// rather than silently dropped.
    var displayVersion: String { version?.description ?? tag }

    /// Whether this release can be an update for `current`, which requires a parseable version that
    /// is strictly newer. A release that is not a version is never offered.
    func isUpdate(over current: SemanticVersion) -> Bool {
        guard let version else { return false }
        return version > current
    }
}
