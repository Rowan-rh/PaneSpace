import Foundation
import XCTest
@testable import PaneSpaceApp

final class RenameOpenFolderTests: XCTestCase {
    /// Temporary folders live under /private/var, where the old URL of a renamed folder no longer
    /// standardizes to the same path as the stored tab URL.
    @MainActor
    func testRenamingTheOpenColumnFolderFollowsTheNewName() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Old", isDirectory: true), withIntermediateDirectories: true)

        let model = BrowserPaneModel(url: root, provider: LocalFileProvider())
        try await waitForPane { !model.isLoading && model.items.count == 1 }
        model.setViewMode(.columns)
        let column = try XCTUnwrap(model.columns.first)
        let folder = try XCTUnwrap(model.displayedItems(in: column).first)
        model.selectColumnItem(folder, in: column.id)
        try await waitForPane { model.columns.count == 2 && !model.columns[1].isLoading }

        model.rename(folder, to: "New")
        try await waitForPane { !model.isPerformingOperation }
        try await waitForPane { !model.isLoading }
        try await waitForPane { model.currentURL.lastPathComponent == "New" && !model.isLoading }
        XCTAssertEqual(model.currentURL.lastPathComponent, "New")
        XCTAssertNil(model.errorMessage)
    }
}
