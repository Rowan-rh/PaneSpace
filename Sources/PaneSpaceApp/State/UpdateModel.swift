import AppKit
import Foundation
import OSLog
import Sparkle

/// The result of a check the user explicitly asked for.
///
/// A scheduled check reports nothing: an update that cannot be fetched is not worth interrupting
/// anyone over, so a failure there is only logged.
enum UpdateCheckResult: Equatable, Sendable {
    case upToDate
    case available(ReleaseInfo)
    case failed(UpdateFeedError)

    var failure: UpdateFeedError? {
        guard case .failed(let error) = self else { return nil }
        return error
    }
}

/// What the update banner needs to know, whichever source produced it.
///
/// Two sources reach the same banner and they describe an update differently: Sparkle's appcast
/// item and stage 2's GitHub release. This is the one shape both are translated into, so the
/// banner never branches on where the update came from.
enum AvailableUpdate: Equatable, Sendable {
    /// An update Sparkle found and is prepared to install.
    case sparkle(SparkleUpdateOffer)
    /// An update found by the stage-2 GitHub feed, in a build with no appcast to ask.
    case release(ReleaseInfo)

    /// The version to show the user.
    var displayVersion: String {
        switch self {
        case .sparkle(let offer): return offer.displayVersion
        case .release(let release): return release.displayVersion
        }
    }

    /// Where the user can read about the release, if anywhere.
    var releaseNotesURL: URL? {
        switch self {
        case .sparkle(let offer): return offer.releaseNotesURL
        case .release(let release): return release.releasePageURL
        }
    }

    /// Whether the update is a pre-release, for a label on the banner.
    var isPrerelease: Bool {
        switch self {
        case .sparkle(let offer): return offer.isPrerelease
        case .release(let release): return release.isPrerelease
        }
    }

    /// Whether this is the version the user chose to ignore.
    func matchesSkippedVersion(_ version: String?) -> Bool {
        guard let version else { return false }
        return displayVersion == version
    }
}

/// Owns update state: whether a newer release exists, when the last check ran, and what the banner
/// should offer.
///
/// **This is a UI state adapter, not the update engine.** Sparkle fetches the appcast, compares
/// versions, filters channels, downloads, verifies and installs; this type translates the callbacks
/// it makes into state a banner can render, and passes the user's intent back. It deliberately keeps
/// no second copy of the answer: a version compared here and a version installed by Sparkle could
/// disagree, and the user would be shown one and given another.
///
/// The stage-2 feed survives as the fallback for a build with no appcast to ask — see `usesSparkle`.
/// Its own tests still cover that path in full.
@MainActor
final class UpdateModel: ObservableObject {
    /// How often a scheduled check runs.
    static let checkInterval: TimeInterval = 24 * 60 * 60

    static let automaticallyChecksKey = UpdatePreferences.automaticChecksKey
    static let includesPrereleasesKey = UpdatePreferences.includesPrereleasesKey
    /// Retained for the stage-2 path, which still skips versions itself. Sparkle keeps its skipped
    /// version in `SUSkippedVersion`; `skip(version:)` only writes this key on that path.
    static let skippedVersionKey = "skippedUpdateVersion"
    /// The build number behind a Sparkle-path skip, paired with the display version beside it.
    ///
    /// Separate from `skippedUpdateVersion` on purpose: that key is the fallback path's answer to
    /// "what was skipped" and reading one as the other is what made the split in `91da2d7`
    /// necessary in the first place.
    static let skippedSparkleBuildKey = "skippedSparkleBuild"
    static let skippedSparkleDisplayVersionKey = "skippedSparkleDisplayVersion"

    /// The newest release worth showing, or nil when there is nothing to show.
    @Published private(set) var availableUpdate: AvailableUpdate?
    @Published private(set) var isChecking = false
    /// When the last check finished, whether it succeeded or not.
    @Published private(set) var lastCheckDate: Date?
    /// The outcome of the last check the user asked for; nil until there has been one.
    ///
    /// A scheduled check that finds an update also writes this, so the name is now narrower than
    /// the property: on the fallback path that check can say `.available(release)` because it holds
    /// the `ReleaseInfo`, and on the Sparkle path it clears the value rather than leave an answer
    /// that the banner has already contradicted. Keeping a correct "0.3.0 is available" or an
    /// honest blank was judged worth the wider meaning, since the alternative is Settings claiming
    /// the app is up to date while an update sits on the banner.
    @Published private(set) var lastManualResult: UpdateCheckResult?
    /// The version the user chose not to hear about again.
    ///
    /// This is what the user is shown and what `AvailableUpdate.matchesSkippedVersion` compares, so
    /// a skip made in this session carries the display version (`0.3.0`), never the build number.
    ///
    /// The *store* keeps the build number, because that is the half Sparkle compares: it records
    /// `SUSkippedVersion` as the update's `versionString`, and so does `SparkleSkippedUpdate`, for
    /// the reason its own documentation gives. What survives a relaunch is therefore whichever half
    /// can be recovered from disk — the display version when `skippedSparkleBuildKey` still matches
    /// `SUSkippedVersion`, and otherwise the build number on its own.
    ///
    /// A relaunch can only ever do that much, because the display string is not in any key Sparkle
    /// writes. The pair exists so the usual case keeps a version the user recognises; it cannot
    /// cover a skip Sparkle recorded on its own, or one whose record has been cleared, and in those
    /// cases the build number is shown rather than a stale display version.
    @Published private(set) var skippedVersion: String?
    /// Why the last scheduled check failed, so the UI can offer a retry without a modal.
    @Published private(set) var lastAutomaticFailure: UpdateFeedError?

