import Foundation
import Sparkle

/// The object Sparkle calls back, and the only place its two protocols are implemented.
///
/// Sparkle holds its delegates weakly, so this object is owned by the application delegate for as
/// long as the updater exists. It forwards to `UpdateModel` rather than holding state: the model's
/// published properties are what the banner observes, and a second copy here would be a second
/// answer to the same question.
///
/// It conforms to both `SPUUpdaterDelegate` and `SPUStandardUserDriverDelegate` on purpose. Gentle
/// reminders are the mechanism that moves update presentation into PaneSpace's own banner, and that
/// needs the user-driver half; the channel filter and the check callbacks need the updater half.
///
/// `@preconcurrency` on the conformance is required, not cosmetic.
/// `SPUStandardUserDriverDelegate` is declared without main-actor isolation even though Sparkle
/// documents that every one of its methods is called from the main thread, so Swift 6 rejects a
/// conformance from a `@MainActor` type as crossing into isolated code. The isolation is real — the
/// object is only ever touched from the main thread, and each method that cannot express it hops
/// explicitly — so annotating the conformance is the honest way to say so.
@MainActor
final class SparkleUpdateDelegate: NSObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    /// Set by `attach(to:)` right after the controller is created.
    ///
    /// Optional because the controller's initialiser takes the delegates as `id?` while Swift will
    /// not let a stored property be read before every other one is initialised. Nothing can call
    /// into this object before `attach(to:)` runs, so the value is always set by then.
    private var model: UpdateModel?

    func attach(to model: UpdateModel) {
        self.model = model
    }

    // MARK: - Channels

    /// The channels this build may look for updates in.
    ///
    /// Read on every check rather than cached, because the user can change the toggle at any time
    /// and Sparkle asks the question each time. The default channel is always allowed by Sparkle, so
    /// the empty set is exactly "stable only".
    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        MainActor.assumeIsolated {
            UpdatePreferences.allowedChannels(
                includingPrereleases: model?.includesPrereleases ?? false
            )
        }
    }

    // MARK: - Check outcomes

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        MainActor.assumeIsolated {
            model?.noteSparkleFoundUpdate()
        }
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: (any Error)) {
        MainActor.assumeIsolated {
            // A check that aborted must not leave a banner offering a version the last check never
            // confirmed. The cycle callback that follows publishes the failure to the user.
            model?.dropStaleSparkleOffer()
        }
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        MainActor.assumeIsolated {
            model?.finishSparkleCycle(updateCheck: updateCheck, error: error)
        }
    }

    // MARK: - User choices

    func updater(
        _ updater: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate updateItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        MainActor.assumeIsolated {
            // A skip made inside Sparkle's own window still has to reach the published state, or the
            // banner would keep offering what the user just dismissed. `SUSkippedVersion` is
            // already written by Sparkle at this point; this only mirrors it for the UI.
            guard choice == .skip else { return }
            // `displayVersionString`, not `versionString`: what the model publishes is rendered in
            // Settings and compared against the banner's display version. Sparkle has already
            // written the build number into `SUSkippedVersion` itself; this only mirrors it for
            // the UI, and the UI wants the version the user recognises.
            model?.mirrorSkippedVersion(updateItem.displayVersionString)
        }
    }

    // MARK: - Gentle reminders

    /// Declares that PaneSpace presents scheduled updates itself.
    ///
    /// Returning `true` is what tells Sparkle to ask
    /// `standardUserDriverShouldHandleShowingScheduledUpdate` instead of putting up its own window.
    /// Without it the standard driver owns presentation and the banner is never shown.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Hands scheduled updates to PaneSpace's banner.
    ///
    /// Returning `false` moves responsibility for showing the update to this delegate. The method is
    /// required to have no side effects, and user-initiated checks never reach it: a check the user
    /// asked for is Sparkle's to present, so "Check for Updates…" still behaves as a user expects.
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        MainActor.assumeIsolated {
            // `handleShowingUpdate` is true when Sparkle presents the update itself, which is the
            // user-initiated case the banner must not take over. Only the delegate-owned path feeds
            // the banner.
            guard !handleShowingUpdate else { return }
            model?.presentSparkleOffer(SparkleUpdateOffer(appcastItem: update))
        }
    }

    func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated {
            model?.endSparkleUpdateSession()
        }
    }
}
