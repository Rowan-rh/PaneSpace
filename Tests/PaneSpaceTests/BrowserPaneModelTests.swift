import Foundation
import XCTest
@testable import PaneSpaceApp

final class BrowserPaneModelTests: XCTestCase {
    @MainActor
    func testSearchFiltersCurrentPaneCaseInsensitivelyAndKeepsQueriesIndependent() async throws {
        let fixture = ColumnNavigationFixture()
        let firstPane = BrowserPaneModel(url: fixture.root, provider: fixture.provider)
        let secondPane = BrowserPaneModel(url: fixture.root, provider: fixture.provider)
        try await waitUntil { !firstPane.isLoading && !secondPane.isLoading }

        firstPane.searchText = "FILE"
        secondPane.searchText = "fold"

        XCTAssertEqual(firstPane.visibleItems.map(\.name), ["file.txt"])
        XCTAssertEqual(secondPane.visibleItems.map(\.name), ["folder"])

        firstPane.searchText = ""

        XCTAssertEqual(Set(firstPane.visibleItems.map(\.name)), Set(["folder", "file.txt"]))
        XCTAssertEqual(secondPane.visibleItems.map(\.name), ["folder"])
    }

    @MainActor
    func testKeyboardFolderEntryAndParentNavigationRestoreFolderSelection() async throws {
        let fixture = ColumnNavigationFixture()
        let model = BrowserPaneModel(url: fixture.root, provider: fixture.provider)
        try await waitUntil { !model.isLoading }

        model.selection = [fixture.folder.id]
        XCTAssertTrue(model.enterSelectedFolderFromKeyboard())
        try await waitUntil { !model.isLoading && model.currentURL == fixture.folder.url }
        XCTAssertEqual(model.items.map(\.id), [fixture.subfolder.id])
        XCTAssertTrue(model.selection.isEmpty)

        XCTAssertTrue(model.goUp())
        try await waitUntil { !model.isLoading && model.currentURL == fixture.root }
        XCTAssertEqual(model.selection, [fixture.folder.id])
    }

    @MainActor
    func testKeyboardFolderEntryDoesNothingForFilesOrMultipleSelection() async throws {
        let fixture = ColumnNavigationFixture()
        let model = BrowserPaneModel(url: fixture.root, provider: fixture.provider)
        try await waitUntil { !model.isLoading }

        model.selection = [fixture.file.id]
        XCTAssertFalse(model.enterSelectedFolderFromKeyboard())
        XCTAssertEqual(model.currentURL, fixture.root)

        model.selection = [fixture.file.id, fixture.folder.id]
        XCTAssertFalse(model.enterSelectedFolderFromKeyboard())
        XCTAssertEqual(model.currentURL, fixture.root)

        model.selection = []
        XCTAssertFalse(model.enterSelectedFolderFromKeyboard())
        XCTAssertEqual(model.currentURL, fixture.root)
    }

    @MainActor
    func testKeyboardParentNavigationDoesNothingAtFileSystemRoot() async throws {
        let fixture = ColumnNavigationFixture()
        let root = URL(fileURLWithPath: "/", isDirectory: true)
        let model = BrowserPaneModel(url: root, provider: fixture.provider)
        try await waitUntil { !model.isLoading }

        XCTAssertFalse(model.goUp())
        XCTAssertEqual(model.currentURL.standardizedFileURL, root.standardizedFileURL)
    }

    @MainActor
    func testKeyboardParentNavigationLeavesSelectionEmptyWhenDepartedFolderWasRemoved() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let child = root.appendingPathComponent("Child", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)

        let model = BrowserPaneModel(url: root, provider: LocalFileProvider())
        try await waitUntil { !model.isLoading && model.items.count == 1 }
        model.selection = [try XCTUnwrap(model.items.first?.id)]
        XCTAssertTrue(model.enterSelectedFolderFromKeyboard())
        try await waitUntil { !model.isLoading && model.currentURL == child }

