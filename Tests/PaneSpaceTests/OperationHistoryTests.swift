import Foundation
import XCTest
@testable import PaneSpaceApp

final class OperationHistoryTests: XCTestCase {
    private func makeStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("OperationHistory.json")
    }

    private func sampleRecord(kind: OperationKind = .copy) -> OperationRecord {
        let folder = URL(fileURLWithPath: "/history", isDirectory: true)
        return OperationRecord(
            kind: kind,
            outcome: .completed,
            directory: folder,
            items: [OperationRecordItem(original: folder.appendingPathComponent("a"), result: folder.appendingPathComponent("b"))],
            requestedCount: 1
        )
    }

    func testStoreRoundTripsAndIgnoresUnreadableFiles() async throws {
        let url = makeStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = OperationHistoryStore(fileURL: url)
        let empty = await store.load()
        XCTAssertEqual(empty, [])

        let record = sampleRecord()
        try await store.save([record])
        let loaded = await store.load()
        XCTAssertEqual(loaded, [record])

        try Data("not json".utf8).write(to: url)
        let corrupted = await store.load()
        XCTAssertEqual(corrupted, [])
    }

    @MainActor
    func testModelPersistsNewestFirstAndCapsLength() async throws {
        let url = makeStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let model = OperationHistoryModel(store: OperationHistoryStore(fileURL: url))
        try await waitForPane { model.isLoaded }

        for _ in 0 ..< OperationHistoryModel.maximumRecords + 5 {
            model.record(sampleRecord())
        }
        let newest = sampleRecord(kind: .trash)
        model.record(newest)
        XCTAssertEqual(model.records.count, OperationHistoryModel.maximumRecords)
        XCTAssertEqual(model.records.first, newest)
        await model.flush()

        let reloaded = OperationHistoryModel(store: OperationHistoryStore(fileURL: url))
        try await waitForPane { reloaded.isLoaded }
        XCTAssertEqual(reloaded.records.count, OperationHistoryModel.maximumRecords)
        XCTAssertEqual(reloaded.records.first, newest)

        reloaded.clear()
        await reloaded.flush()
        let cleared = await OperationHistoryStore(fileURL: url).load()
        XCTAssertEqual(cleared, [])
    }

    @MainActor
    func testQueueReportsEachRunOnceWithTrashLocations() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("Destination", isDirectory: true)
        let trash = root.appendingPathComponent("Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("moved.txt")
        try Data("content".utf8).write(to: source)
        let service = LocalTransferService(trashItem: { url in
            let trashed = trash.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: trashed)
            return trashed
        })
        let queue = FileTransferQueueModel(service: service)
        var reported: [FileTransferJob] = []
        queue.didFinishJob = { reported.append($0) }

        queue.enqueue(kind: .move, sources: [source], destinationDirectory: destination)
        try await waitForPane { reported.count == 1 }
        let item = try XCTUnwrap(reported.first?.items.first)
        XCTAssertEqual(item.destination?.lastPathComponent, "moved.txt")
        XCTAssertEqual(item.sourceInTrash, trash.appendingPathComponent("moved.txt"))
    }

    @MainActor
    func testPaneRecordsTrashAndRenameOperations() async throws {
        let root = URL(fileURLWithPath: "/recorded", isDirectory: true)
        let file = FileItem.stub("a.txt", in: root)
        let provider = StaticDirectoryProvider([root: [file]])
        let model = BrowserPaneModel(url: root, provider: provider)
        try await waitForPane { !model.isLoading && model.items.count == 1 }
        var records: [OperationRecord] = []
        model.didRecordOperation = { records.append($0) }

        model.trash([file])
        try await waitForPane { !model.isPerformingOperation && records.count == 1 }
        XCTAssertEqual(records[0].kind, .trash)
        XCTAssertEqual(records[0].outcome, .completed)
        XCTAssertEqual(records[0].items.map(\.original), [file.url])
    }
}
