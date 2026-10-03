import AppKit
import Foundation
import XCTest
@testable import PaneSpaceApp

/// Records what the launcher was asked to do instead of starting an application. Every launch in
/// this suite goes through it, so no test can accidentally open Otty or Terminal for real.
@MainActor
private final class RecordingLauncher: ApplicationLaunching {
    private var installedApplications: [String: URL] = [:]
    private(set) var openedDirectories: [URL] = []
    private(set) var openedWithApplications: [URL] = []
    private(set) var lookupOrder: [String] = []
    private var acceptsLaunch = true
    /// When true the completion handler is held back until `completeHeldLaunch` runs, so a test can
    /// look at the pane while a launch is still in flight.
    private var holdsCompletion = false
    private var pendingCompletion: (@MainActor (Bool) -> Void)?

    func install(_ application: String, bundleIdentifier: String) {
        installedApplications[bundleIdentifier] = URL(fileURLWithPath: "/Applications/\(application).app")
    }

    /// Makes the launch be refused, the way an application that cannot start is.
    func refuseLaunch() {
        acceptsLaunch = false
    }

    func holdLaunchCompletion() {
        holdsCompletion = true
    }

    func completeHeldLaunch(succeeded: Bool) {
        let completion = pendingCompletion
        pendingCompletion = nil
        holdsCompletion = false
        completion?(succeeded)
    }

    func applicationURL(forBundleIdentifier identifier: String) -> URL? {
        lookupOrder.append(identifier)
        return installedApplications[identifier]
    }

    func open(
        _ url: URL,
        withApplicationAt applicationURL: URL,
        configuration: NSWorkspace.OpenConfiguration,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        if acceptsLaunch {
            openedDirectories.append(url)
            openedWithApplications.append(applicationURL)
        }
        if holdsCompletion {
            pendingCompletion = completion
        } else {
            completion(acceptsLaunch)
        }
    }

    var lastOpenedDirectory: URL? { openedDirectories.last }
    var lastApplication: URL? { openedWithApplications.last }
}

/// An empty scratch directory for one test, removed when the test ends.
@MainActor
private func makeScratchDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Lets a completion handler that is already scheduled run.
@MainActor
private func settleCompletion() async {
    await Task.yield()
    await Task.yield()
}

@MainActor
final class TerminalLauncherTests: XCTestCase {
    private var directory = URL(fileURLWithPath: "/", isDirectory: true)
    private let launcher = RecordingLauncher()

