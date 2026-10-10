import Foundation
import Sparkle

/// How a skipped version is recorded, in the same keys Sparkle reads it from.
///
/// When PaneSpace takes over presentation through gentle reminders, Sparkle's update window is
/// never built, so its "Skip" button — the only thing that normally writes these keys — is never
/// shown. A banner that offers "skip this version" therefore has to write the record itself, or the
/// next check finds the same version again and the button silently does nothing.
///
/// The keys and the choice between them follow `SPUSkippedUpdate.skipUpdate(_:host:)`: a normal
/// update records `versionString` in `SUSkippedVersion`, while a major upgrade records its minimum
/// autoupdate version in `SUSkippedMajorVersion` together with the update's own version in
/// `SUSkippedMajorSubreleaseVersion`. Writing only the minor key for a major upgrade would leave
/// every later patch of that major line on offer, which is the opposite of what the user asked for.
///
/// Sparkle stores these in the host bundle's own `UserDefaults` domain with no prefix, so the same
/// `UserDefaults` instance PaneSpace already holds addresses the same records.
enum SparkleSkippedUpdate {
    static let minorVersionKey = "SUSkippedVersion"
    static let majorVersionKey = "SUSkippedMajorVersion"
    static let majorSubreleaseVersionKey = "SUSkippedMajorSubreleaseVersion"

    /// Records a skip for an offer, and returns the key it wrote so the UI can show it.
    ///
    /// The value is `versionString` — the update's `CFBundleVersion` — not the display string, because
    /// that is what Sparkle compares against on the next check.
    @discardableResult
    static func recordSkip(
        of offer: SparkleUpdateOffer,
        isMajorUpgrade: Bool = false,
        minimumAutoupdateVersion: String? = nil,
        in defaults: UserDefaults
    ) -> String {
        if isMajorUpgrade, let minimumAutoupdateVersion {
            defaults.set(minimumAutoupdateVersion, forKey: majorVersionKey)
            defaults.set(offer.versionString, forKey: majorSubreleaseVersionKey)
            // A major skip supersedes any minor one, so a later check cannot resurrect an update the
            // user skipped on the strength of skipping this one.
            defaults.removeObject(forKey: minorVersionKey)
            return majorVersionKey
        }
        defaults.set(offer.versionString, forKey: minorVersionKey)
        return minorVersionKey
    }

    /// The version Sparkle would currently skip, for display in Settings.
    static func currentSkippedVersion(in defaults: UserDefaults) -> String? {
        defaults.string(forKey: minorVersionKey)
            ?? defaults.string(forKey: majorSubreleaseVersionKey)
    }
}
