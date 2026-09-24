import Foundation
import XCTest
@testable import PaneSpaceApp

final class ItemSelectionTests: XCTestCase {
    private let order = [1, 2, 3, 4, 5, 6]

    func testShiftRangeSelectsFromAnchorInEitherDirection() {
        var selection = ItemSelection<Int>()
        selection.select(2)
        selection.extend(to: 5, in: order)
        XCTAssertEqual(selection.selected, [2, 3, 4, 5])

        selection.extend(to: 1, in: order)
        XCTAssertEqual(selection.selected, [1, 2])
    }

    func testToggleAddsAndRemovesWithoutTouchingOtherItems() {
        var selection = ItemSelection<Int>()
        selection.select(1)
        selection.toggle(3, in: order)
        selection.toggle(1, in: order)
        XCTAssertEqual(selection.selected, [3])
    }

    func testShiftRangeAfterToggleStartsAtToggledItem() {
        var selection = ItemSelection<Int>()
        selection.select(1)
        selection.toggle(4, in: order)
        selection.extend(to: 6, in: order)
        XCTAssertEqual(selection.selected, [4, 5, 6])
    }

    func testKeyboardExtensionGrowsAndShrinksAroundAnchor() {
        var selection = ItemSelection<Int>()
        selection.select(2)
        selection.move(.next, extending: true, in: order)
        selection.move(.next, extending: true, in: order)
        XCTAssertEqual(selection.selected, [2, 3, 4])

        selection.move(.previous, extending: true, in: order)
        XCTAssertEqual(selection.selected, [2, 3])

        selection.move(.previous, extending: true, in: order)
        selection.move(.previous, extending: true, in: order)
        XCTAssertEqual(selection.selected, [1, 2])
    }

    func testPlainMoveCollapsesToNeighbourAndStopsAtEdges() {
        var selection = ItemSelection<Int>()
        selection.select(5)
        XCTAssertEqual(selection.move(.next, extending: false, in: order), 6)
        XCTAssertEqual(selection.selected, [6])
        XCTAssertNil(selection.move(.next, extending: false, in: order))
        XCTAssertEqual(selection.selected, [6])
    }

    func testMoveWithoutSelectionStartsAtListEdge() {
        var selection = ItemSelection<Int>()
        XCTAssertEqual(selection.move(.next, extending: false, in: order), 1)
        var reverse = ItemSelection<Int>()
        XCTAssertEqual(reverse.move(.previous, extending: true, in: order), 6)
        XCTAssertEqual(reverse.selected, [6])
    }

    func testExternalMouseSelectionIsAdoptedForKeyboardExtension() {
        var selection = ItemSelection<Int>()
        selection.select(1)
        // The system table selected 3...4 with a mouse drag.
        selection.adopt([3, 4])
        selection.move(.next, extending: true, in: order)
        XCTAssertEqual(selection.selected, [3, 4, 5])
    }

    func testSelectAllOnlyUsesGivenOrder() {
        var selection = ItemSelection<Int>()
        selection.select(1)
        selection.selectAll(in: [2, 4])
        XCTAssertEqual(selection.selected, [2, 4])
    }
}

final class MultipleSelectionPaneTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/multi", isDirectory: true)
    private var names: [String] { ["a.txt", "b.txt", "c.txt", "d.txt"] }

    @MainActor
    private func makeModel(extra: [FileItem] = [], contents: [URL: [FileItem]] = [:]) async throws -> BrowserPaneModel {
        let files = names.map { FileItem.stub($0, in: root) } + extra
        var directories = contents
        directories[root] = files
        let model = BrowserPaneModel(url: root, provider: StaticDirectoryProvider(directories))
        try await waitForPane { !model.isLoading && model.items.count == files.count }
        return model
    }

    @MainActor
    func testListKeyboardExtensionAndSelectAllRespectSearch() async throws {
        let model = try await makeModel()
        model.setViewMode(.list)
        model.selection = [root.appendingPathComponent("b.txt")]

        model.moveListSelection(.next, extending: true)
        model.moveListSelection(.next, extending: true)
        XCTAssertEqual(model.selectedItems.map(\.name), ["b.txt", "c.txt", "d.txt"])

        model.moveListSelection(.previous, extending: false)
        XCTAssertEqual(model.selectedItems.map(\.name), ["c.txt"])

        model.searchText = "a"
        model.selectAllVisibleItems()
        XCTAssertEqual(model.selection, [root.appendingPathComponent("a.txt")])
    }

    @MainActor
    func testColumnModifierClicksSelectRangeAndToggleWithinColumn() async throws {
        let folder = FileItem.stub("folder", in: root, folder: true)
        let model = try await makeModel(
            extra: [folder],
            contents: [folder.url: [FileItem.stub("inside.txt", in: folder.url)]]
        )
        model.setViewMode(.columns)
        let column = try XCTUnwrap(model.columns.first)
        let items = model.displayedItems(in: column)
        XCTAssertEqual(items.map(\.name), ["folder", "a.txt", "b.txt", "c.txt", "d.txt"])

        model.clickColumnItem(items[0], in: column.id, modifier: .none)
        try await waitForPane { model.columns.count == 2 && model.columns[1].isLoading == false }

        model.clickColumnItem(items[2], in: column.id, modifier: .range)
        XCTAssertEqual(model.selectedItems.map(\.name), ["folder", "a.txt", "b.txt"])
        XCTAssertEqual(model.columns.count, 1, "Multiple selection does not show a child column")
        XCTAssertEqual(model.transferDestinationURL, root)

        model.clickColumnItem(items[1], in: column.id, modifier: .toggle)
        XCTAssertEqual(model.selectedItems.map(\.name), ["folder", "b.txt"])

        model.clickColumnItem(items[2], in: column.id, modifier: .toggle)
        XCTAssertEqual(model.selectedItems.map(\.name), ["folder"])
        try await waitForPane { model.columns.count == 2 }
        XCTAssertEqual(model.currentURL, folder.url.standardizedFileURL)
    }

    @MainActor
    func testColumnShiftArrowAndSelectAllUseActiveColumn() async throws {
        let model = try await makeModel()
        model.setViewMode(.columns)
        let column = try XCTUnwrap(model.columns.first)
        let items = model.displayedItems(in: column)
        model.clickColumnItem(items[1], in: column.id, modifier: .none)

        XCTAssertTrue(model.extendColumnSelection(.next, in: column.id))
        XCTAssertEqual(model.selectedItems.map(\.name), ["b.txt", "c.txt"])
        XCTAssertNil(model.enterSelectedColumnFolderFromKeyboard(in: column.id))

        model.selectAllItems(inColumn: column.id)
        XCTAssertEqual(model.selectedItems.count, 4)
    }
}
