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

    private var checkTask: Task<CheckOutcome, Never>?
    private var scheduleTask: Task<Void, Never>?
    /// Keeps a second `start()` from running a second schedule.
    private var hasStarted = false

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
        skippedVersion = defaults.string(forKey: Self.skippedVersionKey)
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
    var automaticallyChecks: Bool {
        get {
            defaults.object(forKey: Self.automaticallyChecksKey) == nil
                ? true
                : defaults.bool(forKey: Self.automaticallyChecksKey)
        }
        set {
            guard newValue != automaticallyChecks else { return }
            defaults.set(newValue, forKey: Self.automaticallyChecksKey)
            if newValue {
                restateSchedule()
            } else {
                // Switching off has to stop work already in flight, not only future runs.
                stopWork()
            }
        }
    }

    /// Whether pre-releases are offered. Shares the `betaUpdates` key the Settings window already
    /// binds, so the toggle and the model cannot disagree.
    var includesPrereleases: Bool {
        get { defaults.bool(forKey: Self.includesPrereleasesKey) }
        set {
            guard newValue != includesPrereleases else { return }
            defaults.set(newValue, forKey: Self.includesPrereleasesKey)
            // The answer depends on the channel, so the previous one no longer applies.
            availableUpdate = nil
            lastManualResult = nil
            lastAutomaticFailure = nil
            restateSchedule()
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
        clearIfShowing(version)
    }

    /// Hides the banner without remembering the version, so the next check may show it again.
    func dismiss() {
        availableUpdate = nil
    }

    private func runCheck(origin: Origin) async -> UpdateCheckResult {
        // A check already in flight is superseded: its answer would describe a different feed state.
        checkTask?.cancel()
        guard let currentVersion else {
            // Nothing to compare against. A manual check reports the reason; a scheduled one is
            // never started in the first place.
            return finish(.failed(.invalidResponse), origin: origin)
        }

        isChecking = true
        let outcome = await performRequest(includingPrereleases: includesPrereleases)
        checkTask = nil
        isChecking = false

        switch outcome {
        case .cancelled:
            // Leave the existing state alone: a cancelled check must not look like a fresh answer.
            guard origin == .manual else { return .failed(.cancelled) }
            return lastManualResult ?? .failed(.cancelled)
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
        checkTask?.cancel()
        checkTask = nil
        guard hasStarted, automaticallyChecks, isSupported else { return }

        let interval = Self.checkInterval
        let clock = self.clock
        scheduleTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.performScheduledCheck()
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
        checkTask?.cancel()
        checkTask = nil
        isChecking = false
    }

    private enum Origin {
        case automatic
        case manual
    }
}
