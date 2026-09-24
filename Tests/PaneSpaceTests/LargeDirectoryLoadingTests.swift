import Foundation
import XCTest
@testable import PaneSpaceApp

final class LargeDirectoryLoadingTests: XCTestCase {
    func testSorterPutsFoldersFirstAndComparesNumbersNaturally() {
        let root = URL(fileURLWithPath: "/sort", isDirectory: true)
        let items = [
            FileItem.stub("file10.txt", in: root),
            FileItem.stub("File2.txt", in: root),
            FileItem.stub("zeta", in: root, folder: true),
            FileItem.stub("alpha", in: root, folder: true),
            FileItem.stub("file1.txt", in: root)
        ]
        XCTAssertEqual(
            FileItemSorter.sorted(items, by: .name, ascending: true).map(\.name),
            ["alpha", "zeta", "file1.txt", "File2.txt", "file10.txt"]
        )
        XCTAssertEqual(
            FileItemSorter.sorted(items, by: .name, ascending: false).map(\.name),
            ["zeta", "alpha", "file10.txt", "File2.txt", "file1.txt"]
        )
    }

    func testSorterKeepsMissingDatesAfterPresentOnesWhenAscending() {
        let root = URL(fileURLWithPath: "/dates", isDirectory: true)
        let dated = { (name: String, seconds: Double?) in
            FileItem(
                url: root.appendingPathComponent(name),
                isDirectory: false,
                isHidden: false,
                fileSize: nil,
                modificationDate: seconds.map(Date.init(timeIntervalSince1970:)),
                kind: "Item"
            )
        }
        let items = [dated("none", nil), dated("new", 200), dated("old", 100)]
        XCTAssertEqual(FileItemSorter.sorted(items, by: .date, ascending: true).map(\.name), ["old", "new", "none"])
    }

    func testLocalProviderStreamsBatchesAndSharesKinds() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("Folder"), withIntermediateDirectories: true)
        let count = LocalFileProvider.batchSize + 5
        for index in 0 ..< count {
            FileManager.default.createFile(atPath: directory.appendingPathComponent("item-\(index).txt").path, contents: nil)
        }
        FileManager.default.createFile(atPath: directory.appendingPathComponent(".hidden").path, contents: nil)

        var batches: [[FileItem]] = []
        for try await batch in LocalFileProvider().contentBatches(of: directory, showsHiddenFiles: false) {
            batches.append(batch)
        }
        XCTAssertEqual(batches.count, 2)
        XCTAssertEqual(batches.first?.count, LocalFileProvider.batchSize)
        let all = batches.flatMap { $0 }
        XCTAssertEqual(all.count, count + 1)
        XCTAssertFalse(all.contains { $0.name == ".hidden" })
        let textKinds = Set(all.filter { $0.name.hasSuffix(".txt") }.map(\.kind))
        XCTAssertEqual(textKinds.count, 1)
        let folder = try XCTUnwrap(all.first { $0.name == "Folder" })
        XCTAssertTrue(folder.isFolder)
        XCTAssertFalse(textKinds.contains(folder.kind))
    }

    func testLocalProviderStreamFailsForMissingFolder() async throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            for try await _ in LocalFileProvider().contentBatches(of: missing, showsHiddenFiles: false) {}
            XCTFail("Expected a missing folder to fail")
        } catch let error as FileProviderError {
            XCTAssertEqual(error, .itemUnavailable)
        }
    }

    @MainActor
    func testPaneShowsFirstBatchBeforeTheListingFinishes() async throws {
        let root = URL(fileURLWithPath: "/stream", isDirectory: true)
        let provider = GatedBatchProvider(root: root)
        let model = BrowserPaneModel(url: root, provider: provider)

        try await waitForPane { model.items.count == 2 && model.isLoadingMoreItems }
        XCTAssertTrue(model.isLoading)
        XCTAssertEqual(model.visibleItems.map(\.name), ["a.txt", "b.txt"])

        await provider.release()
        try await waitForPane { !model.isLoading && model.items.count == 3 }
        XCTAssertFalse(model.isLoadingMoreItems)
        XCTAssertEqual(model.visibleItems.map(\.name), ["a.txt", "b.txt", "c.txt"])
    }
}

/// Delivers one batch, then waits until the test releases the rest.
private actor GatedBatchProvider: FileProviding {
    let root: URL
    private var gate: CheckedContinuation<Void, Never>?
    private var released = false

    init(root: URL) {
        self.root = root
    }

    func release() {
        released = true
        gate?.resume()
        gate = nil
    }

    private func waitForRelease() async {
        guard !released else { return }
        await withCheckedContinuation { gate = $0 }
    }

    nonisolated func contentBatches(of directory: URL, showsHiddenFiles: Bool) -> AsyncThrowingStream<[FileItem], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield([FileItem.stub("b.txt", in: self.root), FileItem.stub("a.txt", in: self.root)])
                await self.waitForRelease()
                continuation.yield([FileItem.stub("c.txt", in: self.root)])
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func contents(of directory: URL, showsHiddenFiles: Bool) -> [FileItem] { [] }
    func createFolder(named name: String, in directory: URL) throws -> URL { throw FileProviderError.operationFailed }
    func rename(_ item: URL, to newName: String) throws -> URL { throw FileProviderError.operationFailed }
    func moveToTrash(_ item: URL) throws -> URL? { throw FileProviderError.operationFailed }
}