    /// The scratch directory is made per test rather than in a fixture override, because XCTest
    /// calls those off the main actor.
    override func setUp() async throws {
        directory = makeScratchDirectory()
        launcher.install("Otty", bundleIdentifier: TerminalLauncher.preferredBundleIdentifier)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Runs `open` and returns the identifier it reported, or nil when it reported a failure.
    private func openAndWait(_ terminalLauncher: TerminalLauncher) async -> String?? {
        var reported: String?
        var didReport = false
        terminalLauncher.open(directory) { identifier in
            reported = identifier
            didReport = true
        }
        await settleCompletion()
        return didReport ? reported : nil
    }

    func testPrefersOttyWhenItIsInstalled() async {
        launcher.install("Terminal", bundleIdentifier: TerminalLauncher.fallbackBundleIdentifier)

        let reported = await openAndWait(TerminalLauncher(launcher: launcher))

        XCTAssertEqual(reported ?? nil, TerminalLauncher.preferredBundleIdentifier)
        XCTAssertEqual(launcher.lastOpenedDirectory, directory)
        XCTAssertEqual(launcher.lastApplication?.lastPathComponent, "Otty.app")
    }

    func testFallsBackToTerminalWhenOttyIsMissing() async {
        let terminalOnly = RecordingLauncher()
        terminalOnly.install("Terminal", bundleIdentifier: TerminalLauncher.fallbackBundleIdentifier)

        let reported = await openAndWait(TerminalLauncher(launcher: terminalOnly))

        XCTAssertEqual(reported ?? nil, TerminalLauncher.fallbackBundleIdentifier)
        XCTAssertEqual(terminalOnly.lastOpenedDirectory, directory)
        XCTAssertEqual(terminalOnly.lastApplication?.lastPathComponent, "Terminal.app")
    }

    /// Otty is asked for first even when it turns out to be absent, so a missing preference costs
    /// one lookup rather than changing the order.
    func testChecksThePreferredTerminalBeforeTheFallback() async {
        let terminalOnly = RecordingLauncher()
        terminalOnly.install("Terminal", bundleIdentifier: TerminalLauncher.fallbackBundleIdentifier)

        _ = await openAndWait(TerminalLauncher(launcher: terminalOnly))

        XCTAssertEqual(terminalOnly.lookupOrder, TerminalLauncher.bundleIdentifiers)
    }

    func testReportsWhenNoTerminalIsInstalled() async {
        let reported = await openAndWait(TerminalLauncher(launcher: RecordingLauncher()))

        XCTAssertNil(reported ?? nil)
    }

    func testLooksUpEveryCandidateBeforeGivingUp() async {
        let empty = RecordingLauncher()

        _ = await openAndWait(TerminalLauncher(launcher: empty))

        XCTAssertEqual(empty.lookupOrder, TerminalLauncher.bundleIdentifiers)
        XCTAssertTrue(empty.openedDirectories.isEmpty)
    }

    /// A refused launch is the only failure signal `NSWorkspace` gives, and it must not be reported
    /// to the user as success.
    func testReportsARefusedLaunch() async {
        launcher.refuseLaunch()

        let reported = await openAndWait(TerminalLauncher(launcher: launcher))

        XCTAssertNil(reported ?? nil)
        XCTAssertTrue(launcher.openedDirectories.isEmpty)
    }

    func testAvailableTerminalIsNilWithoutAnyTerminal() {
        let empty = TerminalLauncher(launcher: RecordingLauncher())

        XCTAssertNil(empty.availableTerminal())
        XCTAssertNil(empty.availableTerminalIdentifier())
    }

    func testAvailableTerminalIsOttyWhenBothAreInstalled() {
        launcher.install("Terminal", bundleIdentifier: TerminalLauncher.fallbackBundleIdentifier)
        let terminalLauncher = TerminalLauncher(launcher: launcher)

        XCTAssertEqual(terminalLauncher.availableTerminalIdentifier(), TerminalLauncher.preferredBundleIdentifier)
        XCTAssertEqual(terminalLauncher.availableTerminal()?.application.lastPathComponent, "Otty.app")
    }
}

@MainActor
final class OpenDirectoryInTerminalPaneTests: XCTestCase {
    private var directory = URL(fileURLWithPath: "/", isDirectory: true)
    private let launcher = RecordingLauncher()