    private let feed: any UpdateFeed
    private let clock: any UpdateClock
    private let defaults: UserDefaults
    private let currentVersion: SemanticVersion?
    private let logger = Logger(subsystem: "org.panespace.app", category: "update")
    /// Kept alive for as long as this model observes preferences.
    private var defaultsObservation: NSObjectProtocol?
    /// The skipped version as the *store* holds it, the last time the model looked.
    ///
    /// `UserDefaults` posts one notification for any change, so the cached value is what tells a
    /// write to the skipped-version key apart from an unrelated write in the same process. It holds
    /// the store's own value, never the published one, and those two are deliberately different on
    /// the Sparkle path: the store carries the build number Sparkle compares, while `skippedVersion`
    /// carries the display version the user reads. Comparing the incoming store value against the
    /// published display version made the two look like an external change on every notification,
    /// and the model answered by writing the build number back into what Settings renders.
    /// The two booleans need no cache of their own: comparing against the published properties is
    /// the same test, and a `didSet` is what keeps that comparison honest.
    private var observedSkippedVersion: String?
    /// The controller that owns the updater, or nil in a build that cannot ask one.
    private let updaterController: SPUStandardUpdaterController?
    /// The delegate Sparkle calls back. Held here because Sparkle references it weakly.
    private var sparkleDelegate: SparkleUpdateDelegate?

    private var checkTask: Task<CheckOutcome, Never>?
    private var scheduleTask: Task<Void, Never>?
    /// Keeps a second `start()` from running a second schedule.
    private var hasStarted = false
    /// Counts the checks this model has started.
    ///
    /// A check that has been superseded still runs to completion before its caller resumes, and it
    /// must not touch shared state on the way out. The generation identifies which check owns the
    /// model, so a returning check only clears `checkTask` and `isChecking` when it is still the
    /// current one, and never publishes a result at all once superseded.
    private var checkGeneration = 0
    /// Cancels the running check and marks everything in flight as superseded.
    private func supersedeRunningCheck() {
        checkGeneration += 1
        checkTask?.cancel()
        checkTask = nil
        // Nothing is running under the new generation yet, and the check that was running is on its
        // way out. Clearing this here is what stops a superseded check from leaving `isChecking` true
        // forever: the replacement sets it again on its way in.
        isChecking = false
    }

    private enum CheckOutcome {
        /// A finished check. The release is nil when the feed has nothing published.
        case completed(ReleaseInfo?)
        case failed(UpdateFeedError)
        case cancelled
    }

    init(
        feed: any UpdateFeed = GitHubReleaseFeed(),
        clock: any UpdateClock = SystemUpdateClock(),
        defaults: UserDefaults = .standard,
        currentVersion: SemanticVersion? = AppVersion.current,
        updaterController: SPUStandardUpdaterController? = nil
    ) {
        // The carry-over from the stage-2 key has to happen here, before anything
        // below reads the preference, and not in `applicationDidFinishLaunching`:
        // `@StateObject` builds this model before that callback runs, so a
        // migration there would arrive after the read below and leave the model
        // holding the default ("checks on") until the defaults notification
        // corrected it. `start()` could run first, and a user who had turned
        // automatic checks off in stage 2 would get one check they had declined.
        //
        // It is idempotent (guarded by `hasMigratedUpdatePreferences`), so calling
        // it on every launch costs one UserDefaults read.
        UpdatePreferences.migrateAutomaticChecks(in: defaults)

        self.feed = feed
        self.clock = clock
        self.defaults = defaults
        self.currentVersion = currentVersion
        // Which channel this build runs on, decided in the branch below. Declared here because the
        // skipped-version read that follows it cannot go through `self` yet.
        let onSparkle: Bool
        // A caller that supplies a controller has already decided Sparkle is available. Otherwise
        // one is built only where it can work, and its delegates are attached in
        // `attachSparkleDelegate()` below: Sparkle takes them at init and has no setter, and it
        // holds them weakly, so the model has to own them. Attaching is a separate step because a
        // stored property cannot be passed to another object through `self` before every stored
        // property is initialised.
        if let updaterController {
            self.updaterController = updaterController
            onSparkle = true
        } else if Self.canUseSparkle {
            let delegate = SparkleUpdateDelegate()
            self.updaterController = SPUStandardUpdaterController(
                startingUpdater: false,
                updaterDelegate: delegate,
                userDriverDelegate: delegate
            )
            sparkleDelegate = delegate
            onSparkle = true
        } else {
            self.updaterController = nil
            onSparkle = false
        }
        // Which key records a skip depends on the channel, so which key is read has to depend on it
        // too. Both happen before every stored property is initialised, so the answer is carried out
        // of the branch above rather than read back through `self.updaterController`.
        let storedSkipped = Self.storedSkippedVersion(in: defaults, usesSparkle: onSparkle)
        // Read into locals first: a stored property cannot be read through `self` before every other
        // stored property is initialized.
        let storedAutomaticChecks = Self.readAutomaticChecks(from: defaults)
        let storedPrereleases = defaults.bool(forKey: Self.includesPrereleasesKey)
        skippedVersion = storedSkipped
        automaticallyChecks = storedAutomaticChecks
        includesPrereleases = storedPrereleases
        observedSkippedVersion = storedSkipped
        observePreferences()
        attachSparkleDelegate()
    }

