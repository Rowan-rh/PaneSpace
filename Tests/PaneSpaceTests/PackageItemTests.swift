import Foundation
import XCTest
@testable import PaneSpaceApp

final class PackageItemTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/packages", isDirectory: true)

    private var folder: FileItem { .stub("Zeta", in: root, folder: true) }
    private var application: FileItem { .stub("Alpha.app", in: root, package: true) }
    private var document: FileItem { .stub("beta.txt", in: root) }

    private func makeProvider() -> StaticDirectoryProvider {
        StaticDirectoryProvider([
            root: [document, application, folder],
            folder.url: [],
            application.url: [.stub("Contents", in: application.url, folder: true)]
        ])
    }

    @MainActor
    func testPackagesSortWithFilesAfterFolders() async throws {
        let model = BrowserPaneModel(url: root, provider: makeProvider())
        try await waitForPane { !model.isLoading && model.items.count == 3 }

        XCTAssertEqual(model.visibleItems.map(\.name), ["Zeta", "Alpha.app", "beta.txt"])
    }

    @MainActor
    func testRightArrowDoesNotEnterPackage() async throws {
        let model = BrowserPaneModel(url: root, provider: makeProvider())
        try await waitForPane { !model.isLoading && model.items.count == 3 }

        model.selection = [application.id]
        XCTAssertFalse(model.enterSelectedFolderFromKeyboard())
        XCTAssertEqual(model.currentURL, root)
    }

    @MainActor
    func testSelectingPackageInColumnsDoesNotAppendColumn() async throws {
        let model = BrowserPaneModel(url: root, provider: makeProvider())
        try await waitForPane { !model.isLoading && model.items.count == 3 }
        model.setViewMode(.columns)

        model.selectColumnItem(application, in: root)

        XCTAssertEqual(model.columns.count, 1)
        XCTAssertEqual(model.columns.first?.selectedItemID, application.id)
        XCTAssertEqual(model.currentURL.standardizedFileURL, root.standardizedFileURL)
        XCTAssertNil(model.enterSelectedColumnFolderFromKeyboard(in: root))
    }
}
