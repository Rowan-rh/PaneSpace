import Foundation
import OSLog

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

/// Owns update state: whether a newer release exists, when the last check ran, and when the next
/// one is due.
///
/// This is the only type that talks to the feed. Network work runs in a child task so the main
/// actor is never blocked, and any check in flight is cancelled when a newer check starts or when
/// the user switches automatic checks off.
@MainActor
final class UpdateModel: ObservableObject {
    /// How often a scheduled check runs.
    static let checkInterval: TimeInterval = 24 * 60 * 60

    static let automaticallyChecksKey = "automaticallyCheckForUpdates"
    static let includesPrereleasesKey = "betaUpdates"
    static let skippedVersionKey = "skippedUpdateVersion"

    /// The newest release worth showing, or nil when there is nothing to show.
    @Published private(set) var availableUpdate: ReleaseInfo?
    @Published private(set) var isChecking = false
    /// When the last check finished, whether it succeeded or not.
    @Published private(set) var lastCheckDate: Date?
    /// The outcome of the last check the user asked for; nil until there has been one.
    @Published private(set) var lastManualResult: UpdateCheckResult?
    /// The version the user chose not to hear about again.
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
    /// The skipped version this model last reacted to.
    ///
    /// `UserDefaults` posts one notification for any change, so the cached value is what tells a
    /// write to `skippedUpdateVersion` apart from an unrelated write in the same process. The two
    /// booleans need no cache of their own: comparing against the published properties is the same
    /// test, and a `didSet` is what keeps that comparison honest.
    private var observedSkippedVersion: String?

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
        currentVersion: SemanticVersion? = AppVersion.current
    ) {
        self.feed = feed
        self.clock = clock
        self.defaults = defaults
        self.currentVersion = currentVersion
        let storedSkipped = defaults.string(forKey: Self.skippedVersionKey)
        // Read into locals first: a stored property cannot be read through `self` before every other
        // stored property is initialized.
        let storedAutomaticChecks = Self.readAutomaticChecks(from: defaults)
        let storedPrereleases = defaults.bool(forKey: Self.includesPrereleasesKey)
        skippedVersion = storedSkipped
        automaticallyChecks = storedAutomaticChecks
        includesPrereleases = storedPrereleases
        observedSkippedVersion = storedSkipped
        observePreferences()
    }

    /// Removes the preference observer. The token is cleared here because a `deinit` may not touch
    /// main-actor state, and the observer holds only a weak reference, so nothing outlives the model.
    nonisolated deinit {
        MainActor.assumeIsolated {
            if let defaultsObservation {
                NotificationCenter.default.removeObserver(defaultsObservation)
            }
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
        let skipped = defaults.string(forKey: Self.skippedVersionKey)

        // Assigning the published properties is what routes the response. Each `didSet` writes the
        // value back and then performs exactly the cancellation or rescheduling a write through the
        // model would have performed, so there is one response path rather than two that can drift
        // apart. The comparison is against the published value rather than a separate cache, so the
        // value and the response to it cannot disagree.
        if prereleases != includesPrereleases {
            includesPrereleases = prereleases
        }
        if skipped != skippedVersion {
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
    /// Published so a view can bind it directly and still refresh: this is the model behind the
    /// Settings toggle, not a value the toggle writes and the model merely reads back.
    @Published var automaticallyChecks: Bool {
        didSet {
            guard automaticallyChecks != oldValue else { return }
            defaults.set(automaticallyChecks, forKey: Self.automaticallyChecksKey)
            if automaticallyChecks {
                restateSchedule()
            } else {
                // Switching off has to stop work already in flight, not only future runs.
                stopWork()
            }
        }
    }

    /// Whether pre-releases are offered. Shares the `betaUpdates` key the Settings window already
    /// binds, so the toggle and the model cannot disagree.
    @Published var includesPrereleases: Bool {
        didSet {
            guard includesPrereleases != oldValue else { return }
            defaults.set(includesPrereleases, forKey: Self.includesPrereleasesKey)
            handlePrereleasesChanged()
        }
    }

    /// Begins the scheduled check. Calling it twice keeps the first schedule.
    ///
    /// The first check runs immediately rather than a day later, because someone who just launched
    /// after a release is exactly the case an update banner exists for.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        restateSchedule()
    }

    /// Stops the schedule, cancels any check in flight, and allows a later `start()`.
    func stop() {
        hasStarted = false
        stopWork()
    }

    /// Checks now because the user asked, and publishes the outcome.
    @discardableResult
    func checkNow() async -> UpdateCheckResult {
        let result = await runCheck(origin: .manual)
        return result
    }

    /// Stops offering `version` until a higher one appears.
    func skip(version: String) {
        skippedVersion = version
        defaults.set(version, forKey: Self.skippedVersionKey)
        // Kept in step with the store so the write above is not re-applied as an external change.
        observedSkippedVersion = version
        clearIfShowing(version)
    }

    /// Hides the banner without remembering the version, so the next check may show it again.
    func dismiss() {
        availableUpdate = nil
    }

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
            // written, leaving whatever the replacement check publishes intact.
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
            availableUpdate = release
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
        if availableUpdate?.tag == version || availableUpdate?.displayVersion == version {
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
                // Held strongly for the length of one iteration: without it a released model would
                // keep waking every 24 hours to do nothing.
                guard let self else { return }
                await self.performScheduledCheck()
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
        restateSchedule()
    }

    private enum Origin {
        case automatic
        case manual
    }
}
