import Foundation
import XCTest
@testable import PaneSpaceApp

/// What the update banner and the manual-check feedback decide, and the one rule that keeps a
/// check's outcome from being reported twice.
///
/// These are pure functions over the two update sources, so they are tested directly — a test that
/// needed a window, a running updater or a real appcast would be testing SwiftUI, Sparkle or the
/// network, none of which is what changed here.
@MainActor
final class UpdatePresentationTests: XCTestCase {
    private func makeRelease(
        _ tag: String,
        prerelease: Bool = false
    ) -> ReleaseInfo {
        ReleaseInfo(
            tag: tag,
            version: SemanticVersion(string: tag),
            releasePageURL: URL(string: "https://github.com/Rowan-rh/PaneSpace/releases/tag/\(tag)")!,
            isPrerelease: prerelease,
            publishedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func makeOffer(
        version: String = "0.3.0",
        versionString: String = "30099",
        prereleaseChannel: Bool = false
    ) -> AvailableUpdate {
        .sparkle(
            SparkleUpdateOffer(
                displayVersion: version,
                versionString: versionString,
                releaseNotesURL: URL(string: "https://example.invalid/notes"),
                isFromPrereleaseChannel: prereleaseChannel
            )
        )
    }

    // MARK: - Banner

    func testABannerNamesTheVersionItIsOffering() {
        let banner = UpdateBannerPresentation.banner(for: makeOffer(version: "0.4.1"))
        XCTAssertEqual(banner.headline, "PaneSpace 0.4.1 is available.")
    }

    func testASparkleUpdateIsInstalledBySparkleAndSaysSo() {
        let banner = UpdateBannerPresentation.banner(for: makeOffer())
        // The button opens Sparkle's own window, where the download and installation happen. Calling
        // it "Install" would promise something the button does not do.
        XCTAssertEqual(banner.primaryActionTitle, "Update…")
        XCTAssertEqual(banner.primaryAction, .checkForUpdates)
    }

    func testAFallbackReleaseSendsTheUserToTheReleasePageInstead() {
        // PaneSpace cannot install a GitHub release; the release page is the only honest
        // destination for it, so the button must not claim to be installing anything.
        let banner = UpdateBannerPresentation.banner(for: .release(makeRelease("0.4.1")))
        XCTAssertEqual(banner.primaryActionTitle, "View Release Page")
        XCTAssertEqual(banner.primaryAction, .openReleasePage)
    }

    func testTheSameVersionRendersIdenticallyWhicheverSourceFoundIt() {
        // The banner is written once; if the two sources could differ, every piece of wording would
        // have to be written twice and they would drift.
        let sparkle = UpdateBannerPresentation.banner(for: makeOffer(version: "0.4.1"))
        let release = UpdateBannerPresentation.banner(for: .release(makeRelease("0.4.1")))
        XCTAssertEqual(sparkle.headline, release.headline)
        XCTAssertEqual(sparkle.channelBadge, release.channelBadge)
        XCTAssertEqual(sparkle.accessibilityLabel, release.accessibilityLabel)
        // Only the action differs, because only that can: one path installs, the other cannot.
        XCTAssertNotEqual(sparkle.primaryAction, release.primaryAction)
    }

    func testAPrereleaseIsLabelledBetaAndStableIsNot() {
        XCTAssertEqual(
            UpdateBannerPresentation.banner(for: makeOffer(prereleaseChannel: true)).channelBadge,
            "Beta"
        )
        XCTAssertEqual(
            UpdateBannerPresentation.banner(for: .release(makeRelease("0.4.0-beta.1", prerelease: true)))
                .channelBadge,
            "Beta"
        )
        XCTAssertNil(UpdateBannerPresentation.banner(for: makeOffer()).channelBadge)
        XCTAssertNil(
            UpdateBannerPresentation.banner(for: .release(makeRelease("0.4.0"))).channelBadge
        )
    }

    func testTheBetaLabelIsPartOfWhatVoiceOverReads() {
        // A badge that only exists visually is a badge a VoiceOver user never hears.
        let banner = UpdateBannerPresentation.banner(for: makeOffer(prereleaseChannel: true))
        XCTAssertEqual(banner.accessibilityLabel, "PaneSpace 0.3.0 is available. Beta")

        let stable = UpdateBannerPresentation.banner(for: makeOffer())
        XCTAssertEqual(stable.accessibilityLabel, stable.headline)
    }

    // MARK: - Manual check feedback

    func testTheFallbackPathReportsEveryOutcome() {
        // Nobody else reports a result on this path: the check returned a value and no window was
        // put up, so the user would otherwise never learn what happened.
        XCTAssertEqual(
            UpdateCheckFeedback.feedback(for: .upToDate, usesSparkle: false)?.message,
            "PaneSpace is up to date."
        )
        XCTAssertEqual(
            UpdateCheckFeedback.feedback(
                for: .available(makeRelease("0.4.1")),
                usesSparkle: false
            )?.message,
            "PaneSpace 0.4.1 is available."
        )
        XCTAssertEqual(
            UpdateCheckFeedback.feedback(for: .failed(.unreachable), usesSparkle: false)?.message,
            "The update service could not be reached."
        )
    }

    func testSparkleReportsItselfSoPaneSpaceStaysSilent() {
        // Sparkle's standard user driver puts up its own window for every outcome. An alert here
        // would say the same thing twice, in two windows — and `checkNow()` on this path returns
        // `.upToDate` before the cycle has even finished, so it cannot be used as the answer.
        for result: UpdateCheckResult in [
            .upToDate,
            .available(makeRelease("0.4.1")),
            .failed(.unreachable),
            .failed(.invalidResponse),
            .failed(.cancelled)
        ] {
            XCTAssertNil(
                UpdateCheckFeedback.feedback(for: result, usesSparkle: true),
                "Sparkle already reports \(result) in its own window."
            )
        }
    }

    func testACancelledCheckIsNotReported() {
        // A cancelled check was replaced by a newer one or switched off, so its outcome describes a
        // state the user is not in. Reporting it would name a problem that no longer exists.
        XCTAssertNil(
            UpdateCheckFeedback.feedback(for: .failed(.cancelled), usesSparkle: false)
        )
    }

    func testARateLimitedFailureKeepsItsOwnWording() {
        // "Try again later" is a different instruction from "could not be reached", and collapsing
        // them would send the user to the wrong next step.
        XCTAssertEqual(
            UpdateCheckFeedback.feedback(for: .failed(.httpStatus(429)), usesSparkle: false)?.message,
            "The update service is rate limiting requests. Try again later."
        )
    }

    // MARK: - Last check timing

    func testARelativeTimeIsWordedNotNumbered() {
        // The exact instant is not something a user acts on in a settings row; how long ago it was
        // is. The formatting is `RelativeDateTimeFormatter`'s so a translator owns the wording.
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let twoHoursAgo = UpdateCheckTiming.relativeText(
            for: now.addingTimeInterval(-7_200),
            now: now
        )
        XCTAssertFalse(twoHoursAgo.isEmpty)
        XCTAssertTrue(
            twoHoursAgo.contains("2") || twoHoursAgo.lowercased().contains("hour"),
            "Expected a worded relative time, got \(twoHoursAgo)"
        )
    }

    func testAMomentAndALongGapAreWordedDifferently() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertNotEqual(
            UpdateCheckTiming.relativeText(for: now, now: now),
            UpdateCheckTiming.relativeText(for: now.addingTimeInterval(-86_400 * 3), now: now)
        )
    }
}
