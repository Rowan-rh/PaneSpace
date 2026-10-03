import Foundation

/// The time source the update schedule is measured against.
///
/// Injected so the 24-hour interval can be tested without waiting a day, and so tests can advance
/// time instead of sleeping.
protocol UpdateClock: Sendable {
    func now() -> Date
    /// Suspends for `interval`, or throws `CancellationError` if the calling task is cancelled.
    /// Interrupting an early wait is done by cancelling the task, not by polling.
    func sleep(for interval: TimeInterval) async throws
}

/// The production clock: the system time and `Task.sleep`.
struct SystemUpdateClock: UpdateClock {
    func now() -> Date { Date() }

    func sleep(for interval: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(interval))
    }
}
