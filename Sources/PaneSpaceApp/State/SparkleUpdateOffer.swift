import Foundation
import Sparkle

/// The updater's own record of what it offers, translated into PaneSpace's vocabulary.
///
/// Sparkle is the only source of update information once it is linked: it fetches the appcast,
/// compares versions, applies the channel filter, and decides what is worth offering. The banner
/// needs a version string and a release-notes link, so those are read once here rather than being
/// re-derived from a second feed.
///
/// Reading the appcast item on the main actor keeps this a plain value copy: `SUAppcastItem` is not
/// `Sendable`, and passing one across actors would be the one place this layer could leak a Sparkle
/// object into SwiftUI state.
struct SparkleUpdateOffer: Equatable, Sendable {
    /// The version to show in UI, e.g. `0.3.0` or `0.3.0-beta.1`.
    let displayVersion: String
    /// The value Sparkle compares and records skips against: the update's `CFBundleVersion`.
    ///
    /// This is deliberately not the display string. Sparkle's skipped-version keys hold
    /// `versionString`, so a skip that PaneSpace records has to be the same string or Sparkle will
    /// not recognise it on the next check and will offer the very version the user just skipped.
    let versionString: String
    /// Where the user can read about the release. nil when the appcast item carries no link.
    let releaseNotesURL: URL?
    /// Whether the appcast item sits on a channel other than the default one.
    let isFromPrereleaseChannel: Bool

    /// Whether this offer is a pre-release the user may not have asked for.
    ///
    /// This is what the banner needs to decide whether to label the update, not a comparison
    /// against the running build: with beta updates off Sparkle only offers the default channel,
    /// so anything flagged here arrived because the user opted in.
    var isPrerelease: Bool { isFromPrereleaseChannel }

    init(
        displayVersion: String,
        versionString: String,
        releaseNotesURL: URL?,
        isFromPrereleaseChannel: Bool
    ) {
        self.displayVersion = displayVersion
        self.versionString = versionString
        self.releaseNotesURL = releaseNotesURL
        self.isFromPrereleaseChannel = isFromPrereleaseChannel
    }

    /// Builds the offer from a Sparkle appcast item, or nil when the item is information-only.
    ///
    /// An information-only item has nothing to download; handing it to the banner as if it were an
    /// update would offer an "Install" that cannot start.
    @MainActor
    init?(appcastItem: SUAppcastItem) {
        guard !appcastItem.isInformationOnlyUpdate else { return nil }
        let displayVersion = appcastItem.displayVersionString
        let versionString = appcastItem.versionString
        guard !displayVersion.isEmpty, !versionString.isEmpty else { return nil }
        self.init(
            displayVersion: displayVersion,
            versionString: versionString,
            releaseNotesURL: appcastItem.releaseNotesURL,
            isFromPrereleaseChannel: appcastItem.channel != nil
        )
    }
}
