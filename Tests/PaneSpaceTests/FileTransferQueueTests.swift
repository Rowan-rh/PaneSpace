import Foundation
import XCTest
@testable import PaneSpaceApp

final class FileTransferQueueTests: XCTestCase {
    @MainActor
    func testConflictPausesThenApplyToAllCompletesBatchInOrder() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent("Destination", isDirectory: true)
        let trash = root.appendingPathComponent("Trash", isDirectory: true)
        for directory in [source, destination, trash] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let names = ["one.txt", "two.txt"]
        for name in names {
            try Data("new".utf8).write(to: source.appendingPathComponent(name))
            try Data("old".utf8).write(to: destination.appendingPathComponent(name))
        }
        let service = LocalTransferService(trashItem: { url in
            let trashed = trash.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: trashed)
            return trashed
        })
        let queue = FileTransferQueueModel(service: service)
        queue.enqueue(kind: .copy, sources: names.map { source.appendingPathComponent($0) }, destinationDirectory: destination)

        try await waitUntil { queue.conflict != nil }
        XCTAssertEqual(queue.jobs[0].state, .waitingForDecision)
        queue.resolveConflict(.replace, applyToAll: true)
        try await waitUntil { queue.jobs[0].state == .completed }

        XCTAssertEqual(queue.jobs[0].completedCount, 2)
        XCTAssertNil(queue.conflict)
        for name in names {
            XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent(name), encoding: .utf8), "new")
            XCTAssertEqual(try String(contentsOf: trash.appendingPathComponent(name), encoding: .utf8), "old")
        }
    }

    @MainActor
    func testCancellationWhileWaitingPreventsTransferAndCanRetry() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.txt")
        let destination = root.appendingPathComponent("Destination", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("new".utf8).write(to: source)
        let existing = destination.appendingPathComponent("source.txt")
        try Data("old".utf8).write(to: existing)
        let queue = FileTransferQueueModel()
        queue.enqueue(kind: .copy, sources: [source], destinationDirectory: destination)

        try await waitUntil { queue.conflict != nil }
        let jobID = queue.jobs[0].id
        queue.cancel(jobID)
        try await waitUntil { queue.jobs[0].state == .cancelled }
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "old")

        queue.retry(jobID)
        try await waitUntil { queue.conflict != nil }
        queue.resolveConflict(.skip, applyToAll: false)
        try await waitUntil { queue.jobs[0].state == .completed }
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "old")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    @MainActor
    func testRetryAfterMoveSourceRemovalFailureDoesNotCopyAgain() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.txt")
        let destination = root.appendingPathComponent("Destination", isDirectory: true)
        let trash = root.appendingPathComponent("Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try Data("content".utf8).write(to: source)
        let attempts = AttemptCounter()
        let service = LocalTransferService(trashItem: { url in
            if attempts.shouldFail() { throw CocoaError(.fileWriteNoPermission) }
            let trashed = trash.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: trashed)
            return trashed
        })
        let queue = FileTransferQueueModel(service: service)
        queue.enqueue(kind: .move, sources: [source], destinationDirectory: destination)

        try await waitUntil { queue.jobs[0].state == .failed }
        XCTAssertTrue(queue.jobs[0].items[0].needsSourceRemoval)
        let copied = destination.appendingPathComponent("source.txt")
        XCTAssertEqual(try String(contentsOf: copied, encoding: .utf8), "content")

        queue.retry(queue.jobs[0].id)
        try await waitUntil { queue.jobs[0].state == .completed }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path), ["source.txt"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try String(contentsOf: trash.appendingPathComponent("source.txt"), encoding: .utf8), "content")
    }

    @MainActor
    func testCompletedJobReportsAllMeasuredBytes() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("Destination", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let first = root.appendingPathComponent("first.bin")
        let second = root.appendingPathComponent("second.bin")
        try Data(count: 2_000).write(to: first)
        try Data(count: 3_000).write(to: second)
        let queue = FileTransferQueueModel()
        queue.enqueue(kind: .copy, sources: [first, second], destinationDirectory: destination)

        try await waitUntil { queue.jobs[0].state == .completed }
        XCTAssertEqual(queue.jobs[0].totalBytes, 5_000)
        XCTAssertEqual(queue.jobs[0].completedBytes, 5_000)
        XCTAssertEqual(queue.jobs[0].fractionCompleted, 1)
    }

    @MainActor
    func testCopyIntoSourceFolderDuplicatesWithoutAskingForDecision() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("photo.jpg")
        try Data("image".utf8).write(to: source)
        let queue = FileTransferQueueModel()

        queue.enqueue(kind: .copy, sources: [source], destinationDirectory: root)
        try await waitUntil { queue.jobs[0].state == .completed || queue.jobs[0].state == .failed }

        XCTAssertEqual(queue.jobs[0].state, .completed)
        XCTAssertNil(queue.conflict)
        XCTAssertEqual(queue.jobs[0].items[0].destination?.lastPathComponent, "photo copy 2.jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for transfer state")
    }
}

private final class AttemptCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var attempts = 0

    func shouldFail() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        attempts += 1
        return attempts == 1
    }
}
