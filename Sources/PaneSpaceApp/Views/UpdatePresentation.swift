import AppKit
import Foundation

/// What the update banner's primary button does, decided by which source found the update.
///
/// The two sources can only be told apart here. A Sparkle offer is installed by Sparkle, and the
/// fallback path's release is not installable by PaneSpace at all — its whole design is "tell the
/// user where the release is" — so the button the user presses and the words on it are different
/// things, not one thing worded twice.
enum UpdateInstallAction: Equatable, Sendable {
    /// Hand the update to Sparkle, which downloads and installs it in its own window.
    case checkForUpdates
    /// Open the release page in the user's browser.
    case openReleasePage
}

/// Everything the update banner renders, resolved from the update itself.
///
/// This is the whole of the banner's decision-making, kept out of the view so it can be tested
/// without a window. It is deliberately a value: the same update must always produce the same
/// banner, whichever source produced it, and a test can only check that if the rule lives here
/// rather than inside a `View` body.
struct UpdateBannerPresentation: Equatable, Sendable {
    /// The sentence the user reads, which already carries the version.
    let headline: String
    /// "Beta" for an offer from a pre-release channel, nil otherwise.
    let channelBadge: String?
    /// The words on the primary button.
    let primaryActionTitle: String
    /// What the primary button does.
    let primaryAction: UpdateInstallAction
    /// What VoiceOver reads for the banner as a whole.
    let accessibilityLabel: String

    /// The banner for an update, whichever source found it.
    ///
    /// The pre-release flag is carried through from the source rather than derived from a
    /// comparison with the running build: with beta updates off, Sparkle only offers the default
    /// channel, so anything flagged here arrived because the user opted in.
    static func banner(for update: AvailableUpdate) -> UpdateBannerPresentation {
        let headline = L10n.format("PaneSpace %@ is available.", update.displayVersion)
        let badge = update.isPrerelease ? L10n.text("Beta") : nil
        let isSparkleUpdate: Bool
        if case .sparkle = update {
            isSparkleUpdate = true
        } else {
            isSparkleUpdate = false
        }
        return UpdateBannerPresentation(
            headline: headline,
            channelBadge: badge,
            // "Update…" rather than "Install": pressing it does not install, it opens the window
            // where the download and the installation happen.
            primaryActionTitle: L10n.text(isSparkleUpdate ? "Update…" : "View Release Page"),
            primaryAction: isSparkleUpdate ? .checkForUpdates : .openReleasePage,
            // The badge is part of what the banner says, so it is part of what VoiceOver reads.
            accessibilityLabel: badge.map { "\(headline) \($0)" } ?? headline
        )
    }
}

/// The alert a manual check produces on the path where PaneSpace owns the answer.
///
/// A user-initiated action is allowed to interrupt, and the fallback path has nobody else to
/// report the result: the check returned a value and no window was put up. On the Sparkle path
/// Sparkle's own standard user driver reports the outcome, and an alert here would say the same
/// thing twice — so nothing asks for feedback on that path.
struct UpdateCheckFeedback: Equatable, Sendable, Identifiable {
    let title: String
    let message: String

    var id: String { "\(title)\u{1F}\(message)" }

    /// The feedback for a check the user asked for, or nil when nothing should interrupt them.
    ///
    /// The `usesSparkle` branch is the important one. When Sparkle owns the check, its standard
    /// user driver puts up its own window for every outcome — up to date, an update was found, the
    /// check failed — so an alert here would say the same thing a second time, in a different
    /// window. `checkNow()` returns `.upToDate` on that path before the cycle has even finished,
    /// which is not an answer at all: treating it as one is how "up to date" gets reported for a
    /// check that in fact found an update. The real outcome arrives later in `lastManualResult`.
    static func feedback(for result: UpdateCheckResult, usesSparkle: Bool) -> UpdateCheckFeedback? {
        guard !usesSparkle else { return nil }
        switch result {
        case .upToDate:
            return UpdateCheckFeedback(
                title: L10n.text("Check for Updates"),
                message: L10n.text("PaneSpace is up to date.")
            )
        case .available(let release):
            return UpdateCheckFeedback(
                title: L10n.text("Check for Updates"),
                message: L10n.format("PaneSpace %@ is available.", release.displayVersion)
            )
        case .failed(let error):
            // A cancelled check describes a state the user is no longer in — a newer check replaced
            // it, or automatic checking was switched off — so there is nothing to report. Every
            // other failure carries its own localized, user-actionable description.
            guard error != .cancelled else { return nil }
            return UpdateCheckFeedback(
                title: L10n.text("Check for Updates"),
                message: error.errorDescription ?? L10n.text("The update service could not be reached.")
            )
        }
    }
}

/// How long ago the last check ran, in words.
///
/// `RelativeDateTimeFormatter` is used rather than a hand-written "3 hours ago", because the
/// wording of a relative time is the translator's to write, not the code's — and because a
/// sentence is assembled around it, not from it.
enum UpdateCheckTiming {
    static func relativeText(for date: Date, now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

/// Runs a check the user asked for, on behalf of the menu command and the Settings button.
///
/// Both entry points go through here so they cannot disagree about whether feedback is shown —
/// which is the whole point of the rule above.
enum UpdateCheckAction {
    /// Checks now and returns the feedback to show, if the caller should show any.
    ///
    /// The Settings page presents the result in a SwiftUI alert; the menu command uses
    /// `runAndAlert(_:)` below, because a menu bar command has no view to attach one to.
    @MainActor
    static func run(_ updates: UpdateModel) async -> UpdateCheckFeedback? {
        let usesSparkle = updates.usesSparkle
        let result = await updates.checkNow()
        return UpdateCheckFeedback.feedback(for: result, usesSparkle: usesSparkle)
    }

    /// Checks now and shows the result in an `NSAlert`, or shows nothing at all.
    ///
    /// Modal, which is acceptable here and only here: the user asked for this, so interrupting them
    /// is what they asked for. On the Sparkle path `run` returns nil and this is a no-op, because
    /// Sparkle's own window has already reported the outcome.
    @MainActor
    static func runAndAlert(_ updates: UpdateModel) async {
        guard let feedback = await run(updates) else { return }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = feedback.title
        alert.informativeText = feedback.message
        alert.addButton(withTitle: L10n.text("OK"))
        // `beginSheetModalFor` would need a window to hang off, and the menu command can be invoked
        // with no window open. The app-modal form is what matches that.
        alert.runModal()
    }
}
