import Combine
import Foundation
import Synchronization
import XCTest
@testable import PaneSpaceApp

/// Counts `objectWillChange` publications, so a test can assert that a bound property announces its
/// change instead of only storing it.
@MainActor
private final class ObjectWillChangeRecorder {
    private(set) var count = 0

    func record() {
        count += 1
    }
}

/// A feed that answers with whatever a test puts in it, and can be held mid-request so a test can
/// observe or cancel a check that is genuinely in flight.
private actor StubUpdateFeed: UpdateFeed {
    private var results: [Result<ReleaseInfo?, UpdateFeedError>] = []
    private var fallback: Result<ReleaseInfo?, UpdateFeedError>
    private var requestedPrereleaseFlags: [Bool] = []
    private var holds = false
    /// Requests before this count answer normally; the rest wait for `release()`. This is how a
    /// test freezes the schedule and then inspects the state the last answer produced.
    private var holdAfterRequest = Int.max
    private var pendingContinuations: [CheckedContinuation<Void, Never>] = []
    private var startedRequests = 0

    init(fallback: Result<ReleaseInfo?, UpdateFeedError> = .success(nil)) {
        self.fallback = fallback
    }

    func enqueue(_ result: Result<ReleaseInfo?, UpdateFeedError>) {
        results.append(result)
    }

    var requestCount: Int { startedRequests }
    var prereleaseFlags: [Bool] { requestedPrereleaseFlags }

    /// Makes requests wait until `release()` is called, which is how a test cancels a check that is
    /// actually in flight rather than one that merely could be.
    func holdRequests() {
        holds = true
    }

    /// Answers normally until `count` requests have been made, then holds every further one.
    func holdRequests(after count: Int) {
        holdAfterRequest = count
    }

    func release() {
        let continuations = pendingContinuations
        pendingContinuations.removeAll()
        holds = false
        for continuation in continuations {
            continuation.resume()
        }
    }

    /// Resumes a single held request — the oldest — and leaves the rest waiting.
    ///
    /// `release()` answers everything at once, which cannot express the interleaving that matters
    /// here: a superseded check returning while the check that replaced it is still genuinely in
    /// flight. That window is where the state the two checks share gets corrupted.
    func releaseOne() {
        guard !pendingContinuations.isEmpty else { return }
        pendingContinuations.removeFirst().resume()
    }

    /// Stops holding without answering anything already waiting, so a later request can complete on
    /// its own. Used to show that a model still works after its checks have been cancelled.
    func stopHolding() {
        holds = false
        holdAfterRequest = Int.max
    }

    func latestRelease(includingPrereleases: Bool) async throws -> ReleaseInfo? {
        startedRequests += 1
        let isAfterHoldPoint = startedRequests > holdAfterRequest
        requestedPrereleaseFlags.append(includingPrereleases)
        let queued = results.isEmpty ? fallback : results.removeFirst()
        if holds || isAfterHoldPoint {
            await withCheckedContinuation { continuation in
                if holds || isAfterHoldPoint {
                    pendingContinuations.append(continuation)
                } else {
                    continuation.resume()
                }
            }
        }
        return try queued.get()
    }
}

/// A clock a test moves by hand, and whose sleeps complete only when the test says so.
///
/// A mutex rather than an actor: `UpdateClock.now()` is a synchronous requirement, which an actor
/// cannot witness.
private final class StubUpdateClock: UpdateClock, @unchecked Sendable {
    private struct State {
        var current: Date
        var sleeps: [TimeInterval] = []
        var pendingSleeps: [CheckedContinuation<Void, Never>] = []
        /// Sleeps wait for the test. `remainingAutoSleeps` is how many sleeps still complete on
        /// their own before the clock blocks again; without a budget the schedule would free-run
        /// and a test could never observe one interval rather than thousands.
        var waitsForRelease = false
        var remainingAutoSleeps = 0
    }

    private let state: Mutex<State>

    init(now: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        state = Mutex(State(current: now))
    }

    var sleepIntervals: [TimeInterval] { state.withLock { $0.sleeps } }
    var sleepCount: Int { state.withLock { $0.sleeps.count } }

    /// Lets the next sleep wait for `finishSleeps()` instead of returning at once.
    func holdSleeps() {
        state.withLock { $0.waitsForRelease = true }
    }

    /// Completes the held sleep and lets the next `count` sleeps finish on their own before the
    /// clock blocks again, so a test can advance exactly as many intervals as it needs.
    ///
    /// The budget matters: without it the schedule would free-run and a test could only ever
    /// observe thousands of intervals instead of the one it arranged.
    func finishSleeps(thenAutoAdvance count: Int = 1) {
        let continuations: [CheckedContinuation<Void, Never>] = state.withLock { state in
            state.remainingAutoSleeps = count
            state.waitsForRelease = false
            let pending = state.pendingSleeps
            state.pendingSleeps.removeAll()
            return pending
        }
        for continuation in continuations {
            continuation.resume()
        }
    }