        try FileManager.default.removeItem(at: child)
        XCTAssertTrue(model.goUp())
        try await waitUntil { !model.isLoading && model.currentURL == root }

        XCTAssertTrue(model.items.isEmpty)
        XCTAssertTrue(model.selection.isEmpty)
    }

    @MainActor
    func testKeyboardParentNavigationFromFirstColumnRestoresFolderSelection() async throws {
        let fixture = ColumnNavigationFixture()
        let model = BrowserPaneModel(url: fixture.folder.url, provider: fixture.provider)
        try await waitUntil { !model.isLoading }
        model.setViewMode(.columns)

        let firstColumn = try XCTUnwrap(model.columns.first)
        XCTAssertTrue(model.goUp(from: firstColumn.directory))
        try await waitUntil { !model.isLoading && model.currentURL == fixture.root }

        XCTAssertEqual(model.columns.first?.selectedItemID, fixture.folder.id)
        XCTAssertEqual(model.selection, [fixture.folder.id])
    }

    @MainActor
    func testColumnSelectionLoadsTheNextDirectory() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let child = root.appendingPathComponent("Projects", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: child.appendingPathComponent("README.txt"))

        let model = BrowserPaneModel(url: root, provider: LocalFileProvider())
        try await waitUntil { !model.isLoading && model.items.count == 1 }
        model.setViewMode(.columns)

        let folder = try XCTUnwrap(model.items.first)
        model.selectColumnItem(folder, in: try XCTUnwrap(model.columns.first?.id))
        try await waitUntil { model.columns.count == 2 && model.columns.last?.isLoading == false }

        XCTAssertEqual(model.currentURL.standardizedFileURL, child.standardizedFileURL)
        XCTAssertEqual(model.columns.last?.items.map(\.name), ["README.txt"])
        XCTAssertEqual(model.selection, [folder.id])

        model.goBack()
        try await waitUntil { !model.isLoading && model.currentURL.standardizedFileURL == root.standardizedFileURL }
        XCTAssertEqual(model.columns.count, 1)
        XCTAssertEqual(model.columns.first?.items.map(\.name), ["Projects"])
    }

    @MainActor
    func testColumnArrowNavigationEntersChildrenAndReturnsAcrossColumns() async throws {
        let fixture = ColumnNavigationFixture()
        let model = BrowserPaneModel(url: fixture.root, provider: fixture.provider)
        try await waitUntil { !model.isLoading }
        model.setViewMode(.columns)

        let rootColumn = try XCTUnwrap(model.columns.first?.id)
        model.selectColumnItem(fixture.folder, in: rootColumn)
        try await waitUntil { model.columns.count == 2 && model.columns.last?.isLoading == false }
        let folderColumn = try XCTUnwrap(model.columns.last?.id)

        XCTAssertEqual(model.enterSelectedColumnFolderFromKeyboard(in: rootColumn), folderColumn)
        XCTAssertEqual(model.selection, [fixture.subfolder.id])
        XCTAssertEqual(model.currentURL.standardizedFileURL, fixture.subfolder.url.standardizedFileURL)
        try await waitUntil { model.columns.count == 3 && model.columns.last?.isLoading == false }
        let emptyColumn = try XCTUnwrap(model.columns.last?.id)
        XCTAssertTrue(try XCTUnwrap(model.columns.last).items.isEmpty)

        XCTAssertEqual(model.enterSelectedColumnFolderFromKeyboard(in: folderColumn), emptyColumn)
        XCTAssertEqual(model.returnToPreviousColumnFromKeyboard(in: emptyColumn), folderColumn)
        XCTAssertEqual(model.columns.map(\.id), [rootColumn, folderColumn, emptyColumn])
        XCTAssertEqual(model.columns[1].selectedItemID, fixture.subfolder.id)
        XCTAssertNil(model.columns[2].selectedItemID)
        XCTAssertEqual(model.selection, [fixture.subfolder.id])
        XCTAssertFalse(model.isLoading)

        XCTAssertEqual(model.returnToPreviousColumnFromKeyboard(in: folderColumn), rootColumn)
        XCTAssertEqual(model.columns.map(\.id), [rootColumn, folderColumn])
        XCTAssertEqual(model.columns[0].selectedItemID, fixture.folder.id)
        XCTAssertNil(model.columns[1].selectedItemID)
        XCTAssertEqual(model.selection, [fixture.folder.id])
        XCTAssertEqual(model.currentURL.standardizedFileURL, fixture.folder.url.standardizedFileURL)
        XCTAssertNil(model.returnToPreviousColumnFromKeyboard(in: rootColumn))

        XCTAssertEqual(model.enterSelectedColumnFolderFromKeyboard(in: rootColumn), folderColumn)
        XCTAssertEqual(model.selection, [fixture.subfolder.id])
        XCTAssertEqual(model.columns.map(\.id), [rootColumn, folderColumn, emptyColumn])

        XCTAssertTrue(model.goUp(from: rootColumn))
        try await waitUntil { model.columns.count == 1 && !model.isLoading && model.currentURL.path == "/" }
    }

    @MainActor
    func testTransferDestinationUsesTheFolderHoldingTheVisibleSelection() async throws {
        let fixture = ColumnNavigationFixture()
        let model = BrowserPaneModel(url: fixture.root, provider: fixture.provider)
        try await waitUntil { !model.isLoading }
        XCTAssertEqual(model.transferDestinationURL, fixture.root)

        model.setViewMode(.columns)
        XCTAssertEqual(model.transferDestinationURL, fixture.root)

        model.selectColumnItem(fixture.folder, in: fixture.root)
        try await waitUntil { model.columns.count == 2 && model.columns.last?.isLoading == false }
        XCTAssertEqual(model.currentURL.standardizedFileURL, fixture.folder.url.standardizedFileURL)
        XCTAssertEqual(model.transferDestinationURL, fixture.root)

        model.selectColumnItem(fixture.subfolder, in: fixture.folder.url)
        try await waitUntil { model.columns.count == 3 && model.columns.last?.isLoading == false }
        XCTAssertEqual(model.transferDestinationURL, fixture.folder.url)
    }

    @MainActor
    func testColumnArrowNavigationMovesSelectionAndIgnoresFiles() async throws {
        let fixture = ColumnNavigationFixture()
        let model = BrowserPaneModel(url: fixture.root, provider: fixture.provider)
        try await waitUntil { !model.isLoading }
        model.setViewMode(.columns)
        let rootColumn = try XCTUnwrap(model.columns.first?.id)

        XCTAssertNil(model.enterSelectedColumnFolderFromKeyboard(in: rootColumn))
        XCTAssertNil(model.returnToPreviousColumnFromKeyboard(in: rootColumn))
        XCTAssertTrue(model.moveColumnSelection(by: 1, in: rootColumn))
        XCTAssertEqual(model.selection, [fixture.folder.id])
        XCTAssertTrue(model.moveColumnSelection(by: 1, in: rootColumn))
        XCTAssertEqual(model.selection, [fixture.file.id])
        XCTAssertNil(model.enterSelectedColumnFolderFromKeyboard(in: rootColumn))
        XCTAssertTrue(model.moveColumnSelection(by: -1, in: rootColumn))
        XCTAssertEqual(model.selection, [fixture.folder.id])
    }

    @MainActor
    func testColumnArrowNavigationTargetsChildWhileItLoads() async throws {
        let fixture = ColumnNavigationFixture()
        let provider = DelayedColumnProvider(fixture: fixture)
        let model = BrowserPaneModel(url: fixture.root, provider: provider)
        try await waitUntil { !model.isLoading }
        model.setViewMode(.columns)
        let rootColumn = try XCTUnwrap(model.columns.first?.id)

        model.selectColumnItem(fixture.folder, in: rootColumn)
        await provider.waitUntilColumnLoadStarts()
        XCTAssertTrue(try XCTUnwrap(model.columns.last).isLoading)

        XCTAssertEqual(
            model.enterSelectedColumnFolderFromKeyboard(in: rootColumn),
            fixture.folder.url
        )
        try await waitUntil { model.columns.last?.isLoading == false }
        XCTAssertTrue(try XCTUnwrap(model.columns.last).items.isEmpty)
    }

    @MainActor
    func testSwitchingToColumnsUsesTheCurrentDirectory() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let model = BrowserPaneModel(url: root, provider: LocalFileProvider())
        try await waitUntil { !model.isLoading }
        model.setViewMode(.columns)

        XCTAssertEqual(model.viewMode, .columns)
        XCTAssertEqual(model.columns.map(\.directory.standardizedFileURL), [root.standardizedFileURL])
    }

    @MainActor
    func testSelectingAFileInAnEarlierColumnRestoresItsContainingDirectory() async throws {
        let fixture = ColumnNavigationFixture()
        let model = BrowserPaneModel(url: fixture.root, provider: fixture.provider)
        try await waitUntil { !model.isLoading }
        model.setViewMode(.columns)

        model.selectColumnItem(fixture.folder, in: fixture.root)
        try await waitUntil { model.columns.last?.isLoading == false }
        model.selectColumnItem(fixture.file, in: fixture.root)

        XCTAssertEqual(model.currentURL.standardizedFileURL, fixture.root.standardizedFileURL)
        XCTAssertEqual(Set(model.items.map(\.id)), Set([fixture.folder.id, fixture.file.id]))
    }

    @MainActor
    func testSwitchingToListClearsASelectionThatIsNotInTheCurrentDirectory() async throws {
        let fixture = ColumnNavigationFixture()
        let model = BrowserPaneModel(url: fixture.root, provider: fixture.provider)
        try await waitUntil { !model.isLoading }
        model.setViewMode(.columns)
        model.selectColumnItem(fixture.folder, in: fixture.root)
        try await waitUntil { model.columns.last?.isLoading == false }

        model.setViewMode(.list)

        XCTAssertTrue(model.selection.isEmpty)
        XCTAssertTrue(model.selectedItems.isEmpty)
    }

    @MainActor
    func testRenamingAnAncestorRemapsTheCurrentDirectoryAndHistory() async throws {
        let fixture = ColumnNavigationFixture()
        let model = BrowserPaneModel(url: fixture.root, provider: fixture.provider)
        try await waitUntil { !model.isLoading }
        model.navigate(to: fixture.folder.url)
        try await waitUntil { !model.isLoading }
        model.navigate(to: fixture.subfolder.url)
        try await waitUntil { !model.isLoading }

        model.rename(fixture.folder, to: "renamed")
        try await waitUntil { !model.isPerformingOperation && !model.isLoading }

        let renamedFolder = fixture.root.appendingPathComponent("renamed", isDirectory: true)
        XCTAssertEqual(
            model.currentURL.standardizedFileURL,
            renamedFolder.appendingPathComponent("sub", isDirectory: true).standardizedFileURL
        )
        XCTAssertTrue(model.activeTab.backHistory.contains(renamedFolder))
    }

    @MainActor
    func testRefreshCancelsAnOlderColumnLoad() async throws {
        let fixture = ColumnNavigationFixture()
        let provider = DelayedColumnProvider(fixture: fixture)
        let model = BrowserPaneModel(url: fixture.root, provider: provider)
        try await waitUntil { !model.isLoading }
        model.setViewMode(.columns)
        model.selectColumnItem(fixture.folder, in: fixture.root)
        await provider.waitUntilColumnLoadStarts()

        model.toggleHiddenFiles()
        try await waitUntil { !model.isLoading }
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(model.items.map(\.id), [fixture.subfolder.id])
    }

    @MainActor
    func testPartialTrashFailureRefreshesItemsAndKeepsLoadStateHealthy() async throws {
        let root = URL(fileURLWithPath: "/test", isDirectory: true)
        let first = FileItem(
            url: root.appendingPathComponent("first.txt"),
            isDirectory: false,
            isHidden: false,
            fileSize: 1,
            modificationDate: nil,
            kind: "Text"
        )
        let second = FileItem(
            url: root.appendingPathComponent("second.txt"),
            isDirectory: false,
            isHidden: false,
            fileSize: 1,
            modificationDate: nil,
            kind: "Text"
        )
        let provider = PartialTrashFailureProvider(items: [first, second], failingURL: second.url)
        let model = BrowserPaneModel(url: root, provider: provider)
        try await waitUntil { !model.isLoading && model.items.count == 2 }

        model.selection = [first.id, second.id]
        model.trashSelection()
        try await waitUntil { !model.isPerformingOperation && !model.isLoading }

        XCTAssertEqual(model.items.map(\.id), [second.id])
        XCTAssertNil(model.errorMessage)
        XCTAssertNotNil(model.operationErrorMessage)
    }

    @MainActor
    func testRenameFailureDoesNotReplaceFolderContents() async throws {
        let root = URL(fileURLWithPath: "/test", isDirectory: true)
        let item = FileItem(
            url: root.appendingPathComponent("first.txt"),
            isDirectory: false,
            isHidden: false,
            fileSize: 1,
            modificationDate: nil,
            kind: "Text"
        )
        let provider = RenameFailureProvider(items: [item])
        let model = BrowserPaneModel(url: root, provider: provider)
        try await waitUntil { !model.isLoading && model.items == [item] }

        model.rename(item, to: "renamed.txt")
        try await waitUntil { !model.isPerformingOperation }

        XCTAssertEqual(model.items, [item])
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.operationErrorMessage, FileProviderError.permissionDenied.localizedDescription)
    }

    @MainActor
    func testObservedDirectoryRefreshesAndKeepsSurvivingSelection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let model = BrowserPaneModel(url: root, provider: LocalFileProvider())
        model.setDirectoryObservationEnabled(true)
        defer { model.setDirectoryObservationEnabled(false) }
        try await waitUntil { !model.isLoading }

        let first = root.appendingPathComponent("first.txt")
        try Data("one".utf8).write(to: first)
        try await waitUntil { model.items.map(\.name) == ["first.txt"] }
        guard let firstID = model.items.first?.id else {
            return XCTFail("Observed file did not appear")
        }
        model.selection = [firstID]

        try Data("two".utf8).write(to: root.appendingPathComponent("second.txt"))
        try await waitUntil { model.items.count == 2 }
        XCTAssertEqual(model.selection, [firstID])
    }

    @MainActor
    func testOldDirectoryObservationCannotReplaceNewLocation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("First", isDirectory: true)
        let second = root.appendingPathComponent("Second", isDirectory: true)
        for directory in [first, second] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let model = BrowserPaneModel(url: first, provider: LocalFileProvider())
        model.setDirectoryObservationEnabled(true)
        defer { model.setDirectoryObservationEnabled(false) }
        try await waitUntil { !model.isLoading }

        model.navigate(to: second)
        try await waitUntil { !model.isLoading && model.currentURL == second }
        try Data("old".utf8).write(to: first.appendingPathComponent("old.txt"))
        try await Task.sleep(for: .milliseconds(350))

        XCTAssertEqual(model.currentURL, second)
        XCTAssertTrue(model.items.isEmpty)
    }

    @MainActor
    private func waitUntil(
        timeoutIterations: Int = 200,
        condition: () -> Bool
    ) async throws {
        for _ in 0 ..< timeoutIterations {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for asynchronous pane state")
    }
}

