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
