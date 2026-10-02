import Foundation
import XCTest
@testable import PaneSpaceApp

/// Covers the two commands that take the folder they act on as a parameter: creating a folder and
/// opening one in a terminal. Both exist because a context menu in the column browser has to act on
/// the column the user clicked, which is not always the folder the pane is showing.
@MainActor
final class NewFolderInDirectoryTests: XCTestCase {
    private var root = URL(fileURLWithPath: "/", isDirectory: true)
    private var storedViewMode: String?

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        storedViewMode = UserDefaults.standard.string(forKey: "defaultViewMode")
    }

    override func tearDown() async throws {
        // `setViewMode` records the choice in the shared defaults, so leaving it behind would make
        // unrelated tests start in the column browser.
        if let storedViewMode {
            UserDefaults.standard.set(storedViewMode, forKey: "defaultViewMode")
        } else {
            UserDefaults.standard.removeObject(forKey: "defaultViewMode")
        }
        try? FileManager.default.removeItem(at: root)
    }

    private func makeChild(_ name: String) throws -> URL {
        let child = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
        return child
    }

    // MARK: - Creating a folder in a given directory

    /// The column browser asks for the clicked column's folder, which is not the folder the address
    /// bar shows once more than one column is open.
    func testCreatesTheFolderInTheRequestedDirectory() async throws {
        let target = try makeChild("Target")
        let other = try makeChild("Other")
        let model = BrowserPaneModel(url: other, provider: LocalFileProvider())
        try await waitForPane { !model.isLoading }

        model.createFolder(named: "Projects", in: target)
        try await waitForPane { !model.isPerformingOperation }

        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("Projects").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: other.appendingPathComponent("Projects").path))
        // A pane showing another folder cannot select this one, and must not pretend to: the
        // selection would be invisible to every action that reads it.
        XCTAssertTrue(model.selectedItems.isEmpty)
        XCTAssertNil(model.operationErrorMessage)
    }

    /// In the column browser the clicked column is part of what the pane shows, so the new folder is
    /// selected there and the user can rename it straight away.
    func testSelectsTheNewFolderInTheColumnItWasCreatedIn() async throws {
        let parent = try makeChild("Parent")
        let target = parent.appendingPathComponent("Target", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        let model = BrowserPaneModel(url: parent, provider: LocalFileProvider())
        try await waitForPane { !model.isLoading && model.items.count == 1 }
        // A column browser only keeps columns that form a parent-to-child chain, so the pane is
        // driven through its own API rather than by writing column state by hand.
        model.setViewMode(.columns)
        let targetItem = try XCTUnwrap(model.items.first { $0.name == "Target" })
        model.selectColumnItem(targetItem, in: try XCTUnwrap(model.columns.first?.id))
        try await waitForPane { model.columns.count == 2 && model.columns.last?.isLoading == false }

        model.createFolder(named: "Projects", in: target)
        try await waitForPane { !model.isPerformingOperation }
        // The refresh that shows the new folder is what makes it selectable, so wait for it.
        try await waitForPane {
            model.columns.last?.items.contains { $0.name == "Projects" } == true
        }

        XCTAssertEqual(model.columns.last?.directory.standardizedFileURL, target.standardizedFileURL)
        XCTAssertEqual(model.selectedItems.map(\.name), ["Projects"])
        XCTAssertNil(model.operationErrorMessage)
    }

    /// Passing nil keeps the previous behavior: the folder the pane shows.
    func testCreatesTheFolderInTheDirectoryOnScreenWhenNoneIsGiven() async throws {
        let shown = try makeChild("Shown")
        let model = BrowserPaneModel(url: shown, provider: LocalFileProvider())
        try await waitForPane { !model.isLoading }

        model.createFolder(named: "Projects", in: nil)
        try await waitForPane { !model.isPerformingOperation }

        XCTAssertTrue(FileManager.default.fileExists(atPath: shown.appendingPathComponent("Projects").path))
    }

    /// A refused creation must reach the user and leave nothing half-done behind.
    func testReportsAFolderThatCannotBeCreated() async throws {
        let model = BrowserPaneModel(url: root, provider: LocalFileProvider())
        try await waitForPane { !model.isLoading }

        model.createFolder(named: "bad/name", in: root)
        try await waitForPane { !model.isPerformingOperation }

        XCTAssertEqual(model.operationErrorMessage, FileProviderError.invalidName.localizedDescription)
    }

    /// A second request while one is in flight is dropped rather than queued, so the operation
    /// state stays a single readable value.
    func testIgnoresASecondRequestWhileOneIsRunning() async throws {
        let slowProvider = SlowCreateProvider()
        let model = BrowserPaneModel(url: root, provider: slowProvider)
        try await waitForPane { !model.isLoading }

        model.createFolder(named: "First", in: root)
        XCTAssertTrue(model.isPerformingOperation)
        model.createFolder(named: "Second", in: root)
        try await waitForPane { !model.isPerformingOperation }

        let created = await slowProvider.recordedNames()
        XCTAssertEqual(created, ["First"])
    }

    // MARK: - The pending target held by AppModel

    /// The naming sheet is presented by a view that only knows `AppModel`, so the target is held
    /// there between the request and the sheet's submit.
    func testRequestHoldsTheTargetForTheNamingSheet() throws {
        let (model, suiteName) = try makeAppModel()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let target = try makeChild("Target")

        model.requestNewFolder(in: target)
        XCTAssertTrue(model.isCreatingFolder)

        XCTAssertEqual(model.takePendingNewFolderDirectory()?.standardizedFileURL, target.standardizedFileURL)
        // Taking it clears it, so a second submit cannot reuse a stale target.
        XCTAssertNil(model.takePendingNewFolderDirectory())
    }

    /// A request without a folder leaves the pane to use its own current folder.
    func testRequestWithoutAFolderHoldsNothing() throws {
        let (model, suiteName) = try makeAppModel()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        model.requestNewFolder()

        XCTAssertTrue(model.isCreatingFolder)
        XCTAssertNil(model.takePendingNewFolderDirectory())
    }

    /// Cancelling the sheet must not leave the previous target behind for the next command.
    func testALaterRequestReplacesTheHeldTarget() throws {
        let (model, suiteName) = try makeAppModel()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let first = try makeChild("First")
        let second = try makeChild("Second")

        model.requestNewFolder(in: first)
        _ = model.takePendingNewFolderDirectory()
        model.requestNewFolder(in: second)

        XCTAssertEqual(model.takePendingNewFolderDirectory()?.standardizedFileURL, second.standardizedFileURL)
    }

    private func makeAppModel(layout: PaneLayout = .single) throws -> (AppModel, String) {
        let suiteName = "PaneSpaceTests.NewFolder.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(false, forKey: "restoreLastSession")
        defaults.set(layout.rawValue, forKey: "defaultPaneLayout")
        return (AppModel(defaults: defaults), suiteName)
    }

    // MARK: - Acting on the pane the command came from

    /// A context menu on a pane does not make that pane active, because the pane only switches on a
    /// left click. Without naming the source pane, creating from the right-hand pane's empty area
    /// would create the folder in the left-hand pane and record the operation against it.
    func testCreatingFromAnInactivePaneTargetsThatPane() async throws {
        let (model, suiteName) = try makeAppModel(layout: .twoColumns)
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let left = try makeChild("Left")
        let right = try makeChild("Right")
        model.primaryPane.navigate(to: left)
        model.secondaryPane.navigate(to: right)
        model.activePane = .primary
        try await waitForPane { !model.primaryPane.isLoading && !model.secondaryPane.isLoading }
        XCTAssertEqual(model.activePane, .primary)

        // The command arrives from the right-hand pane, which is not the active one.
        model.requestNewFolder(from: .secondary)
        XCTAssertEqual(model.activePane, .secondary, "The pane the command came from has to become active")

        // The naming sheet creates against the active pane, using the held target.
        model.activePaneModel.createFolder(
            named: "Projects",
            in: model.takePendingNewFolderDirectory()
        )
        try await waitForPane { !model.secondaryPane.isPerformingOperation }

        XCTAssertTrue(FileManager.default.fileExists(atPath: right.appendingPathComponent("Projects").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: left.appendingPathComponent("Projects").path))
    }

    /// Naming the source pane must not disturb a request that already came from the active one.
    func testRequestFromTheActivePaneLeavesItActive() throws {
        let (model, suiteName) = try makeAppModel(layout: .twoColumns)
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let target = try makeChild("Target")
        model.activePane = .secondary

        model.requestNewFolder(in: target, from: .secondary)

        XCTAssertEqual(model.activePane, .secondary)
        XCTAssertEqual(model.takePendingNewFolderDirectory()?.standardizedFileURL, target.standardizedFileURL)
    }

    /// A request with no source pane keeps the existing behavior, so menu items that are not tied to
    /// a pane keep working unchanged.
    func testRequestWithoutASourcePaneLeavesTheActivePaneAlone() throws {
        let (model, suiteName) = try makeAppModel(layout: .twoColumns)
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        model.activePane = .secondary

        model.requestNewFolder()

        XCTAssertEqual(model.activePane, .secondary)
        XCTAssertTrue(model.isCreatingFolder)
    }
}

/// A provider whose creation is slow enough for a second request to arrive while one is running.
private actor SlowCreateProvider: FileProviding {
    private var createdNames: [String] = []

    init() {}

    /// Read through an accessor so the assertion stays on the test's actor.
    func recordedNames() -> [String] { createdNames }

    func contents(of directory: URL, showsHiddenFiles: Bool) async throws -> [FileItem] {
        try await LocalFileProvider().contents(of: directory, showsHiddenFiles: showsHiddenFiles)
    }

    func createFolder(named name: String, in directory: URL) async throws -> URL {
        try await Task.sleep(for: .milliseconds(80))
        let created = try await LocalFileProvider().createFolder(named: name, in: directory)
        createdNames.append(name)
        return created
    }

    func rename(_ item: URL, to newName: String) async throws -> URL {
        try await LocalFileProvider().rename(item, to: newName)
    }

    func moveToTrash(_ item: URL) async throws -> URL? {
        try await LocalFileProvider().moveToTrash(item)
    }
}
