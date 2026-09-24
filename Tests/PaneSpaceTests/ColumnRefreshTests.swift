import Foundation
import XCTest
@testable import PaneSpaceApp

final class ColumnRefreshTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/columns", isDirectory: true)
    private var folderB: FileItem { .stub("B", in: root, folder: true) }
    private var folderC: FileItem { .stub("C", in: folderB.url, folder: true) }
    private var fileInC: FileItem { .stub("inside.txt", in: folderC.url) }

    private func makeProvider() -> StaticDirectoryProvider {
        StaticDirectoryProvider([
            root: [folderB, .stub("a.txt", in: root)],
            folderB.url: [folderC],
            folderC.url: [fileInC]
        ])
    }

    @MainActor
    private func openThreeColumns(provider: StaticDirectoryProvider) async throws -> BrowserPaneModel {
        let model = BrowserPaneModel(url: root, provider: provider)
        try await waitForPane { !model.isLoading && model.items.count == 2 }
        model.setViewMode(.columns)
        model.selectColumnItem(folderB, in: root)
        try await waitForPane { model.columns.count == 2 && model.columns.last?.isLoading == false }
        model.selectColumnItem(folderC, in: folderB.url)
        try await waitForPane { model.columns.count == 3 && model.columns.last?.isLoading == false }
        return model
    }

    @MainActor
    func testRefreshKeepsColumnPathWhenAnEarlierDirectoryChanges() async throws {
        let provider = makeProvider()
        let model = try await openThreeColumns(provider: provider)
        let historyCount = model.activeTab.backHistory.count

        await provider.setContents([folderB, .stub("a.txt", in: root), .stub("new.txt", in: root)], of: root)
        model.refresh()
        try await waitForPane { model.columns.first?.items.count == 3 }

        XCTAssertEqual(model.columns.map(\.directory), [root, folderB.url, folderC.url])
        XCTAssertEqual(model.columns[0].selectedItemID, folderB.id)
        XCTAssertEqual(model.columns[1].selectedItemID, folderC.id)
        XCTAssertEqual(model.currentURL.standardizedFileURL, folderC.url.standardizedFileURL)
        XCTAssertEqual(model.activeTab.backHistory.count, historyCount)
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testExplicitNavigationStillRebuildsColumns() async throws {
        let model = try await openThreeColumns(provider: makeProvider())

        model.navigate(to: root)
        try await waitForPane { !model.isLoading && model.columns.count == 1 }

        XCTAssertEqual(model.columns.first?.directory, root)
    }

    @MainActor
    func testRefreshDropsColumnsAfterARemovedSelection() async throws {
        let provider = makeProvider()
        let model = try await openThreeColumns(provider: provider)

        await provider.setContents([], of: folderB.url)
        await provider.setContents(nil, of: folderC.url)
        model.refresh()
        try await waitForPane { model.columns.count == 2 }

        XCTAssertEqual(model.columns.map(\.directory), [root, folderB.url])
        XCTAssertNil(model.columns[1].selectedItemID)
        XCTAssertEqual(model.currentURL.standardizedFileURL, folderB.url.standardizedFileURL)
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testRefreshMarksAnUnreadableColumnAndDropsLaterColumns() async throws {
        let provider = makeProvider()
        let model = try await openThreeColumns(provider: provider)

        await provider.setContents(nil, of: folderB.url)
        model.refresh()
        try await waitForPane { model.columns.count == 2 }

        XCTAssertEqual(model.columns[0].selectedItemID, folderB.id)
        XCTAssertNotNil(model.columns[1].errorMessage)
        XCTAssertEqual(model.currentURL.standardizedFileURL, root.standardizedFileURL)
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testObservesEveryDisplayedColumnDirectory() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let first = base.appendingPathComponent("First", isDirectory: true)
        let second = first.appendingPathComponent("Second", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)

        let model = BrowserPaneModel(url: base, provider: LocalFileProvider())
        model.setDirectoryObservationEnabled(true)
        defer { model.setDirectoryObservationEnabled(false) }
        try await waitForPane { !model.isLoading && model.items.count == 1 }
        model.setViewMode(.columns)
        let firstItem = try XCTUnwrap(model.items.first)
        model.selectColumnItem(firstItem, in: try XCTUnwrap(model.columns.first?.id))
        try await waitForPane { model.columns.count == 2 && model.columns.last?.isLoading == false }
        let secondItem = try XCTUnwrap(model.columns.last?.items.first)
        model.selectColumnItem(secondItem, in: try XCTUnwrap(model.columns.last?.id))
        try await waitForPane { model.columns.count == 3 && model.columns.last?.isLoading == false }

        try Data("new".utf8).write(to: second.appendingPathComponent("new.txt"))
        try await waitForPane { model.columns.last?.items.map(\.name) == ["new.txt"] }
        XCTAssertEqual(model.columns.count, 3)

        try Data("top".utf8).write(to: base.appendingPathComponent("top.txt"))
        try await waitForPane { model.columns.first?.items.count == 2 }
        XCTAssertEqual(model.columns.count, 3)
    }

    @MainActor
    func testCollapsedColumnsStopTriggeringRefreshes() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let child = base.appendingPathComponent("Child", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: base.appendingPathComponent("file.txt"))

        let model = BrowserPaneModel(url: base, provider: LocalFileProvider())
        model.setDirectoryObservationEnabled(true)
        defer { model.setDirectoryObservationEnabled(false) }
        try await waitForPane { !model.isLoading && model.items.count == 2 }
        model.setViewMode(.columns)
        let rootColumn = try XCTUnwrap(model.columns.first?.id)
        let folder = try XCTUnwrap(model.items.first { $0.name == "Child" })
        let file = try XCTUnwrap(model.items.first { $0.name == "file.txt" })
        model.selectColumnItem(folder, in: rootColumn)
        try await waitForPane { model.columns.count == 2 && model.columns.last?.isLoading == false }

        model.selectColumnItem(file, in: rootColumn)
        XCTAssertEqual(model.columns.count, 1)
        let columnsBeforeChange = model.columns.map(\.items)

        try Data("late".utf8).write(to: child.appendingPathComponent("late.txt"))
        try await Task.sleep(for: .milliseconds(400))

        XCTAssertEqual(model.columns.count, 1)
        XCTAssertEqual(model.columns.map(\.items), columnsBeforeChange)
        XCTAssertEqual(model.columns.first?.selectedItemID, file.id)
    }
}