    override func setUp() async throws {
        directory = makeScratchDirectory()
        launcher.install("Otty", bundleIdentifier: TerminalLauncher.preferredBundleIdentifier)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeModel(launcher: RecordingLauncher) -> BrowserPaneModel {
        BrowserPaneModel(
            url: directory,
            provider: LocalFileProvider(),
            terminalLauncher: TerminalLauncher(launcher: launcher)
        )
    }

    func testOpensTheDirectoryThePaneShows() async throws {
        let model = makeModel(launcher: launcher)
        try await waitForPane { !model.isLoading }

        model.openInTerminal()
        await settleCompletion()

        XCTAssertEqual(launcher.lastOpenedDirectory?.standardizedFileURL, directory.standardizedFileURL)
        XCTAssertEqual(launcher.lastApplication?.lastPathComponent, "Otty.app")
        XCTAssertNil(model.operationErrorMessage)
    }

    func testFollowsThePaneWhenItNavigatesElsewhere() async throws {
        let child = directory.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
        let model = makeModel(launcher: launcher)
        try await waitForPane { !model.isLoading }

        model.navigate(to: child)
        try await waitForPane { !model.isLoading && model.currentURL == child }
        model.openInTerminal()
        await settleCompletion()

        XCTAssertEqual(launcher.lastOpenedDirectory?.standardizedFileURL, child.standardizedFileURL)
    }

    /// The command targets what the pane shows, not the selection: opening a terminal somewhere the
    /// user cannot see would be worse than not offering the command at all.
    func testTargetsTheCurrentDirectoryEvenWhenSomethingIsSelected() async throws {
        let file = directory.appendingPathComponent("file.txt")
        try Data("x".utf8).write(to: file)
        let model = makeModel(launcher: launcher)
        try await waitForPane { !model.isLoading }
        // Selection goes through the pane's own API so the ids are the ones the listing produced.
        model.selectAllVisibleItems()
        XCTAssertEqual(model.selectedItems.count, 1)
        XCTAssertNotEqual(model.selectedItems.first?.url.standardizedFileURL, directory.standardizedFileURL)

        model.openInTerminal()
        await settleCompletion()

        XCTAssertEqual(launcher.lastOpenedDirectory?.standardizedFileURL, directory.standardizedFileURL)
    }

    func testReportsADirectoryThatNoLongerExists() async throws {
        let model = makeModel(launcher: launcher)
        try await waitForPane { !model.isLoading }
        try FileManager.default.removeItem(at: directory)

        model.openInTerminal()
        await settleCompletion()

        XCTAssertTrue(launcher.openedDirectories.isEmpty, "No terminal may be launched for a folder that is gone")
        XCTAssertEqual(
            model.operationErrorMessage,
            TerminalLauncherError.directoryUnavailable.localizedDescription
        )
    }

    func testReportsWhenNoTerminalIsInstalled() async throws {
        let empty = RecordingLauncher()
        let model = makeModel(launcher: empty)
        try await waitForPane { !model.isLoading }

        model.openInTerminal()
        await settleCompletion()

        XCTAssertTrue(empty.openedDirectories.isEmpty)
        XCTAssertEqual(
            model.operationErrorMessage,
            TerminalLauncherError.noTerminalAvailable.localizedDescription
        )
    }

    /// A launch that cannot start must leave the user with a message, not a silent no-op.
    func testReportsARefusedLaunch() async throws {
        launcher.refuseLaunch()
        let model = makeModel(launcher: launcher)
        try await waitForPane { !model.isLoading }

        model.openInTerminal()
        await settleCompletion()

        XCTAssertEqual(
            model.operationErrorMessage,
            TerminalLauncherError.launchFailed.localizedDescription
        )
    }

    /// An earlier error must not linger once a later command succeeds.
    func testClearsAPreviousErrorAfterASuccessfulOpen() async throws {
        let model = makeModel(launcher: launcher)
        try await waitForPane { !model.isLoading }
        model.operationErrorMessage = "earlier failure"
        XCTAssertNotNil(model.operationErrorMessage)

        model.openInTerminal()
        await settleCompletion()

        XCTAssertNil(model.operationErrorMessage)
    }

    /// A launch that is still in flight must not be reported as either success or failure.
    func testReportsNothingWhileTheLaunchIsStillInFlight() async throws {
        launcher.refuseLaunch()
        launcher.holdLaunchCompletion()
        let model = makeModel(launcher: launcher)
        try await waitForPane { !model.isLoading }

        model.openInTerminal()
        await settleCompletion()
        XCTAssertNil(model.operationErrorMessage)

        launcher.completeHeldLaunch(succeeded: false)
        await settleCompletion()
        XCTAssertEqual(
            model.operationErrorMessage,
            TerminalLauncherError.launchFailed.localizedDescription
        )
    }

    /// A context menu in the column browser opens the column the user clicked, not the deepest
    /// column the address bar happens to show.
    func testOpensTheDirectoryItIsGivenRatherThanTheOneOnScreen() async throws {
        let child = directory.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
        let model = makeModel(launcher: launcher)
        try await waitForPane { !model.isLoading }
        model.navigate(to: child)
        try await waitForPane { !model.isLoading && model.currentURL == child }

        model.openInTerminal(directory)
        await settleCompletion()

        XCTAssertEqual(launcher.lastOpenedDirectory?.standardizedFileURL, directory.standardizedFileURL)
        XCTAssertNil(model.operationErrorMessage)
    }

    /// Passing nil must keep the previous behavior of opening what the pane shows.
    func testFallsBackToTheDirectoryOnScreen() async throws {
        let child = directory.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
        let model = makeModel(launcher: launcher)
        try await waitForPane { !model.isLoading }
        model.navigate(to: child)
        try await waitForPane { !model.isLoading && model.currentURL == child }

        model.openInTerminal(nil)
        await settleCompletion()

        XCTAssertEqual(launcher.lastOpenedDirectory?.standardizedFileURL, child.standardizedFileURL)
    }

    func testReportsARequestedDirectoryThatDoesNotExist() async throws {
        let missing = directory.appendingPathComponent("Gone", isDirectory: true)
        let model = makeModel(launcher: launcher)
        try await waitForPane { !model.isLoading }

        model.openInTerminal(missing)
        await settleCompletion()

        XCTAssertTrue(launcher.openedDirectories.isEmpty, "No terminal may be launched for a folder that is gone")
        XCTAssertEqual(
            model.operationErrorMessage,
            TerminalLauncherError.directoryUnavailable.localizedDescription
        )
    }
}
