import Foundation
import XCTest
@testable import PaneSpaceApp

final class WorkspaceShortcutsTests: XCTestCase {
    private var home: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent("Code", isDirectory: true),
            withIntermediateDirectories: true
        )
        suiteName = "WorkspaceShortcutsTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: home)
    }

    @MainActor
    func testDefaultsOnlyIncludeExistingFolders() {
        let model = WorkspaceShortcutsModel(defaults: defaults, homeDirectory: home)

        XCTAssertEqual(model.shortcuts.map(\.systemImage), ["square.grid.2x2", "hammer"])
        XCTAssertEqual(model.shortcuts.last?.path, home.appendingPathComponent("Code").standardizedFileURL.path)
    }

    @MainActor
    func testEditsPersistAcrossInstancesAndRestoreDefaultsResets() {
        let model = WorkspaceShortcutsModel(defaults: defaults, homeDirectory: home)
        let project = WorkspaceShortcut(name: "Project", systemImage: "star", path: home.path)
        model.add(project)
        model.move(project.id, by: -1)
        var renamed = project
        renamed.name = "Renamed"
        model.update(renamed)
        model.remove(model.shortcuts[0].id)

        let reloaded = WorkspaceShortcutsModel(defaults: defaults, homeDirectory: home)
        XCTAssertEqual(reloaded.shortcuts.map(\.name), ["Renamed", L10n.text("Development")])

        reloaded.restoreDefaults()
        XCTAssertEqual(reloaded.shortcuts.map(\.systemImage), ["square.grid.2x2", "hammer"])
        XCTAssertNil(defaults.data(forKey: WorkspaceShortcutsModel.defaultsKey))
    }

    @MainActor
    func testMoveIgnoresOutOfRangeOffsets() {
        let model = WorkspaceShortcutsModel(defaults: defaults, homeDirectory: home)
        let order = model.shortcuts.map(\.id)

        model.move(order[0], by: -1)
        model.move(order[1], by: 1)

        XCTAssertEqual(model.shortcuts.map(\.id), order)
    }

    @MainActor
    func testCorruptStoredDataFallsBackToDefaults() {
        defaults.set(Data("not json".utf8), forKey: WorkspaceShortcutsModel.defaultsKey)

        let model = WorkspaceShortcutsModel(defaults: defaults, homeDirectory: home)

        XCTAssertEqual(model.shortcuts.count, 2)
    }

    @MainActor
    func testValidatesNameAndSymbol() {
        let model = WorkspaceShortcutsModel(defaults: defaults, homeDirectory: home)

        XCTAssertEqual(model.validationIssue(name: "  ", systemImage: "folder"), .emptyName)
        XCTAssertEqual(model.validationIssue(name: "Work", systemImage: "not.a.real.symbol"), .invalidSymbol)
        XCTAssertNil(model.validationIssue(name: "Work", systemImage: "folder"))
    }

    @MainActor
    func testResolvesTildeAndRelativePathsAndRejectsFiles() async throws {
        let model = WorkspaceShortcutsModel(defaults: defaults, homeDirectory: home)
        let file = home.appendingPathComponent("note.txt")
        try Data("x".utf8).write(to: file)

        let relative = try await model.resolvedPath(for: "Code")
        XCTAssertEqual(relative, home.appendingPathComponent("Code").standardizedFileURL.path)
        let homeRelative = try await model.resolvedPath(for: "~")
        XCTAssertEqual(homeRelative, FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path)

        do {
            _ = try await model.resolvedPath(for: file.path)
            XCTFail("A file must not be accepted as a workspace folder")
        } catch {
            XCTAssertEqual(error as? LocationError, .notDirectory)
        }
        do {
            _ = try await model.resolvedPath(for: home.appendingPathComponent("Missing").path)
            XCTFail("A missing folder must not be accepted")
        } catch {
            XCTAssertEqual(error as? LocationError, .unavailable)
        }
    }

    @MainActor
    func testMissingFoldersAreMarkedUnavailableUntilTheyReturn() async throws {
        let model = WorkspaceShortcutsModel(defaults: defaults, homeDirectory: home)
        let code = home.appendingPathComponent("Code", isDirectory: true)
        let codeID = try XCTUnwrap(model.shortcuts.last?.id)
        try await waitUntil { model.unavailableIDs.isEmpty }

        try FileManager.default.moveItem(at: code, to: home.appendingPathComponent("Moved", isDirectory: true))
        model.refreshAvailability()
        try await waitUntil { model.unavailableIDs == [codeID] }

        try FileManager.default.moveItem(at: home.appendingPathComponent("Moved", isDirectory: true), to: code)
        model.refreshAvailability()
        try await waitUntil { model.unavailableIDs.isEmpty }
    }

    @MainActor
    private func waitUntil(condition: () -> Bool) async throws {
        for _ in 0 ..< 200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for workspace availability")
    }
}
