import Foundation

/// The `UserDefaults` keys the update path uses, and the one-time migration between the
/// stage-2 keys and the ones Sparkle owns.
///
/// Sparkle stores its own settings under `SU`-prefixed keys in the app's defaults domain, and
/// `UPanelSpace` no longer keeps a second copy. The rules here are ADR 0011 decision 3.
enum UpdatePreferences {
    // MARK: - PaneSpace's own keys

    /// Whether pre-releases are offered. Bound by the Settings window with `@AppStorage`, and
    /// mapped onto Sparkle's channel filter rather than onto a second stored copy of the answer.
    static let includesPrereleasesKey = "betaUpdates"

    // MARK: - Keys owned by Sparkle

    /// Sparkle's copy of the automatic-checks switch, and the only place it is stored.
    static let automaticChecksKey = "SUEnableAutomaticChecks"
    /// The stage-2 key that the switch used to live in.
    static let supersededAutomaticChecksKey = "automaticallyCheckForUpdates"
    /// Guards the migration so it cannot run twice and flip a user's newer choice back.
    static let migrationFlagKey = "hasMigratedUpdatePreferences"

    // MARK: - Reset policy

    /// The Sparkle keys `PaneSpacePreferences.reset` clears, because the user can see or change
    /// them: the two update switches, the check interval, the versions the user skipped, and the
    /// consent to send a system profile.
    static let resettableKeys = [
        "SUEnableAutomaticChecks",
        "SUAutomaticallyUpdate",
        "SUScheduledCheckInterval",
        "SUSkippedVersion",
        "SUSkippedMajorVersion",
        "SUSkippedMajorSubreleaseVersion",
        "SUSendProfileInfo"
    ]

    /// The Sparkle keys reset deliberately leaves alone.
    ///
    /// Clearing these would cause a behaviour the user never asked for: an immediate extra check
    /// (`SULastCheckTime`), a replayed first-launch flow (`SUHasLaunchedBefore`), or the loss of
    /// the random identifier that groups updates of the same build (`SUUpdateGroupIdentifier`).
    /// They are listed so the omission is a decision rather than an oversight.
    static let preservedKeys = [
        "SULastCheckTime",
        "SUHasLaunchedBefore",
        "SUUpdateGroupIdentifier"
    ]

    /// The channel PaneSpace's beta toggle adds to Sparkle's allowed set.
    static let betaChannel = "beta"

    // MARK: - Channel mapping

    /// The channels Sparkle may look for updates in.
    ///
    /// An empty set means the default channel only, and the default channel is always included by
    /// Sparkle regardless of what is returned here. So "beta updates off" is the empty set rather
    /// than `["default"]`: naming the default channel would be redundant and would make the two
    /// branches look different when they are the same choice.
    static func allowedChannels(includingPrereleases: Bool) -> Set<String> {
        includingPrereleases ? [betaChannel] : []
    }

    // MARK: - Migration

    /// Moves a stage-2 automatic-checks choice into Sparkle's key, exactly once.
    ///
    /// Before Sparkle, PaneSpace stored the switch in `automaticallyCheckForUpdates`. With both
    /// keys present the state is ambiguous, so Sparkle's wins and the old key is removed; leaving
    /// it would let a later read resurrect a value the user has since changed. When only the old
    /// key exists its value is carried over.
    ///
    /// The flag is set whatever happens, including when neither key exists, so a fresh install does
    /// not re-run this on every launch.
    static func migrateAutomaticChecks(in defaults: UserDefaults) {
        guard !defaults.bool(forKey: migrationFlagKey) else { return }
        if defaults.object(forKey: automaticChecksKey) == nil,
           defaults.object(forKey: supersededAutomaticChecksKey) != nil {
            defaults.set(
                defaults.bool(forKey: supersededAutomaticChecksKey),
                forKey: automaticChecksKey
            )
        }
        defaults.removeObject(forKey: supersededAutomaticChecksKey)
        defaults.set(true, forKey: migrationFlagKey)
    }
}