private struct ColumnNavigationFixture: Sendable {
    let root = URL(fileURLWithPath: "/review", isDirectory: true)

    var folder: FileItem { item(root.appendingPathComponent("folder", isDirectory: true), isDirectory: true) }
    var subfolder: FileItem { item(folder.url.appendingPathComponent("sub", isDirectory: true), isDirectory: true) }
    var file: FileItem { item(root.appendingPathComponent("file.txt"), isDirectory: false) }
    var provider: ColumnNavigationProvider { ColumnNavigationProvider(fixture: self) }

    private func item(_ url: URL, isDirectory: Bool) -> FileItem {
        FileItem(
            url: url,
            isDirectory: isDirectory,
            isHidden: false,
            fileSize: nil,
            modificationDate: nil,
            kind: "Item"
        )
    }
}

private actor ColumnNavigationProvider: FileProviding {
    private let fixture: ColumnNavigationFixture

    init(fixture: ColumnNavigationFixture) {
        self.fixture = fixture
    }

    func contents(of directory: URL, showsHiddenFiles: Bool) -> [FileItem] {
        switch directory.standardizedFileURL {
        case fixture.root.standardizedFileURL:
            [fixture.folder, fixture.file]
        case fixture.folder.url.standardizedFileURL:
            [fixture.subfolder]
        default:
            []
        }
    }

    func createFolder(named name: String, in directory: URL) throws -> URL {
        throw FileProviderError.operationFailed
    }

    func rename(_ item: URL, to newName: String) -> URL {
        item.deletingLastPathComponent().appendingPathComponent(newName, isDirectory: true)
    }

    func moveToTrash(_ item: URL) throws {
        throw FileProviderError.operationFailed
    }
}