    /// Hands the delegate to the model it reports to.
    ///
    /// The reference from the delegate back to this model is weak, and the application holds the
    /// model for the process's lifetime, so nothing is retained in a cycle.
    private func attachSparkleDelegate() {
        sparkleDelegate?.attach(to: self)
    }

    // MARK: - Sparkle availability

    /// Whether this build can ask Sparkle about updates.
    ///
    /// Two things are required, and both are decided at build time by `build-app.sh`. The framework
    /// has to be present — otherwise there is no updater at all — and the bundle needs a public key,
    /// because without one there is no appcast to fetch and Sparkle has nothing to compare against.
    /// A build missing either keeps using the stage-2 feed, which is a complete path in its own
    /// right and is what an unsigned local build ships.
    ///
    /// The bundle check matters because a test runner and `swift run` are not app bundles: Sparkle
    /// refuses to start against them, so asking would leave the updater dead rather than absent.
    static var canUseSparkle: Bool {
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return false }
        let key = (Bundle.main.infoDictionary?["SUPublicEDKey"] as? String) ?? ""
        guard !key.isEmpty else { return false }
        return key.range(of: "^[A-Za-z0-9+/]{43}=$", options: .regularExpression) != nil
    }

    /// Whether updates come from Sparkle rather than the stage-2 feed.
    var usesSparkle: Bool { updaterController != nil }

    /// The updater, for a view that binds Sparkle's own settings directly.
    var updater: SPUUpdater? { updaterController?.updater }

    // MARK: - Lifecycle

    /// Removes the preference observer.
    ///
    /// `isolated deinit` rather than `nonisolated deinit` + `MainActor.assumeIsolated`. The
    /// observer is stored main-actor state, so a `deinit` that reaches for it has to be on the main
    /// actor; `assumeIsolated` asserted that without being able to enforce it, which is a promise
    /// about every call site rather than a property of the type. `isolated deinit` makes the
    /// isolation part of the declaration. The observer holds only a weak reference to the model,
    /// so nothing outlives it either way.
    isolated deinit {
        if let defaultsObservation {
            NotificationCenter.default.removeObserver(defaultsObservation)
        }
    }

    /// Watches the injected defaults so the model reacts however the preference was written.
    ///
    /// A view may bind these keys with `@AppStorage`, a `Binding`, or plain `UserDefaults` code, and
    /// only the first of those would ever reach a computed setter. Observing the store means the
    /// response is the same in every case, which is what keeps the model and the Settings window
    /// from disagreeing about which channel is active.
    private func observePreferences() {
        let defaults = self.defaults
        defaultsObservation = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: nil
        ) { [weak self] _ in
            // The notification arrives on whatever thread wrote the value; the response touches
            // main-actor state, so the hop is explicit.
            Task { @MainActor [weak self] in
                self?.preferencesDidChange()
            }
        }
    }

    private func preferencesDidChange() {
        let automaticChecks = Self.readAutomaticChecks(from: defaults)
        let prereleases = defaults.bool(forKey: Self.includesPrereleasesKey)
        // Each channel records and compares a skip under its own key, so each reads only its own:
        // Sparkle compares `SUSkippedVersion` / `SUSkippedMajor*`, and the fallback compares the
        // display version PaneSpace wrote. See `storedSkippedVersion(in:usesSparkle:)`.
        let skipped = Self.storedSkippedVersion(in: defaults, usesSparkle: usesSparkle)

        // Assigning the published properties is what routes the response. Each `didSet` writes the
        // value back and then performs exactly the cancellation or rescheduling a write through the
        // model would have performed, so there is one response path rather than two that can drift
        // apart. The skipped version is compared against the cached *store* value rather than the
        // published one, because on the Sparkle path the two differ on purpose; comparing against
        // the published value made every notification look like a change and put the build number
        // back into what Settings renders.
        if prereleases != includesPrereleases {
            includesPrereleases = prereleases
        }
        if skipped != observedSkippedVersion {
            observedSkippedVersion = skipped
            skippedVersion = skipped
        }
        if automaticChecks != automaticallyChecks {
            automaticallyChecks = automaticChecks
        }
    }

    private static func readAutomaticChecks(from defaults: UserDefaults) -> Bool {
        defaults.object(forKey: automaticallyChecksKey) == nil
            ? true
            : defaults.bool(forKey: automaticallyChecksKey)
    }

    /// The skipped version as the store holds it right now, from the channel that is running.
    ///
    /// One function, because the two channels record a skip under different keys and reading them
    /// in one fixed order is how the cache and the store drift apart: `skip` and
    /// `mirrorSkippedVersion` looked only at Sparkle's keys while the observer looked at PaneSpace's
    /// first, so a leftover key from the other channel read as the store changing underneath it and
    /// published a stale version over the one the user had just chosen.
    ///
    /// The split is not a preference between the two keys, it is which one the engine will honour.
    /// Sparkle compares `SUSkippedVersion` and `SUSkippedMajor*`; the fallback channel compares the
    /// display version it wrote, and a build number never matches that. A key left by the other
    /// channel is therefore not a weaker answer, it is one nothing will act on: reading it either
    /// way yields a version that is skipped on one channel and ignored on the other.
    private static func storedSkippedVersion(in defaults: UserDefaults, usesSparkle: Bool) -> String? {
        if usesSparkle {
            guard let build = SparkleSkippedUpdate.currentSkippedVersion(in: defaults) else {
                return nil
            }
            // The pair answers for the key it was written beside, and for nothing else. Sparkle
            // owns `SUSkippedVersion`, so it can be rewritten without PaneSpace hearing about it —
            // by a skip taken in Sparkle's own window, or by the record being cleared — and the
            // display version left behind then describes a skip that no longer exists. Matching the
            // build number is what tells the two apart; the comparison never changes what Sparkle
            // skips, only what Settings shows.
            let recordedBuild = defaults.string(forKey: skippedSparkleBuildKey)
            let recordedDisplay = defaults.string(forKey: skippedSparkleDisplayVersionKey)
            let skippedNow = defaults.string(forKey: SparkleSkippedUpdate.minorVersionKey)
            if skippedNow == recordedBuild, let recordedDisplay {
                return recordedDisplay
            }
            return build
        }
        return defaults.string(forKey: skippedVersionKey)
    }

    /// Whether this build can be compared with releases at all.
    ///
    /// A binary launched outside an app bundle — `swift run`, a test runner — has no
    /// `CFBundleShortVersionString`, and "is this release newer?" has no honest answer without one,
    /// so nothing is checked.
    var isSupported: Bool { currentVersion != nil }

    /// The version this build compares against, for display in Settings.
    var currentVersionDescription: String { currentVersion?.description ?? L10n.text("Unknown") }

    /// Whether checks happen on their own. Defaults to true for a new install.
    ///
    /// The single stored copy is Sparkle's own key, so the Settings toggle and Sparkle cannot
    /// disagree about whether checks run. On the stage-2 path the same key is read and written
    /// directly, which keeps one key for both paths rather than migrating it a second time.
    @Published var automaticallyChecks: Bool {
        didSet {
            guard automaticallyChecks != oldValue else { return }
            defaults.set(automaticallyChecks, forKey: Self.automaticallyChecksKey)
            if usesSparkle {
                // Sparkle owns the schedule; the property is what it reads. Setting it also restarts
                // its update cycle, so nothing else has to be rescheduled here.
                updaterController?.updater.automaticallyChecksForUpdates = automaticallyChecks
            } else if automaticallyChecks {
                restateSchedule()
            } else {
                // Switching off has to stop work already in flight, not only future runs.
                stopWork()
            }
        }
    }

    /// Whether pre-releases are offered. Shares the `betaUpdates` key the Settings window already
    /// binds, so the toggle and the model cannot disagree.
    ///
    /// With Sparkle the key is a *view* of which channels the updater may look in, not a stored
    /// answer: the updater asks the delegate again on the next check, and the banner is dropped
    /// because the version on it belonged to a channel that may no longer be allowed.
    @Published var includesPrereleases: Bool {
        didSet {
            guard includesPrereleases != oldValue else { return }
            defaults.set(includesPrereleases, forKey: Self.includesPrereleasesKey)
            handlePrereleasesChanged()
        }
    }

    /// Begins the update schedule. Calling it twice keeps the first schedule.
    ///
    /// The first check runs immediately rather than a day later, because someone who just launched
    /// after a release is exactly the case an update banner exists for.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        if usesSparkle {
            startSparkle()
        } else {
            restateSchedule()
        }
    }

    /// Stops the schedule, cancels any check in flight, and allows a later `start()`.
    func stop() {
        hasStarted = false
        stopWork()
    }

    /// Checks now because the user asked, and publishes the outcome.
    ///
    /// On the Sparkle path the check is Sparkle's, and it reports back through the delegate: the
    /// result arrives in `lastManualResult` when the cycle ends, so the value returned here is only
    /// what is known at this moment.
    @discardableResult
    func checkNow() async -> UpdateCheckResult {
        guard usesSparkle else {
            return await runCheck(origin: .manual)
        }
        isChecking = true
        updaterController?.updater.checkForUpdates()
        return .upToDate
    }

    /// Stops offering the offered update.
    ///
    /// On the Sparkle path this records the skip in the keys Sparkle reads it from, because taking
    /// over presentation means its own "Skip" button is never shown. Writing a PaneSpace key instead
    /// would give two answers to one question, and the next check would offer the same version again.
    func skip(version: String) {
        if case .sparkle(let offer) = availableUpdate, offer.displayVersion == version {
            SparkleSkippedUpdate.recordSkip(of: offer, in: defaults)
            Self.recordSkippedDisplayVersion(of: offer, in: defaults)
            // The store keeps the build number because that is what Sparkle compares; the published
            // property keeps the display version because that is what the user is shown and what
            // `matchesSkippedVersion` compares. Writing the build number into the published value
            // put "30099" in Settings and made `clearIfShowing` miss the banner it had just hidden.
            skippedVersion = offer.displayVersion
            // The cache holds what the store now holds, so the notification this write posts is
            // recognised as our own and does not come back as an external change.
            observedSkippedVersion = Self.storedSkippedVersion(in: defaults, usesSparkle: usesSparkle)
            availableUpdate = nil
            return
        }
        skippedVersion = version
        defaults.set(version, forKey: Self.skippedVersionKey)
        // Kept in step with the store so the write above is not re-applied as an external change.
        observedSkippedVersion = Self.storedSkippedVersion(in: defaults, usesSparkle: usesSparkle)
        clearIfShowing(version)
    }

    /// Installs the offered update.
    ///
    /// The banner never downloads or replaces anything itself. `checkForUpdates()` is what brings the
    /// update back into Sparkle's own window, which is where Install, Skip and Release Notes live and
    /// where the version the user confirms is the one Sparkle downloads. A separate action that only
    /// PaneSpace knew about would be a second update path, and the version it installed could differ
    /// from the one the banner named.
    func installAvailableUpdate() {
        guard case .sparkle = availableUpdate else {
            // The stage-2 path found a release it cannot install; its whole design is "tell the
            // user where the release is", so the release page is the honest destination.
            if let url = availableUpdate?.releaseNotesURL {
                NSWorkspace.shared.open(url)
            }
            return
        }
        updaterController?.updater.checkForUpdates()
    }

    /// Hides the banner without remembering the version, so the next check may show it again.
    func dismiss() {
        availableUpdate = nil
    }

    // MARK: - Sparkle

    /// Starts the updater and applies the stored schedule to it.
    private func startSparkle() {
        guard let updater = updaterController?.updater else { return }
        // The channel is asked per check through the delegate, but the interval and the switch are
        // the updater's own properties, so they are set before it starts scheduling.
        updater.automaticallyChecksForUpdates = automaticallyChecks
        updater.updateCheckInterval = Self.checkInterval
        do {
            try updater.start()
        } catch {
            // Nothing falls back to the stage-2 feed here, and the previous version of this comment
            // said it did. The controller is a stored `let` picked in `init`, so `usesSparkle` is
            // still true and the stage-2 schedule never starts: a bundle Sparkle refuses leaves an
            // updater that exists but is not running. That is a dead updater rather than a wrong
            // one -- nothing downloads or installs -- and the log is the only record of why, which
            // is why it names the coarse case and nothing else (no URL, no path, no bundle id).
            //
            // Making the fallback real would mean making the controller a published `var`, because
            // `updater` is bound directly by the Settings window and a plain `let` -> `var` change
            // would leave those bindings showing a controller that is no longer there.
            logger.notice("Sparkle refused to start: \(self.logReason(for: Self.mapSparkleError(error)), privacy: .public)")
        }
    }

    /// Notes the display version for a skip just recorded under a build number.
    ///
    /// The two keys are read back together by `storedSkippedVersion(in:usesSparkle:)`, so writing
    /// them here keeps the display version available on the next launch without adding anything
    /// Sparkle reads or compares.
    private static func recordSkippedDisplayVersion(of offer: SparkleUpdateOffer, in defaults: UserDefaults) {
        defaults.set(offer.versionString, forKey: skippedSparkleBuildKey)
        defaults.set(offer.displayVersion, forKey: skippedSparkleDisplayVersionKey)
    }

    /// Publishes an offer Sparkle handed the presentation of.
    func presentSparkleOffer(_ offer: SparkleUpdateOffer?) {
        guard let offer else { return }
        isChecking = false
        availableUpdate = .sparkle(offer)
        retireSupersededManualResult()
    }

    /// Records that Sparkle finished looking, whether or not an update was found.
    func noteSparkleFoundUpdate() {
        isChecking = false
        lastCheckDate = clock.now()
        retireSupersededManualResult()
    }

    /// Withdraws the last manual check's answer, because an update now exists.
    ///
    /// "PaneSpace is up to date" and a banner offering 0.3.0 cannot both be true of this app. The
    /// answer describes the check that produced it, and the banner outlives that check, so the
    /// moment a usable update is known the answer stops being current — including when a *later,
    /// different* check found it, and including when the user then dismisses the install prompt,
    /// which leaves the banner up while asking for no verdict at all.
    ///
    /// `UpdateCheckResult.available` would carry the finding better, but it holds a `ReleaseInfo`
    /// and only the fallback channel has one: a Sparkle offer knows its display version, not the
    /// release it came from or when that was published. Filling those in would put a URL and a date
    /// in front of the user that nothing stands behind, so the result is cleared and Settings falls
    /// back to the time of the last check, which claims nothing about the outcome.
    private func retireSupersededManualResult() {
        lastManualResult = nil
    }

    /// Drops an offer the last check did not confirm.
    func dropStaleSparkleOffer() {
        availableUpdate = nil
    }

    /// Mirrors a skip Sparkle recorded itself, so the banner stops offering it.
    ///
    /// `version` is the display version, not Sparkle's `versionString`: this value is shown to the
    /// user and compared against the banner's display version, and a build number would miss on
    /// both counts — the banner it just dismissed would stay up.
    func mirrorSkippedVersion(_ version: String?) {
        guard let version else { return }
        // Sparkle recorded this skip itself, so the build number is already in the store and the
        // display version arrives here; pairing them is what lets the next launch show a version
        // the user recognises. Nothing is written when the store holds no build number: the pair is
        // only read back when it matches `SUSkippedVersion`, and recording half of one on its own
        // would leave a display version describing a skip that was never recorded.
        if let build = defaults.string(forKey: SparkleSkippedUpdate.minorVersionKey) {
            defaults.set(build, forKey: Self.skippedSparkleBuildKey)
            defaults.set(version, forKey: Self.skippedSparkleDisplayVersionKey)
        }
        skippedVersion = version
        // The cache holds the store's value — the build number Sparkle wrote — not the display
        // version handed over here. The store and the published property differ on purpose, so the
        // observer would otherwise see them as an external change and replace the display version
        // with the build number a moment later.
        observedSkippedVersion = Self.storedSkippedVersion(in: defaults, usesSparkle: usesSparkle)
        clearIfShowing(version)
    }

    /// The update session is over, so nothing about the last offer is still true.
    func endSparkleUpdateSession() {
        availableUpdate = nil
    }

    /// Publishes the end of a Sparkle update cycle.
    ///
    /// A manual check reports its outcome; a scheduled one only records the time and any failure,
    /// exactly as the stage-2 path does, so a background failure never interrupts anyone.
    func finishSparkleCycle(updateCheck: SPUUpdateCheck, error: (any Error)?) {
        lastCheckDate = clock.now()
        isChecking = false
        // Sparkle hands back two ordinary endings of a cycle through the same
        // error channel as a broken feed; `isOrdinarySparkleOutcome` tells them
        // apart, and an ending that is not a failure must not be reported as one.
        let failure = error.flatMap { error in
            Self.isOrdinarySparkleOutcome(error) ? nil : Self.mapSparkleError(error)
        }
        switch updateCheck {
        case .updates:
            lastAutomaticFailure = nil
            // The user cancelled at the authorization prompt, or chose to be asked again later. An
            // update exists and was not installed, so neither answer is true: reporting `.upToDate`
            // would tell the user there is nothing to install when the thing they just dismissed is
            // sitting right there. `.failed` would be worse -- they did nothing wrong, and there is
            // nothing to retry. The banner is still up, so a previous check's answer was already
            // dropped when the update was found; had nothing superseded it, Settings would be
            // showing "Last checked <time>", which claims nothing about the outcome either way.
            if error.map(Self.isSparkleInstallationDeclined) ?? false {
                return
            }
            if let failure {
                lastManualResult = .failed(failure)
            } else if Self.isSparkleNoUpdateError(error) {
                lastManualResult = .upToDate
            } else {
                // `error == nil` on `.updates` is not "found nothing". It is how Sparkle ends the
                // cycle when the user dismissed or skipped an update it had already found — the
                // header calls that "the same as no error" — so writing `.upToDate` here told
                // people the app had nothing new while the update they just waved away was still
                // sitting on the banner. Only `SUNoUpdateError` (1001) means the check looked and
                // found nothing; for everything else Settings falls back to "Last checked <time>",
                // which claims nothing about the outcome.
                lastManualResult = nil
            }
        case .updatesInBackground:
            if let failure {
                lastAutomaticFailure = failure
                logger.debug("scheduled update check failed: \(self.logReason(for: failure), privacy: .public)")
            } else {
                lastAutomaticFailure = nil
            }
        case .updateInformation:
            // Sparkle's information probe feeds its own permission prompt; it has no outcome to
            // publish and must not be mistaken for the user asking for a check.
            break
        @unknown default:
            break
        }
    }

    /// Whether this ending of a cycle is Sparkle's "there was nothing to install".
    ///
    /// On `.updates`, a nil ending is not that answer — it is the dismissal described above — so
    /// only `SUNoUpdateError` qualifies. `.updatesInBackground` is not routed through this at all.
    static func isSparkleNoUpdateError(_ error: (any Error)?) -> Bool {
        guard let error else { return false }
        let nsError = error as NSError
        guard nsError.domain == SUSparkleErrorDomain else { return false }
        // Converted through the enum's own type for the same reason as `mapSparkleError` and
        // `isOrdinarySparkleOutcome`: the code space is `SUError`'s, not an `Int`'s.
        return SUError(rawValue: Int32(truncatingIfNeeded: nsError.code)) == .some(.noUpdateError)
    }

    /// Whether a Sparkle error is the normal end of a cycle rather than a failure.
    ///
    /// Sparkle reports through one channel, and three results travel down it that
    /// are not failures at all:
    ///
    /// - `SUNoUpdateError` — the feed was fetched and there is nothing newer than
    ///   this build. That is the answer to the question the user asked.
    /// - `SUInstallationCanceledError` — the user cancelled the install when
    ///   prompted for authorization, which is them declining, not the feed
    ///   misbehaving. Sparkle's own wording for it, in `SPUUpdaterDelegate.h`.
    /// - `SUInstallationAuthorizeLaterError` — the same moment answered the other
    ///   way: "not now, ask me again". Sparkle groups it with the two above in
    ///   `SPUUpdater.m:798`, where it declines even to log them.
    ///
    /// Left alone, all three reached `mapSparkleError`'s `default` arm and became
    /// `.unreachable`: a manual check that found nothing reported "the update
    /// server could not be reached", and a scheduled one recorded the same as a
    /// background failure worth a retry. Neither is retryable and neither is
    /// true.
    ///
    /// Everything else keeps its existing meaning, including the codes that
    /// describe a feed nobody can trust. Only codes that name a completed,
    /// uneventful cycle are treated this way — an unlisted Sparkle error stays a
    /// failure rather than being quietly reclassified.
    static func isOrdinarySparkleOutcome(_ error: any Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == SUSparkleErrorDomain else { return false }
        // Converted through the enum's own type for the same reason as
        // `mapSparkleError`: the code space is `SUError`'s, not an `Int`'s.
        let code = SUError(rawValue: Int32(truncatingIfNeeded: nsError.code))
        return code == .some(.noUpdateError) || isInstallationDeclined(code)
    }

    /// Whether a Sparkle error means the user walked away from an available update.
    ///
    /// Distinct from `isOrdinarySparkleOutcome`, which only says the cycle did not
    /// fail. These two are ordinary endings that still leave an update uninstalled,
    /// so a manual check must not answer the user with `.upToDate` -- see the
    /// `.updates` arm of `finishSparkleCycle`.
    static func isSparkleInstallationDeclined(_ error: any Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == SUSparkleErrorDomain else { return false }
        let code = SUError(rawValue: Int32(truncatingIfNeeded: nsError.code))
        return isInstallationDeclined(code)
    }

    private static func isInstallationDeclined(_ code: SUError?) -> Bool {
        code == .some(.installationCanceledError) || code == .some(.installationAuthorizeLaterError)
    }

    /// Normalizes a Sparkle error into the coarse cases the UI already knows how to word.
    ///
    /// Sparkle's errors carry URLs, host paths and internal codes, so nothing but the coarse case
    /// crosses into state or into a log line.
    static func mapSparkleError(_ error: any Error) -> UpdateFeedError {
        let nsError = error as NSError
        guard nsError.domain == SUSparkleErrorDomain else { return .unreachable }
        // The Sparkle error codes are an `SUError` enum, which is `Int32`-backed, while
        // `NSError.code` hands back an `Int`. Converting through the enum's own type is what keeps
        // the comparison honest instead of relying on a coincidence of raw values.
        let code = SUError(rawValue: Int32(truncatingIfNeeded: nsError.code))
        return switch code {
        case .some(.appcastParseError),
             .some(.appcastError),
             .some(.resumeAppcastError),
             .some(.invalidFeedURLError),
             .some(.insecureFeedURLError),
             .some(.noPublicDSAFoundError),
             .some(.insufficientSigningError):
            // The feed is missing, unparseable, plaintext, or unsigned. None of these is a reason to
            // offer a download, so the user is put on a retry and the failure stays coarse.
            .invalidResponse
        default:
            .unreachable
        }
    }

    // MARK: - Stage-2 feed path

    private func runCheck(origin: Origin) async -> UpdateCheckResult {
        // A check already in flight is superseded: its answer would describe a different feed state.
        supersedeRunningCheck()
        let generation = checkGeneration
        guard let currentVersion else {
            // Nothing to compare against. A manual check reports the reason; a scheduled one is
            // never started in the first place.
            return finish(.failed(.invalidResponse), origin: origin)
        }

        isChecking = true
        let outcome = await performRequest(includingPrereleases: includesPrereleases)
        // The state below belongs to whichever check is current. A check that lost the model while
        // it was waiting must not clear the running check's task, must not report it as no longer
        // in progress, and must not publish its own result.
        guard generation == checkGeneration else {
            return .failed(.cancelled)
        }
        checkTask = nil
        isChecking = false

        switch outcome {
        case .cancelled:
            // A cancellation is not an answer. Reporting the previous result would hand the caller
            // something stale, so the caller is told the check was cancelled and no state is
            // published, leaving whatever the replacement check publishes intact.
            return .failed(.cancelled)
        case .failed(let error):
            return finish(.failed(error), origin: origin)
        case .completed(let release):
            if let release, release.isUpdate(over: currentVersion), isOfferable(release) {
                return finish(.available(release), origin: origin)
            }
            return finish(.upToDate, origin: origin)
        }
    }

    /// Runs the feed request off the main actor. `Task {}` inherits the main actor, so the work is
    /// explicitly detached from it and the result comes back on the main actor.
    private func performRequest(includingPrereleases: Bool) async -> CheckOutcome {
        let feed = self.feed
        let task = Task<CheckOutcome, Never>.detached {
            do {
                let release = try await feed.latestRelease(includingPrereleases: includingPrereleases)
                // Cancellation is checked after the call as well as in the failure paths: a request
                // that finishes normally after being cancelled still has to be discarded, or a
                // superseded check would overwrite the answer that replaced it.
                return Task.isCancelled ? .cancelled : .completed(release)
            } catch let error as UpdateFeedError {
                return Task.isCancelled ? .cancelled : .failed(error)
            } catch is CancellationError {
                return .cancelled
            } catch {
                return Task.isCancelled ? .cancelled : .failed(.unreachable)
            }
        }
        checkTask = task
        return await task.value
    }

    private func finish(_ result: UpdateCheckResult, origin: Origin) -> UpdateCheckResult {
        lastCheckDate = clock.now()
        switch origin {
        case .manual:
            lastManualResult = result
            lastAutomaticFailure = nil
            if case .failed(let error) = result {
                // The log names the reason only. No host, no path, no request parameters.
                logger.notice("manual update check failed: \(self.logReason(for: error), privacy: .public)")
            }
        case .automatic:
            if case .failed(let error) = result {
                lastAutomaticFailure = error
                logger.debug("scheduled update check failed: \(self.logReason(for: error), privacy: .public)")
            } else {
                lastAutomaticFailure = nil
            }
        }

        switch result {
        case .available(let release):
            availableUpdate = .release(release)
            // A scheduled check that finds a release makes the earlier manual answer stale in the
            // same way a Sparkle finding does. Here the release is in hand, so the result can say
            // what was found rather than going blank — the TL's preference, and better than nil
            // because the reader learns there is something to install. A manual check has already
            // been assigned `.available(release)` above and never reaches here with that origin.
            if origin != .manual { lastManualResult = .available(release) }
        case .upToDate, .failed:
            // A scheduled failure keeps whatever the user was already told, so a transient error
            // never hides a banner that is still true.
            if origin == .manual { availableUpdate = nil }
        }
        return result
    }

    private func logReason(for error: UpdateFeedError) -> String {
        error.isRateLimited ? "rate-limited" : "unavailable"
    }

    /// A release the user has not chosen to ignore. Skipping hides one version, not the channel: a
    /// higher version is still offered.
    private func isOfferable(_ release: ReleaseInfo) -> Bool {
        guard let skippedVersion else { return true }
        return release.tag != skippedVersion && release.displayVersion != skippedVersion
    }

    private func clearIfShowing(_ version: String) {
        if availableUpdate?.matchesSkippedVersion(version) == true {
            availableUpdate = nil
        }
    }

    private func restateSchedule() {
        scheduleTask?.cancel()
        scheduleTask = nil
        supersedeRunningCheck()
        guard hasStarted, automaticallyChecks, isSupported else { return }

        let interval = Self.checkInterval
        let clock = self.clock
        scheduleTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    // Held strongly for the check only. A binding scoped to the whole loop would
                    // also cover the sleep below, keeping a released model alive for the next 24
                    // hours — the opposite of what a released model should do.
                    guard let self else { return }
                    await self.performScheduledCheck()
                }
                do {
                    try await clock.sleep(for: interval)
                } catch {
                    // Cancellation ends the schedule; nothing is left to do on this turn.
                    return
                }
            }
        }
    }

    private func performScheduledCheck() async {
        guard automaticallyChecks, isSupported else { return }
        // The outcome is already published on the model; the caller has nothing to do with it.
        _ = await runCheck(origin: .automatic)
    }

    private func stopWork() {
        scheduleTask?.cancel()
        scheduleTask = nil
        supersedeRunningCheck()
        isChecking = false
    }

    /// The channel changed, so every answer computed for the previous one is no longer an answer.
    private func handlePrereleasesChanged() {
        availableUpdate = nil
        lastManualResult = nil
        lastAutomaticFailure = nil
        if usesSparkle {
            // Nothing to reschedule: Sparkle asks the delegate for the channel on each check. The
            // banner is dropped above because the version it named may no longer be allowed.
            if hasStarted, automaticallyChecks {
                updaterController?.updater.resetUpdateCycle()
            }
            return
        }
        restateSchedule()
    }

    private enum Origin {
        case automatic
        case manual
    }
}
