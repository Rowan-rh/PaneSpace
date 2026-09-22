import Foundation
import XCTest
@testable import PaneSpaceApp

final class BrowserPaneModelTests: XCTestCase {
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