private actor DelayedColumnProvider: FileProviding {
    private let fixture: ColumnNavigationFixture
    private var columnLoadStarted = false

    init(fixture: ColumnNavigationFixture) {
        self.fixture = fixture
    }

    func waitUntilColumnLoadStarts() async {
        while !columnLoadStarted {
            await Task.yield()
        }
    }

    func contents(of directory: URL, showsHiddenFiles: Bool) async throws -> [FileItem] {
        if directory.standardizedFileURL == fixture.root.standardizedFileURL {
            return [fixture.folder]
        }
        if !showsHiddenFiles {
            columnLoadStarted = true
            try await Task.sleep(for: .milliseconds(120))
            return []
        }
        return [fixture.subfolder]
    }

    func createFolder(named name: String, in directory: URL) throws -> URL {
        throw FileProviderError.operationFailed
    }

    func rename(_ item: URL, to newName: String) throws -> URL {
        throw FileProviderError.operationFailed
    }

    func moveToTrash(_ item: URL) throws {
        throw FileProviderError.operationFailed
    }
}

private actor PartialTrashFailureProvider: FileProviding {
    private var items: [FileItem]
    private let failingURL: URL

    init(items: [FileItem], failingURL: URL) {
        self.items = items
        self.failingURL = failingURL
    }

    func contents(of directory: URL, showsHiddenFiles: Bool) -> [FileItem] {
        items
    }

    func createFolder(named name: String, in directory: URL) throws -> URL {
        throw FileProviderError.operationFailed
    }

    func rename(_ item: URL, to newName: String) throws -> URL {
        throw FileProviderError.operationFailed
    }

    func moveToTrash(_ item: URL) throws {
        if item == failingURL {
            throw FileProviderError.permissionDenied
        }
        items.removeAll { $0.url == item }
    }
}

private actor RenameFailureProvider: FileProviding {
    private let items: [FileItem]

    init(items: [FileItem]) {
        self.items = items
    }

    func contents(of directory: URL, showsHiddenFiles: Bool) -> [FileItem] {
        items
    }

    func createFolder(named name: String, in directory: URL) throws -> URL {
        throw FileProviderError.operationFailed
    }

    func rename(_ item: URL, to newName: String) throws -> URL {
        throw FileProviderError.permissionDenied
    }

    func moveToTrash(_ item: URL) throws {
        throw FileProviderError.operationFailed
    }
}