    func advance(by interval: TimeInterval) {
        state.withLock { $0.current = $0.current.addingTimeInterval(interval) }
    }

    func now() -> Date { state.withLock { $0.current } }

    func sleep(for interval: TimeInterval) async throws {
        try Task.checkCancellation()
        let shouldHold: Bool = state.withLock { state in
            state.sleeps.append(interval)
            if state.remainingAutoSleeps > 0 {
                state.remainingAutoSleeps -= 1
                return false
            }
            return state.waitsForRelease
        }
        if shouldHold {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let resumeNow: Bool = state.withLock { state in
                    if state.remainingAutoSleeps > 0 {
                        state.remainingAutoSleeps -= 1
                        return true
                    }
                    guard state.waitsForRelease else { return true }
                    state.pendingSleeps.append(continuation)
                    return false
                }
                if resumeNow { continuation.resume() }
            }
        }
        // A cancelled schedule must not continue into the next check, so cancellation is re-checked
        // once the sleep is over.
        try Task.checkCancellation()
        // The production clock really waits. Without this the schedule loop would spin as fast as
        // the thread allows, and a test could never observe one interval rather than thousands.
        try await Task.sleep(for: .milliseconds(1))
    }
}

final class UpdateModelTests: XCTestCase {
    /// A private defaults suite that is removed when the test finishes.
    @MainActor
    private func makeDefaults() -> UserDefaults {
        let suiteName = "UpdateModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    @MainActor
    private func makeRelease(_ tag: String, prerelease: Bool = false) -> ReleaseInfo {
        ReleaseInfo(
            tag: tag,
            version: SemanticVersion(string: tag),
            releasePageURL: URL(string: "https://github.com/Rowan-rh/PaneSpace/releases/tag/\(tag)")!,
            isPrerelease: prerelease,
            publishedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    @MainActor
    private func makeModel(
        feed: StubUpdateFeed,
        clock: StubUpdateClock = StubUpdateClock(),
        defaults: UserDefaults,
        currentVersion: SemanticVersion? = SemanticVersion(string: "0.1.0")
    ) -> UpdateModel {
        UpdateModel(feed: feed, clock: clock, defaults: defaults, currentVersion: currentVersion)
    }

    /// Waits for an asynchronous condition instead of guessing a fixed delay.
    @MainActor
    private func waitUntil(
        _ condition: @MainActor () async -> Bool,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while await !condition() {
            if Date() > deadline {
                XCTFail("Condition was not met within \(timeout) seconds.", file: file, line: line)
                return
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @MainActor
    private func settle() async {
        try? await Task.sleep(for: .milliseconds(60))
    }

    // MARK: Current version

    @MainActor
    func testDoesNotCheckWhenTheBuildHasNoVersion() async {
        let feed = StubUpdateFeed(fallback: .success(makeRelease("1.0.0")))
        let model = makeModel(feed: feed, defaults: makeDefaults(), currentVersion: nil)

        XCTAssertFalse(model.isSupported)
        model.start()

        let result = await model.checkNow()
        XCTAssertEqual(result, .failed(.invalidResponse))
        let requests = await feed.requestCount
        XCTAssertEqual(requests, 0, "A build with no version cannot be compared with anything.")
        XCTAssertNil(model.availableUpdate)
    }

    // MARK: Manual checks

    @MainActor
    func testManualCheckReportsAnAvailableUpdate() async {
        let release = makeRelease("0.2.0")
        let feed = StubUpdateFeed(fallback: .success(release))
        let model = makeModel(feed: feed, defaults: makeDefaults())

        let result = await model.checkNow()

        XCTAssertEqual(result, .available(release))
        XCTAssertEqual(model.availableUpdate?.tag, "0.2.0")
        XCTAssertFalse(model.isChecking)
        XCTAssertNotNil(model.lastCheckDate)
    }

    @MainActor
    func testManualCheckReportsUpToDate() async {
        let feed = StubUpdateFeed(fallback: .success(makeRelease("0.1.0")))
        let model = makeModel(feed: feed, defaults: makeDefaults())

        let result = await model.checkNow()

        XCTAssertEqual(result, .upToDate, "The same version is not an update.")
        XCTAssertNil(model.availableUpdate)
        XCTAssertEqual(model.lastManualResult, .upToDate)
    }

    @MainActor
    func testManualCheckFailsLoudlyWhenTheFeedIsRateLimited() async {
        let feed = StubUpdateFeed(fallback: .failure(.httpStatus(429)))
        let model = makeModel(feed: feed, defaults: makeDefaults())

        let result = await model.checkNow()

        XCTAssertEqual(result, .failed(.httpStatus(429)))
        XCTAssertEqual(model.lastManualResult, .failed(.httpStatus(429)))
        XCTAssertEqual(model.lastManualResult?.failure?.isRateLimited, true)
    }

    @MainActor
    func testManualCheckFailsLoudlyOnTransportDecodingAndServerFailures() async {
        let defaults = makeDefaults()
        for error in [UpdateFeedError.unreachable, .invalidResponse, .httpStatus(500), .httpStatus(403)] {
            let feed = StubUpdateFeed(fallback: .failure(error))
            let model = makeModel(feed: feed, defaults: defaults)

            let result = await model.checkNow()

            XCTAssertEqual(result, .failed(error), "\(error)")
        }
    }

    // MARK: Automatic checks

    @MainActor
    func testAutomaticFailureStaysOutOfTheManualState() async {
        let feed = StubUpdateFeed(fallback: .failure(.unreachable))
        let model = makeModel(feed: feed, defaults: makeDefaults())

        model.start()
        await waitUntil { model.lastAutomaticFailure != nil }

        XCTAssertNil(model.lastManualResult, "A scheduled check must not look like a manual result.")
        XCTAssertEqual(model.lastAutomaticFailure, .unreachable)
        XCTAssertNil(model.availableUpdate, "A failed check never shows a banner.")
        XCTAssertFalse(model.lastAutomaticFailure!.isRateLimited, "A transport failure is not a rate limit.")
    }

    @MainActor
    func testAutomaticFailureDoesNotClearABannerThatIsStillTrue() async {
        let feed = StubUpdateFeed()
        await feed.enqueue(.success(makeRelease("0.2.0")))
        await feed.enqueue(.failure(.unreachable))
        // Anything after the failing check blocks, so the banner state can be inspected as it was
        // when the failure arrived.
        await feed.holdRequests(after: 2)
        let clock = StubUpdateClock()
        clock.holdSleeps()
        let model = makeModel(feed: feed, clock: clock, defaults: makeDefaults())

        model.start()
        await waitUntil { model.availableUpdate?.tag == "0.2.0" }

        // The feed has one more answer queued, so the next scheduled check consumes the failure.
        clock.finishSleeps()

        await waitUntil { model.lastAutomaticFailure != nil }
        model.stop()

        XCTAssertEqual(
            model.availableUpdate?.tag,
            "0.2.0",
            "A transient failure must not hide a release that is still newer."
        )
    }

    // MARK: Scheduling

    @MainActor
    func testStartChecksImmediatelyThenWaitsADay() async {
        let feed = StubUpdateFeed(fallback: .success(nil))
        let clock = StubUpdateClock()
        clock.holdSleeps()
        let model = makeModel(feed: feed, clock: clock, defaults: makeDefaults())

        model.start()
        await waitUntil { clock.sleepCount > 0 }

        let requests = await feed.requestCount
        let intervals = clock.sleepIntervals
        XCTAssertEqual(requests, 1, "The first check runs at launch, not a day later.")
        XCTAssertEqual(intervals, [UpdateModel.checkInterval])
        XCTAssertEqual(UpdateModel.checkInterval, 24 * 60 * 60)
    }

    @MainActor
    func testChecksAgainAfterTheInterval() async {
        let feed = StubUpdateFeed(fallback: .success(nil))
        // The third request blocks, so the test can observe the second without the schedule running
        // past it.
        await feed.holdRequests(after: 2)
        let clock = StubUpdateClock()
        clock.holdSleeps()
        let model = makeModel(feed: feed, clock: clock, defaults: makeDefaults())

        model.start()
        await waitUntil { clock.sleepCount == 1 }
        clock.advance(by: UpdateModel.checkInterval)
        clock.finishSleeps()

        await waitUntil { await feed.requestCount >= 2 }
        model.stop()

        let requests = await feed.requestCount
        let intervals = clock.sleepIntervals
        XCTAssertGreaterThanOrEqual(requests, 2)
        XCTAssertEqual(
            Array(intervals.prefix(2)),
            [UpdateModel.checkInterval, UpdateModel.checkInterval],
            "The gap between checks is the configured interval."
        )
    }

    @MainActor
    func testDoesNotCheckMoreOftenThanTheInterval() async {
        let feed = StubUpdateFeed(fallback: .success(nil))
        let clock = StubUpdateClock()
        clock.holdSleeps()
        let model = makeModel(feed: feed, clock: clock, defaults: makeDefaults())

        model.start()
        await waitUntil { clock.sleepCount == 1 }
        // Time passes, but the sleep has not finished, so no second check may run.
        clock.advance(by: UpdateModel.checkInterval - 60)
        await settle()

        let requests = await feed.requestCount
        XCTAssertEqual(requests, 1)
    }

    @MainActor
    func testStartTwiceKeepsOneSchedule() async {
        let feed = StubUpdateFeed(fallback: .success(nil))
        let clock = StubUpdateClock()
        clock.holdSleeps()
        let model = makeModel(feed: feed, clock: clock, defaults: makeDefaults())

        model.start()
        model.start()
        model.start()
        await waitUntil { clock.sleepCount >= 1 }
        await settle()

        let requests = await feed.requestCount
        let sleeps = clock.sleepCount
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(sleeps, 1)
    }

    // MARK: Cancellation and preference changes

    @MainActor
    func testTurningAutomaticChecksOffCancelsTheSchedule() async {
        let feed = StubUpdateFeed(fallback: .success(nil))
        let clock = StubUpdateClock()
        clock.holdSleeps()
        let model = makeModel(feed: feed, clock: clock, defaults: makeDefaults())

        model.start()
        await waitUntil { clock.sleepCount == 1 }

        model.automaticallyChecks = false
        clock.finishSleeps(thenAutoAdvance: 0)
        clock.holdSleeps()
        await settle()

        let requests = await feed.requestCount
        XCTAssertEqual(requests, 1, "A cancelled schedule must not check again.")
    }

    @MainActor
    func testTurningAutomaticChecksOffCancelsACheckInFlight() async {
        let feed = StubUpdateFeed(fallback: .success(makeRelease("0.2.0")))
        await feed.holdRequests()
        let model = makeModel(feed: feed, defaults: makeDefaults())

        model.start()
        await waitUntil { await feed.requestCount == 1 }

        model.automaticallyChecks = false

        XCTAssertFalse(model.isChecking, "The pending check is cancelled, not left spinning.")
        XCTAssertNil(model.availableUpdate)
    }

    @MainActor
    func testACheckCancelledMidFlightNeverPublishesItsAnswer() async {
        let feed = StubUpdateFeed(fallback: .success(makeRelease("0.2.0")))
        await feed.holdRequests()
        let model = makeModel(feed: feed, defaults: makeDefaults())

        model.start()
        await waitUntil { await feed.requestCount == 1 }

        model.automaticallyChecks = false
        await feed.release()
        await settle()

        XCTAssertNil(model.availableUpdate, "A superseded check must not resurrect its result.")
    }

    @MainActor
    func testTurningAutomaticChecksBackOnRestartsTheSchedule() async {
        let feed = StubUpdateFeed(fallback: .success(nil))
        let clock = StubUpdateClock()
        clock.holdSleeps()
        let defaults = makeDefaults()
        let model = makeModel(feed: feed, clock: clock, defaults: defaults)

        defaults.set(false, forKey: UpdateModel.automaticallyChecksKey)
        model.start()
        await settle()
        var requests = await feed.requestCount
        XCTAssertEqual(requests, 0, "A schedule is not run while the switch is off.")

        model.automaticallyChecks = true
        await waitUntil { await feed.requestCount == 1 }
        requests = await feed.requestCount
        XCTAssertEqual(requests, 1)
    }

    @MainActor
    func testStopCancelsTheSchedule() async {
        let feed = StubUpdateFeed(fallback: .success(nil))
        let clock = StubUpdateClock()
        clock.holdSleeps()
        let model = makeModel(feed: feed, clock: clock, defaults: makeDefaults())

        model.start()
        await waitUntil { clock.sleepCount == 1 }

        model.stop()
        clock.finishSleeps(thenAutoAdvance: 0)
        clock.holdSleeps()
        await settle()

        let requests = await feed.requestCount
        XCTAssertEqual(requests, 1)
    }

    @MainActor
    func testRepeatedManualChecksKeepOnlyTheLastAnswer() async {
        let feed = StubUpdateFeed()
        await feed.enqueue(.success(makeRelease("0.2.0")))
        await feed.enqueue(.success(nil))
        let model = makeModel(feed: feed, defaults: makeDefaults())

        _ = await model.checkNow()
        let second = await model.checkNow()

        XCTAssertEqual(second, .upToDate)
        let requests = await feed.requestCount
        XCTAssertEqual(requests, 2)
        XCTAssertNil(model.availableUpdate, "The newest answer wins even when it is 'nothing new'.")
    }

    // MARK: Channels

    @MainActor
    func testPrereleaseChannelIsPassedToTheFeed() async {
        let feed = StubUpdateFeed(fallback: .success(nil))
        let model = makeModel(feed: feed, defaults: makeDefaults())

        _ = await model.checkNow()
        model.includesPrereleases = true
        _ = await model.checkNow()

        let flags = await feed.prereleaseFlags
        XCTAssertEqual(flags, [false, true])
    }

    @MainActor
    func testChangingTheChannelDropsTheStaleAnswer() async {
        let feed = StubUpdateFeed(fallback: .success(makeRelease("0.3.0-beta.1", prerelease: true)))
        let model = makeModel(feed: feed, defaults: makeDefaults())

        model.includesPrereleases = true
        _ = await model.checkNow()
        XCTAssertEqual(model.availableUpdate?.tag, "0.3.0-beta.1")

        model.includesPrereleases = false

        XCTAssertNil(model.availableUpdate, "A beta answer must not survive turning the channel off.")
        XCTAssertNil(model.lastManualResult)
    }

    @MainActor
    func testChangingTheChannelRechecksImmediately() async {
        let feed = StubUpdateFeed(fallback: .success(makeRelease("0.2.0")))
        let clock = StubUpdateClock()
        clock.holdSleeps()
        let model = makeModel(feed: feed, clock: clock, defaults: makeDefaults())
        model.start()
        await waitUntil { clock.sleepCount == 1 }

        model.includesPrereleases = true

        await waitUntil { await feed.requestCount == 2 }
        let flags = await feed.prereleaseFlags
        XCTAssertEqual(flags, [false, true], "A new channel has a different answer, so it is re-asked.")
    }

    @MainActor
    func testBetaChannelOffersAPrerelease() async {
        let release = makeRelease("0.3.0-beta.1", prerelease: true)
        let feed = StubUpdateFeed(fallback: .success(release))
        let model = makeModel(feed: feed, defaults: makeDefaults())

        model.includesPrereleases = true
        let result = await model.checkNow()

        XCTAssertEqual(result, .available(release))
    }

    // MARK: Superseded checks

    /// A check that is replaced by a newer one must not clear the newer check's `isChecking` when it
    /// returns. The scenario is ordinary: the launch-time automatic check is still running when the
    /// user clicks "Check Now".
    @MainActor
    func testASupersededCheckDoesNotClearTheNewerChecksCheckingState() async {
        let feed = StubUpdateFeed()
        await feed.enqueue(.success(makeRelease("0.2.0")))
        await feed.enqueue(.success(makeRelease("0.3.0")))
        // Both requests are held, so each check is still in flight when the next one replaces it.
        await feed.holdRequests()
        let clock = StubUpdateClock()
        clock.holdSleeps()
        let model = makeModel(feed: feed, clock: clock, defaults: makeDefaults())

        model.start()
        await waitUntil { await feed.requestCount == 1 }
        let manual = Task { await model.checkNow() }
        await waitUntil { await feed.requestCount == 2 }

        // Answer only the superseded request. The manual check that replaced it is still waiting, so
        // the model is genuinely still checking when the superseded one returns.
        await feed.releaseOne()
        await settle()

        XCTAssertTrue(
            model.isChecking,
            "A superseded check must not report the model as no longer checking while a newer one runs."
        )

        await feed.release()
        let result = await manual.value
        model.stop()

        XCTAssertEqual(result, .available(makeRelease("0.3.0")))
        XCTAssertFalse(model.isChecking, "Once nothing is running, the model says so.")
    }

    /// A channel switch while a manual check is in flight. The manual check describes the old
    /// channel, so it is replaced by the recheck for the new one — and its caller is told so rather
    /// than being handed an answer computed against preferences that no longer hold.
    @MainActor
    func testAManualCheckSupersededByAChannelSwitchIsToldItWasCancelled() async {
        let feed = StubUpdateFeed()
        await feed.enqueue(.success(makeRelease("0.2.0")))
        await feed.enqueue(.success(nil))
        await feed.holdRequests()
        let clock = StubUpdateClock()
        clock.holdSleeps()
        let model = makeModel(feed: feed, clock: clock, defaults: makeDefaults())

        model.start()
        await waitUntil { await feed.requestCount == 1 }
        let manual = Task { await model.checkNow() }
        await waitUntil { await feed.requestCount == 2 }

        // Switching the channel replaces both running checks with one recheck for the new channel.
        model.includesPrereleases = true
        // Cancelling does not unblock a request the feed is still holding, so the replaced checks
        // are answered before their callers can resume.
        await feed.release()
        let manualResult = await manual.value

        XCTAssertEqual(manualResult, .failed(.cancelled), "The caller is told its check was replaced.")
        XCTAssertNil(model.lastManualResult, "A cancelled manual check publishes nothing.")

        let requests = await feed.requestCount
        XCTAssertEqual(requests, 3, "The new channel is asked once, for everyone.")

        await feed.stopHolding()
        model.stop()
    }

    /// A cancelled manual check must report the cancellation, not hand the caller the previous
    /// result. Returning a stale answer is how a UI ends up telling the user "you are up to date"
    /// about a check that never ran.
    @MainActor
    func testACancelledManualCheckReportsCancelledRatherThanTheLastResult() async {
        let feed = StubUpdateFeed()
        await feed.enqueue(.success(makeRelease("0.2.0")))
        await feed.enqueue(.success(makeRelease("0.3.0")))
        await feed.enqueue(.success(makeRelease("0.4.0")))
        // The first check answers immediately; the ones after it wait, so each is genuinely in
        // flight when the next replaces it.
        await feed.holdRequests(after: 1)
        let model = makeModel(feed: feed, defaults: makeDefaults())

        let first = await model.checkNow()
        XCTAssertEqual(first, .available(makeRelease("0.2.0")))

        let second = Task { await model.checkNow() }
        await waitUntil { await feed.requestCount == 2 }
        // A third check replaces the second, which is the ordinary "user clicks Check Now twice"
        // path. The second check is still waiting on the feed, so it is genuinely in flight.
        let third = Task { await model.checkNow() }
        await waitUntil { await feed.requestCount == 3 }

        // Answer only the superseded request. It resumes as cancelled, and the check that replaced
        // it is still running, so `isChecking` must still be true.
        await feed.releaseOne()
        let result = await second.value

        XCTAssertEqual(
            result,
            .failed(.cancelled),
            "A cancelled check has no answer, and the previous one is not it."
        )
        XCTAssertTrue(model.isChecking, "The check that replaced it is still running.")
        XCTAssertEqual(
            model.lastManualResult,
            .available(makeRelease("0.2.0")),
            "Cancelling must not rewrite the state the completed check already published."
        )

        await feed.release()
        let final = await third.value
        XCTAssertEqual(final, .available(makeRelease("0.4.0")))
        XCTAssertEqual(model.lastManualResult, .available(makeRelease("0.4.0")))
    }

    /// After a cancellation, the model is usable again: a later check still runs and publishes.
    @MainActor
    func testACheckAfterACancellationStillRuns() async {
        let feed = StubUpdateFeed()
        await feed.enqueue(.success(makeRelease("0.2.0")))
        await feed.enqueue(.success(makeRelease("0.3.0")))
        // The cancelled check waits so it is really in flight; the next one answers at once.
        await feed.holdRequests(after: 0)
        let model = makeModel(feed: feed, defaults: makeDefaults())

        let cancelled = Task { await model.checkNow() }
        await waitUntil { await feed.requestCount == 1 }
        model.stop()
        await feed.release()
        let cancelledResult = await cancelled.value
        XCTAssertEqual(cancelledResult, .failed(.cancelled))
        XCTAssertFalse(model.isChecking, "A stopped model is not checking.")

        await feed.stopHolding()
        await feed.enqueue(.success(makeRelease("0.3.0")))
        let result = await model.checkNow()

        XCTAssertEqual(result, .available(makeRelease("0.3.0")), "The model is still usable.")
    }

    // MARK: Preferences written outside the model

    /// The Settings window binds `betaUpdates` with `@AppStorage`, which writes `UserDefaults`
    /// directly and never reaches a computed setter. The model observes the store, so the response
    /// is the same however the preference was written.
    @MainActor
    func testWritingTheBetaPreferenceDirectlyRechecksAndDropsTheOldChannelsAnswer() async {
        let feed = StubUpdateFeed()
        // The first answer is for the old channel; the recheck after the switch finds nothing.
        await feed.enqueue(.success(makeRelease("0.2.0")))
        await feed.enqueue(.success(nil))
        await feed.holdRequests()
        let defaults = makeDefaults()
        let model = makeModel(feed: feed, defaults: defaults)

        model.start()
        await waitUntil { await feed.requestCount == 1 }

        // Written the way `@AppStorage` writes it: no setter, no model involvement.
        defaults.set(true, forKey: UpdateModel.includesPrereleasesKey)
        // The new channel has a different answer, so it is re-asked rather than left to the day.
        await waitUntil { await feed.requestCount == 2 }

        let flags = await feed.prereleaseFlags
        XCTAssertEqual(flags, [false, true], "The recheck asks the channel that is now selected.")

        // Both requests now answer. The superseded one carries a release, but it belongs to the old
        // channel and must not become a banner.
        await feed.release()
        await waitUntil { !model.isChecking }

        XCTAssertTrue(model.includesPrereleases, "The model follows the store, not just its own setter.")
        XCTAssertNil(
            model.availableUpdate,
            "An answer for the previous channel must not become a banner on the new one."
        )
        XCTAssertEqual(model.lastAutomaticFailure, nil)
        model.stop()
    }

    @MainActor
    func testWritingTheAutomaticChecksPreferenceDirectlyRestopsTheSchedule() async {
        let feed = StubUpdateFeed(fallback: .success(nil))
        let clock = StubUpdateClock()
        clock.holdSleeps()
        let defaults = makeDefaults()
        let model = makeModel(feed: feed, clock: clock, defaults: defaults)

        defaults.set(false, forKey: UpdateModel.automaticallyChecksKey)
        model.start()
        await settle()
        var requests = await feed.requestCount
        XCTAssertEqual(requests, 0, "The schedule reads the switch before its first check.")

        defaults.set(true, forKey: UpdateModel.automaticallyChecksKey)
        await waitUntil { await feed.requestCount == 1 }
        model.stop()

        requests = await feed.requestCount
        XCTAssertEqual(requests, 1, "Turning the switch back on restarts the schedule.")
        XCTAssertTrue(model.automaticallyChecks, "The published value tracks the store.")
    }

    @MainActor
    func testWritingTheAutomaticChecksPreferenceDirectlyCancelsACheckInFlight() async {
        let feed = StubUpdateFeed(fallback: .success(makeRelease("0.2.0")))
        await feed.holdRequests()
        let defaults = makeDefaults()
        let model = makeModel(feed: feed, defaults: defaults)

        model.start()
        await waitUntil { await feed.requestCount == 1 }

        defaults.set(false, forKey: UpdateModel.automaticallyChecksKey)
        await waitUntil { !model.automaticallyChecks }

        XCTAssertFalse(model.isChecking, "Switching off must stop work already in flight.")
        await feed.release()
        await settle()
        XCTAssertNil(model.availableUpdate)
    }

    @MainActor
    func testWritingTheSkippedVersionPreferenceDirectlyIsObserved() async {
        let defaults = makeDefaults()
        let model = makeModel(feed: StubUpdateFeed(), defaults: defaults)

        defaults.set("0.2.0", forKey: UpdateModel.skippedVersionKey)
        await waitUntil { model.skippedVersion == "0.2.0" }

        XCTAssertEqual(model.skippedVersion, "0.2.0")
    }

    /// The Settings window binds `betaUpdates`; a banner offered for a release the user has already
    /// skipped must disappear even though the skip happened outside the model.
    @MainActor
    func testSkippingThroughPreferencesHidesTheBannerOnTheNextCheck() async {
        let release = makeRelease("0.2.0")
        let feed = StubUpdateFeed(fallback: .success(release))
        let defaults = makeDefaults()
        let model = makeModel(feed: feed, defaults: defaults)

        _ = await model.checkNow()
        XCTAssertEqual(model.availableUpdate?.tag, "0.2.0")

        defaults.set("0.2.0", forKey: UpdateModel.skippedVersionKey)
        await waitUntil { model.skippedVersion == "0.2.0" }

        let result = await model.checkNow()
        XCTAssertEqual(result, .upToDate, "A version skipped in preferences is not offered again.")
        XCTAssertNil(model.availableUpdate)
    }

    /// An unrelated write must not be mistaken for one of the model's own preferences. The store
    /// posts a single notification for any change, so only a real difference may trigger a response.
    @MainActor
    func testAnUnrelatedPreferenceWriteDoesNotDisturbTheModel() async {
        let feed = StubUpdateFeed(fallback: .success(nil))
        let clock = StubUpdateClock()
        clock.holdSleeps()
        let defaults = makeDefaults()
        let model = makeModel(feed: feed, clock: clock, defaults: defaults)

        model.start()
        await waitUntil { clock.sleepCount == 1 }
        let sleepsBefore = clock.sleepCount
        let checksBefore = model.isChecking

        defaults.set("something else", forKey: "unrelatedPaneSpaceKey")
        await settle()

        XCTAssertEqual(clock.sleepCount, sleepsBefore, "An unrelated write must not reschedule.")
        XCTAssertEqual(model.isChecking, checksBefore)
        XCTAssertTrue(model.automaticallyChecks)
        XCTAssertFalse(model.includesPrereleases)
        model.stop()
    }

    /// The model is the thing a Settings toggle binds to, so a change to it has to reach observers.
    /// `automaticallyChecks` and `includesPrereleases` were computed properties, which publish
    /// nothing; a `Binding` over them would have shown a stale Toggle.
    @MainActor
    func testPreferencePropertiesPublishTheirChangesToObservers() async {
        let defaults = makeDefaults()
        let model = makeModel(feed: StubUpdateFeed(), defaults: defaults)
        let recorder = ObjectWillChangeRecorder()
        let subscription = model.objectWillChange.sink { _ in recorder.record() }
        defer { subscription.cancel() }

        // Counted separately per change: each one may legitimately publish more than once, because
        // responding to a preference moves other published state too. What matters is that a bound
        // Toggle is told at all — a computed property told it zero times.
        let before = recorder.count
        model.automaticallyChecks = false
        let afterAutomatic = recorder.count
        model.includesPrereleases = true
        let afterPrereleases = recorder.count

        XCTAssertGreaterThan(afterAutomatic, before, "A bound Toggle has to be told the value moved.")
        XCTAssertGreaterThan(afterPrereleases, afterAutomatic)

        // `@Published` announces before `didSet` can compare, so writing the same value still
        // publishes. That is harmless — a view re-reading the value sees no change — and the
        // important half is the one above: the change is announced at all, which a computed
        // property never did.
    }

    // MARK: Skipping

    @MainActor
    func testSkippingAVersionHidesIt() async {
        let defaults = makeDefaults()
        let feed = StubUpdateFeed(fallback: .success(makeRelease("0.2.0")))
        let model = makeModel(feed: feed, defaults: defaults)

        _ = await model.checkNow()
        XCTAssertEqual(model.availableUpdate?.tag, "0.2.0")

        model.skip(version: "0.2.0")

        XCTAssertNil(model.availableUpdate)
        XCTAssertEqual(defaults.string(forKey: UpdateModel.skippedVersionKey), "0.2.0")
    }

    @MainActor
    func testSkippedVersionIsNotOfferedAgain() async {
        let feed = StubUpdateFeed(fallback: .success(makeRelease("0.2.0")))
        let model = makeModel(feed: feed, defaults: makeDefaults())
        model.skip(version: "0.2.0")

        let result = await model.checkNow()

        XCTAssertEqual(result, .upToDate)
        XCTAssertNil(model.availableUpdate)
    }

    @MainActor
    func testAHigherVersionIsStillOfferedAfterSkipping() async {
        let defaults = makeDefaults()
        defaults.set("0.2.0", forKey: UpdateModel.skippedVersionKey)
        let feed = StubUpdateFeed()
        let model = makeModel(feed: feed, defaults: defaults)

        await feed.enqueue(.success(makeRelease("0.2.0")))
        let skipped = await model.checkNow()
        XCTAssertEqual(skipped, .upToDate)

        let higher = makeRelease("0.3.0")
        await feed.enqueue(.success(higher))
        let offered = await model.checkNow()
        XCTAssertEqual(offered, .available(higher), "Skipping one version must not mute the channel.")
    }

    @MainActor
    func testSkippedVersionIsRestoredFromPreferences() {
        let defaults = makeDefaults()
        defaults.set("0.2.0", forKey: UpdateModel.skippedVersionKey)
        let model = makeModel(feed: StubUpdateFeed(), defaults: defaults)

        XCTAssertEqual(model.skippedVersion, "0.2.0")
    }

    @MainActor
    func testDismissingHidesTheBannerWithoutSkipping() async {
        let defaults = makeDefaults()
        let release = makeRelease("0.2.0")
        let feed = StubUpdateFeed(fallback: .success(release))
        let model = makeModel(feed: feed, defaults: defaults)

        _ = await model.checkNow()
        model.dismiss()

        XCTAssertNil(model.availableUpdate)
        XCTAssertNil(model.skippedVersion, "Dismissing is temporary, not a decision to ignore a version.")
        XCTAssertNil(defaults.string(forKey: UpdateModel.skippedVersionKey))

        let result = await model.checkNow()
        XCTAssertEqual(result, .available(release), "The next check may show it again.")
    }

    // MARK: Preferences

    @MainActor
    func testAutomaticChecksDefaultToOn() {
        let model = makeModel(feed: StubUpdateFeed(), defaults: makeDefaults())
        XCTAssertTrue(model.automaticallyChecks)
    }

    @MainActor
    func testAutomaticChecksPreferenceIsPersisted() {
        let defaults = makeDefaults()
        let model = makeModel(feed: StubUpdateFeed(), defaults: defaults)

        model.automaticallyChecks = false

        XCTAssertFalse(defaults.bool(forKey: UpdateModel.automaticallyChecksKey))
        let reopened = makeModel(feed: StubUpdateFeed(), defaults: defaults)
        XCTAssertFalse(reopened.automaticallyChecks)
    }

    @MainActor
    func testBetaPreferenceSharesTheExistingSettingsKey() {
        let defaults = makeDefaults()
        let model = makeModel(feed: StubUpdateFeed(), defaults: defaults)

        model.includesPrereleases = true

        XCTAssertTrue(defaults.bool(forKey: "betaUpdates"), "Settings binds this key with @AppStorage.")
        XCTAssertEqual(UpdateModel.includesPrereleasesKey, "betaUpdates")
    }

    @MainActor
    func testEveryUpdateKeyIsResettable() {
        for key in [UpdateModel.automaticallyChecksKey, UpdateModel.includesPrereleasesKey, UpdateModel.skippedVersionKey] {
            XCTAssertTrue(PaneSpacePreferences.allKeys.contains(key), key)
        }
    }
}