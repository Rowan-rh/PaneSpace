import Foundation
import XCTest
@testable import PaneSpaceApp

final class OperationUndoTests: XCTestCase {
    private var root: URL!
    private var trash: URL!
    private var folder: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        trash = root.appendingPathComponent("Trash", isDirectory: true)
        folder = root.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeService() -> OperationUndoService {
        let trash = trash!
        return OperationUndoService(trashItem: { url in
            let destination = trash.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        })
    }

    private func write(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url)
    }

    private func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func names(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    private func record(_ kind: OperationKind, _ items: [OperationRecordItem]) -> OperationRecord {
        OperationRecord(kind: kind, outcome: .completed, directory: folder, items: items, requestedCount: items.count)
    }

    func testUndoRenameRestoresSwappedAndCaseChangedNames() async throws {
        try write("A", to: folder.appendingPathComponent("b.txt"))
        try write("B", to: folder.appendingPathComponent("a.txt"))
        try write("C", to: folder.appendingPathComponent("case.txt"))
        let undo = record(.rename, [
            OperationRecordItem(original: folder.appendingPathComponent("a.txt"), result: folder.appendingPathComponent("b.txt")),
            OperationRecordItem(original: folder.appendingPathComponent("b.txt"), result: folder.appendingPathComponent("a.txt")),
            OperationRecordItem(original: folder.appendingPathComponent("Case.txt"), result: folder.appendingPathComponent("case.txt"))
        ])

        _ = try await makeService().undo(undo)

        XCTAssertEqual(try names(in: folder), ["Case.txt", "a.txt", "b.txt"])
        XCTAssertEqual(try read(folder.appendingPathComponent("a.txt")), "A")
    }

    func testUndoRenameRefusesWhenOriginalNameIsTakenByAnotherItem() async throws {
        try write("new", to: folder.appendingPathComponent("new.txt"))
        try write("intruder", to: folder.appendingPathComponent("old.txt"))
        let undo = record(.rename, [
            OperationRecordItem(original: folder.appendingPathComponent("old.txt"), result: folder.appendingPathComponent("new.txt"))
        ])

        do {
            _ = try await makeService().undo(undo)
            XCTFail("Expected the taken name to stop the undo")
        } catch let error as OperationUndoService.UndoError {
            XCTAssertEqual(error, .originalLocationTaken(name: "old.txt"))
        }
        XCTAssertEqual(try read(folder.appendingPathComponent("old.txt")), "intruder")
    }

    func testUndoTrashPutsItemBack() async throws {
        let trashed = trash.appendingPathComponent("note.txt")
        try write("note", to: trashed)
        let original = folder.appendingPathComponent("note.txt")

        let changed = try await makeService().undo(record(.trash, [OperationRecordItem(original: original, trashed: trashed)]))

        XCTAssertEqual(try read(original), "note")
        XCTAssertEqual(changed, [folder.standardizedFileURL])
    }

    func testUndoCopyTrashesCopyAndRestoresReplacedItem() async throws {
        let copy = folder.appendingPathComponent("report.txt")
        try write("new", to: copy)
        let replaced = trash.appendingPathComponent("report.txt")
        try write("old", to: replaced)

        _ = try await makeService().undo(record(.copy, [
            OperationRecordItem(original: root.appendingPathComponent("report.txt"), result: copy, replacedInTrash: replaced)
        ]))

        XCTAssertEqual(try read(copy), "old")
        XCTAssertFalse(FileManager.default.fileExists(atPath: replaced.path))
    }

    func testUndoMoveRestoresTrashedSourceAndRetiresCopy() async throws {
        let original = root.appendingPathComponent("moved.txt")
        let result = folder.appendingPathComponent("moved.txt")
        let trashedSource = trash.appendingPathComponent("moved.txt")
        try write("copy", to: result)
        try write("source", to: trashedSource)

        _ = try await makeService().undo(record(.move, [
            OperationRecordItem(original: original, result: result, trashed: trashedSource)
        ]))

        XCTAssertEqual(try read(original), "source")
        XCTAssertFalse(FileManager.default.fileExists(atPath: result.path))
    }

    func testUndoMoveAfterTrashWasEmptiedMovesCopyBack() async throws {
        let original = root.appendingPathComponent("moved.txt")
        let result = folder.appendingPathComponent("moved.txt")
        try write("copy", to: result)

        _ = try await makeService().undo(record(.move, [
            OperationRecordItem(original: original, result: result, trashed: trash.appendingPathComponent("gone.txt"))
        ]))

        XCTAssertEqual(try read(original), "copy")
    }

    func testUndoNewFolderOnlyTrashesEmptyFolders() async throws {
        let empty = folder.appendingPathComponent("Empty", isDirectory: true)
        let used = folder.appendingPathComponent("Used", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: used, withIntermediateDirectories: false)
        try write("x", to: used.appendingPathComponent("x.txt"))

        _ = try await makeService().undo(record(.newFolder, [OperationRecordItem(original: empty, result: empty)]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: empty.path))

        do {
            _ = try await makeService().undo(record(.newFolder, [OperationRecordItem(original: used, result: used)]))
            XCTFail("Expected a non-empty folder to stay")
        } catch let error as OperationUndoService.UndoError {
            XCTAssertEqual(error, .folderNotEmpty(name: "Used"))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: used.path))
    }

    func testPartialUndoReportsRestoredItems() async throws {
        let present = trash.appendingPathComponent("present.txt")
        try write("p", to: present)
        let undo = record(.trash, [
            OperationRecordItem(original: folder.appendingPathComponent("present.txt"), trashed: present),
            OperationRecordItem(original: folder.appendingPathComponent("gone.txt"), trashed: trash.appendingPathComponent("gone.txt"))
        ])

        do {
            _ = try await makeService().undo(undo)
            XCTFail("Expected a partial result")
        } catch let partial as PartialUndo {
            XCTAssertEqual(partial.changed, [folder.standardizedFileURL])
            guard case let .partial(restored, failed, _) = partial.error else { return XCTFail("Wrong error") }
            XCTAssertEqual(restored, 1)
            XCTAssertEqual(failed, 1)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("present.txt").path))
    }

    @MainActor
    func testAppModelUndoesNewestOperationAndMarksIt() async throws {
        let storeURL = root.appendingPathComponent("history.json")
        let history = OperationHistoryModel(store: OperationHistoryStore(fileURL: storeURL))
        try await waitForPane { history.isLoaded }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let model = AppModel(defaults: defaults, operationHistory: history, undoService: makeService())

        let trashed = trash.appendingPathComponent("item.txt")
        try write("item", to: trashed)
        let older = record(.trash, [OperationRecordItem(original: folder.appendingPathComponent("item.txt"), trashed: trashed)])
        history.record(older)
        var alreadyUndone = record(.newFolder, [OperationRecordItem(original: folder, result: folder)])
        alreadyUndone.isUndone = true
        history.record(alreadyUndone)

        XCTAssertEqual(model.latestUndoableOperation?.id, older.id)
        model.undoLatestOperation()
        try await waitForPane { !model.isUndoing && history.records.first(where: { $0.id == older.id })?.isUndone == true }
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("item.txt").path))
        XCTAssertNil(model.latestUndoableOperation)
    }
}
