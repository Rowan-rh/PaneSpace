import AppKit
import Foundation
import XCTest
@testable import PaneSpaceApp

final class FilePasteboardTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @MainActor
    func testWritesFileURLsThatReadBackAndIgnoresPlainText() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let filePasteboard = FilePasteboard(pasteboard: pasteboard)
        let first = root.appendingPathComponent("one.txt")
        let second = root.appendingPathComponent("two.txt")
        for url in [first, second] {
            try Data("x".utf8).write(to: url)
        }

        filePasteboard.write([first, second])
        XCTAssertEqual(filePasteboard.fileURLs().map(\.standardizedFileURL), [first, second].map(\.standardizedFileURL))

        pasteboard.clearContents()
        pasteboard.setString(first.path, forType: .string)
        XCTAssertEqual(filePasteboard.fileURLs(), [])
    }

    func testCopyIntoOwnFolderDuplicatesEvenWhenAskedToReplace() async throws {
        let source = root.appendingPathComponent("report.txt")
        try Data("original".utf8).write(to: source)
        let service = LocalTransferService(trashItem: { _ in
            XCTFail("A duplicate must never trash anything")
            return nil
        })

        let outcome = try await service.transfer(source: source, to: root, kind: .copy, conflictDecision: .replace)

        let destination = try XCTUnwrap(outcome?.destination)
        XCTAssertNotEqual(destination.standardizedFileURL, source.standardizedFileURL)
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "original")
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "original")
    }

    func testMoveIntoOwnFolderIsStillRejected() async throws {
        let source = root.appendingPathComponent("report.txt")
        try Data("original".utf8).write(to: source)

        do {
            _ = try await LocalTransferService().transfer(source: source, to: root, kind: .move, conflictDecision: .keepBoth)
            XCTFail("Expected invalid destination")
        } catch LocalTransferError.invalidDestination {
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["report.txt"])
        }
    }

    @MainActor
    func testQueueDuplicatesInOwnFolderWithoutAskingAboutConflict() async throws {
        let source = root.appendingPathComponent("report.txt")
        try Data("original".utf8).write(to: source)
        let queue = FileTransferQueueModel()

        queue.enqueue(kind: .copy, sources: [source], destinationDirectory: root)
        for _ in 0..<100 where queue.jobs[0].state != .completed {
            XCTAssertNil(queue.conflict)
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertEqual(queue.jobs[0].state, .completed)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 2)
    }

    @MainActor
    func testAppModelCopiesSelectionAndPastesIntoPaneFolder() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let model = AppModel(defaults: defaults, filePasteboard: FilePasteboard(pasteboard: pasteboard))
        let copied = root.appendingPathComponent("copied.txt")
        try Data("x".utf8).write(to: copied)

        XCTAssertFalse(model.copySelectionToPasteboard(from: .primary))
        XCTAssertNil(pasteboard.string(forType: .fileURL))
        XCTAssertFalse(model.pasteFromPasteboard(into: .secondary))

        pasteboard.clearContents()
        pasteboard.writeObjects([copied as NSURL])
        XCTAssertTrue(model.pasteFromPasteboard(into: .secondary))

        let job = try XCTUnwrap(model.transferQueue.jobs.first)
        XCTAssertEqual(job.kind, .copy)
        XCTAssertEqual(job.items.map(\.source.standardizedFileURL), [copied.standardizedFileURL])
        XCTAssertEqual(job.destinationDirectory, model.secondaryPane.transferDestinationURL)
        model.transferQueue.cancel(job.id)
    }
}
