import Foundation

/// The version this build reports to the update service.
///
/// The value normally comes from `CFBundleShortVersionString`. A binary launched outside an app
/// bundle — `swift run`, a test runner — has no such key, and comparing against a missing version
/// would either offer every release or none.
enum AppVersion {
    /// Overrides the bundle version so an unreleased build can exercise the update banner against
    /// the real feed. Read once at launch; changing it later has no effect.
    static let overrideEnvironmentKey = "PANESPACE_UPDATE_FAKE_VERSION"

    /// The current version, or nil when the build is not packaged and nothing is set.
    static var current: SemanticVersion? {
        currentVersionString.flatMap(SemanticVersion.init(string:))
    }

    /// The raw version string, before parsing.
    static var currentVersionString: String? {
        if let override = ProcessInfo.processInfo.environment[overrideEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return override
        }
        let bundled = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let trimmed = bundled?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
