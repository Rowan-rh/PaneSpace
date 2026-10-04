import Foundation
import XCTest
@testable import PaneSpaceApp

/// The two rules that decide how PaneSpace's own preferences meet Sparkle's: which channels a build
/// may look in, and the one-time carry-over of the automatic-checks switch.
///
/// Both are pure functions over `UserDefaults` rather than anything that needs a live updater, so
/// they are tested directly — a test that needed Sparkle to start would be testing Sparkle.
final class UpdatePreferencesTests: XCTestCase {
    @MainActor
    private func makeDefaults() -> UserDefaults {
        let suiteName = "UpdatePreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        // The teardown block runs off the main actor, and `UserDefaults` is not `Sendable`, so the
        // suite name is captured instead of the instance itself.
        let name = suiteName
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: name) }
        return defaults
    }

    // MARK: - Channels

    @MainActor
    func testBetaUpdatesOffMeansTheDefaultChannelOnly() {
        // An empty set is what "stable only" means to Sparkle. Returning `["default"]` would be the
        // same behaviour, but would read as a different branch than it is.
        XCTAssertEqual(UpdatePreferences.allowedChannels(includingPrereleases: false), [])
    }

    @MainActor
    func testBetaUpdatesOnAddsTheBetaChannel() {
        XCTAssertEqual(
            UpdatePreferences.allowedChannels(includingPrereleases: true),
            [UpdatePreferences.betaChannel]
        )
    }

    @MainActor
    func testTheDefaultChannelIsNeverNamedExplicitly() {
        // Sparkle always includes the default channel, so naming it would suggest it can be turned
        // off, which it cannot.
        for includingPrereleases in [true, false] {
            let channels = UpdatePreferences.allowedChannels(includingPrereleases: includingPrereleases)
            XCTAssertFalse(channels.contains("default"), "\(channels)")
        }
    }

    // MARK: - Migration

    @MainActor
    func testMigrationCarriesTheStage2ChoiceIntoSparklesKey() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: UpdatePreferences.supersededAutomaticChecksKey)

        UpdatePreferences.migrateAutomaticChecks(in: defaults)

        XCTAssertFalse(
            defaults.bool(forKey: UpdatePreferences.automaticChecksKey),
            "A user who turned checks off must not get them back after upgrading."
        )
        XCTAssertNil(
            defaults.object(forKey: UpdatePreferences.supersededAutomaticChecksKey),
            "The old key is removed, so nothing can write it again."
        )
    }

    @MainActor
    func testMigrationAlsoCarriesATurnedOnChoice() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: UpdatePreferences.supersededAutomaticChecksKey)

        UpdatePreferences.migrateAutomaticChecks(in: defaults)

        XCTAssertTrue(defaults.bool(forKey: UpdatePreferences.automaticChecksKey))
    }

    @MainActor
    func testMigrationPrefersSparklesKeyWhenBothExist() {
        let defaults = makeDefaults()
        // The state is ambiguous, and Sparkle's key is the one that has been authoritative since the
        // user last saw the app, so it wins.
        defaults.set(false, forKey: UpdatePreferences.automaticChecksKey)
        defaults.set(true, forKey: UpdatePreferences.supersededAutomaticChecksKey)

        UpdatePreferences.migrateAutomaticChecks(in: defaults)

        XCTAssertFalse(defaults.bool(forKey: UpdatePreferences.automaticChecksKey))
        XCTAssertNil(defaults.object(forKey: UpdatePreferences.supersededAutomaticChecksKey))
    }

    @MainActor
    func testMigrationRunsOnlyOnce() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: UpdatePreferences.supersededAutomaticChecksKey)
        UpdatePreferences.migrateAutomaticChecks(in: defaults)

        // The user changes their mind in Sparkle's own UI, which writes only the Sparkle key.
        defaults.set(true, forKey: UpdatePreferences.automaticChecksKey)
        // A stale copy of the old key reappears — for instance restored from a backup.
        defaults.set(false, forKey: UpdatePreferences.supersededAutomaticChecksKey)

        UpdatePreferences.migrateAutomaticChecks(in: defaults)

        XCTAssertTrue(
            defaults.bool(forKey: UpdatePreferences.automaticChecksKey),
            "A second migration would overwrite a newer choice with an older one."
        )
    }

    @MainActor
    func testMigrationOnAFreshInstallStillRecordsThatItRan() {
        let defaults = makeDefaults()

        UpdatePreferences.migrateAutomaticChecks(in: defaults)

        XCTAssertNil(
            defaults.object(forKey: UpdatePreferences.automaticChecksKey),
            "Nothing is written when there is nothing to carry over."
        )
        XCTAssertTrue(
            defaults.bool(forKey: UpdatePreferences.migrationFlagKey),
            "Otherwise every launch would re-run the migration forever."
        )
    }

    // MARK: - Reset policy

    @MainActor
    func testResetClearsEveryUserVisibleSparkleKey() {
        let defaults = makeDefaults()
        for key in UpdatePreferences.resettableKeys {
            defaults.set("value", forKey: key)
        }
        // The internal keys that must survive the reset.
        defaults.set(1_700_000_000, forKey: "SULastCheckTime")
        defaults.set(true, forKey: "SUHasLaunchedBefore")
        defaults.set("group-id", forKey: "SUUpdateGroupIdentifier")

        PaneSpacePreferences.reset(in: defaults)

        for key in UpdatePreferences.resettableKeys {
            XCTAssertNil(defaults.object(forKey: key), key)
        }
        XCTAssertNotNil(defaults.object(forKey: "SULastCheckTime"))
        XCTAssertNotNil(defaults.object(forKey: "SUHasLaunchedBefore"))
        XCTAssertEqual(defaults.string(forKey: "SUUpdateGroupIdentifier"), "group-id")
    }

    @MainActor
    func testResetClearsTheMigrationFlagToo() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: UpdatePreferences.migrationFlagKey)
        defaults.set(false, forKey: UpdatePreferences.supersededAutomaticChecksKey)

        PaneSpacePreferences.reset(in: defaults)

        XCTAssertNil(
            defaults.object(forKey: UpdatePreferences.migrationFlagKey),
            "A reset user who had a stage-2 choice would otherwise never get it carried across."
        )
    }

    @MainActor
    func testTheTwoKeySetsDoNotOverlap() {
        // A key in both lists would be cleared by accident and preserved by accident in two places;
        // the split is only meaningful while it is a partition.
        let cleared = Set(UpdatePreferences.resettableKeys)
        let preserved = Set(UpdatePreferences.preservedKeys)
        XCTAssertTrue(cleared.isDisjoint(with: preserved), "\(cleared.intersection(preserved))")
    }

    @MainActor
    func testEveryPreservedKeyIsAnInternalSparkleKey() {
        // Named so that a future Sparkle key added to the wrong list is a deliberate act.
        XCTAssertEqual(
            Set(UpdatePreferences.preservedKeys),
            ["SULastCheckTime", "SUHasLaunchedBefore", "SUUpdateGroupIdentifier"]
        )
    }

    // MARK: - Skipped version recording

    @MainActor
    func testRecordingASkipWritesTheValueSparkleCompares() {
        let defaults = makeDefaults()
        let offer = SparkleUpdateOffer(
            displayVersion: "0.3.0",
            versionString: "30099",
            releaseNotesURL: nil,
            isFromPrereleaseChannel: false
        )

        SparkleSkippedUpdate.recordSkip(of: offer, in: defaults)

        XCTAssertEqual(defaults.string(forKey: "SUSkippedVersion"), "30099")
        XCTAssertEqual(SparkleSkippedUpdate.currentSkippedVersion(in: defaults), "30099")
    }

    @MainActor
    func testRecordingAMajorSkipUsesTheMajorKeys() {
        let defaults = makeDefaults()
        let offer = SparkleUpdateOffer(
            displayVersion: "2.0.0",
            versionString: "20000",
            releaseNotesURL: nil,
            isFromPrereleaseChannel: false
        )

        SparkleSkippedUpdate.recordSkip(
            of: offer,
            isMajorUpgrade: true,
            minimumAutoupdateVersion: "20000",
            in: defaults
        )

        XCTAssertEqual(defaults.string(forKey: "SUSkippedMajorVersion"), "20000")
        XCTAssertEqual(defaults.string(forKey: "SUSkippedMajorSubreleaseVersion"), "20000")
        XCTAssertNil(
            defaults.object(forKey: "SUSkippedVersion"),
            "A minor skip left behind would be checked against and could resurface the update."
        )
    }
}
