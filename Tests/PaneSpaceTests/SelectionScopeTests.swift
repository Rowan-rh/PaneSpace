import Foundation
import XCTest
@testable import PaneSpaceApp

final class SelectionScopeTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/selection", isDirectory: true)
    private var fileA: FileItem { .stub("a.txt", in: root) }
    private var fileB: FileItem { .stub("b.txt", in: root) }
    private var fileC: FileItem { .stub("c.txt", in: root) }

    @MainActor
    private func makeModel() async throws -> (BrowserPaneModel, StaticDirectoryProvider) {
        let provider = StaticDirectoryProvider([root: [fileC, fileA, fileB]])
        let model = BrowserPaneModel(url: root, provider: provider)
        try await waitForPane { !model.isLoading && model.items.count == 3 }
        return (model, provider)
    }

    @MainActor
    func testFilteredOutSelectionIsExcludedAndReturnsWhenSearchClears() async throws {
        let (model, _) = try await makeModel()
        model.selection = [fileA.id]

        model.searchText = "b"
        XCTAssertTrue(model.selectedItems.isEmpty)

        model.searchText = ""
        XCTAssertEqual(model.selectedItems.map(\.id), [fileA.id])
    }

    @MainActor
    func testPartiallyFilteredSelectionOnlyIncludesVisibleItems() async throws {
        let (model, _) = try await makeModel()
        model.selection = [fileA.id, fileB.id]

        model.searchText = "b"

        XCTAssertEqual(model.selectedItems.map(\.id), [fileB.id])
    }

    @MainActor
    func testSelectedItemsFollowDisplayOrder() async throws {
        let (model, _) = try await makeModel()
        model.selection = [fileC.id, fileA.id, fileB.id]

        XCTAssertEqual(model.selectedItems.map(\.name), ["a.txt", "b.txt", "c.txt"])
        model.setSort(.name)
        XCTAssertEqual(model.selectedItems.map(\.name), ["c.txt", "b.txt", "a.txt"])
    }

    @MainActor
    func testItemsForIdsIgnoresHiddenAndUnknownItems() async throws {
        let (model, _) = try await makeModel()
        model.searchText = "a"

        let targets = model.items(for: [fileA.id, fileB.id, root.appendingPathComponent("missing")])

        XCTAssertEqual(targets.map(\.id), [fileA.id])
    }

    @MainActor
    func testTrashOnlyMovesTheRequestedItems() async throws {
        let (model, provider) = try await makeModel()
        model.selection = [fileA.id, fileB.id, fileC.id]

        model.trash([fileB])
        try await waitForPane { !model.isPerformingOperation && !model.isLoading && model.items.count == 2 }

        let trashed = await provider.trashedURLs
        XCTAssertEqual(trashed, [fileB.url])
        XCTAssertEqual(Set(model.items.map(\.id)), [fileA.id, fileC.id])
    }

    @MainActor
    func testTrashSelectionSkipsFilteredOutItems() async throws {
        let (model, provider) = try await makeModel()
        model.selection = [fileA.id]
        model.searchText = "b"

        model.trashSelection()
        try await Task.sleep(for: .milliseconds(50))

        let trashed = await provider.trashedURLs
        XCTAssertTrue(trashed.isEmpty)
        XCTAssertFalse(model.isPerformingOperation)
    }
}
