import Foundation
import XCTest
@testable import PaneSpaceApp

final class PaneResponsivenessTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/responsive", isDirectory: true)
    private var folder: FileItem { .stub("Folder", in: root, folder: true) }
    private var fileA: FileItem { .stub("a.txt", in: root) }
    private var fileB: FileItem { .stub("b.txt", in: root) }

    private func makeProvider() -> StaticDirectoryProvider {
        StaticDirectoryProvider([
            root: [fileB, fileA, folder],
            folder.url: [.stub("inner.txt", in: folder.url)]
        ])
    }

    @MainActor
    func testDisplayedItemsFollowContentSearchAndSortChanges() async throws {
        let provider = makeProvider()
        let model = BrowserPaneModel(url: root, provider: provider)
        try await waitForPane { !model.isLoading && model.items.count == 3 }
        XCTAssertEqual(model.visibleItems.map(\.name), ["Folder", "a.txt", "b.txt"])

        model.setSort(.name)
        XCTAssertEqual(model.visibleItems.map(\.name), ["Folder", "b.txt", "a.txt"])

        model.searchText = "a."
        XCTAssertEqual(model.visibleItems.map(\.name), ["a.txt"])
        model.searchText = ""

        await provider.setContents([fileA, .stub("c.txt", in: root)], of: root)
        model.refresh()
        try await waitForPane { model.items.count == 2 }
        XCTAssertEqual(model.visibleItems.map(\.name), ["c.txt", "a.txt"])
    }

    @MainActor
    func testColumnDisplayedItemsUpdateAfterInPlaceRefresh() async throws {
        let provider = makeProvider()
        let model = BrowserPaneModel(url: root, provider: provider)
        try await waitForPane { !model.isLoading && model.items.count == 3 }
        model.setViewMode(.columns)
        model.selectColumnItem(folder, in: root)
        try await waitForPane { model.columns.count == 2 && model.columns.last?.isLoading == false }
        XCTAssertEqual(model.displayedItems(in: model.columns[1]).map(\.name), ["inner.txt"])

        await provider.setContents([.stub("inner.txt", in: folder.url), .stub("added.txt", in: folder.url)], of: folder.url)
        model.refresh()
        try await waitForPane { model.columns.last?.items.count == 2 }

        XCTAssertEqual(model.displayedItems(in: model.columns[1]).map(\.name), ["added.txt", "inner.txt"])
    }

    @MainActor
    func testQuickNavigationNeverShowsLoadingIndicator() async throws {
        let model = BrowserPaneModel(url: root, provider: makeProvider())
        try await waitForPane { !model.isLoading }

        var sawIndicator = false
        model.navigate(to: folder.url)
        for _ in 0 ..< 30 {
            sawIndicator = sawIndicator || model.showsLoadingIndicator
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertFalse(sawIndicator)
        XCTAssertEqual(model.items.map(\.name), ["inner.txt"])
    }

    @MainActor
    func testSlowNavigationShowsIndicatorButRefreshKeepsContents() async throws {
        let provider = makeProvider()
        let model = BrowserPaneModel(url: root, provider: provider)
        try await waitForPane { !model.isLoading }
        await provider.setLoadDelay(.milliseconds(400))

        model.navigate(to: folder.url)
        try await waitForPane { model.showsLoadingIndicator }
        try await waitForPane(timeoutIterations: 100) { !model.isLoading }
        XCTAssertFalse(model.showsLoadingIndicator)

        var sawIndicator = false
        model.refresh()
        while model.isLoading {
            sawIndicator = sawIndicator || model.showsLoadingIndicator
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(sawIndicator)
        XCTAssertEqual(model.items.map(\.name), ["inner.txt"])
    }
}
