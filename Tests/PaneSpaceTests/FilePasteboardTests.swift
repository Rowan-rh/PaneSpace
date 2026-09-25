import AppKit
import Foundation
import XCTest
@testable import PaneSpaceApp

final class FilePasteboardTests: XCTestCase {
    @MainActor
    func testRoundTripsFileURLsAndIgnoresOtherContent() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let filePasteboard = FilePasteboard(pasteboard: pasteboard)
        let root = URL(fileURLWithPath: "/pasteboard", isDirectory: true)

        XCTAssertTrue(filePasteboard.write([
            root.appendingPathComponent("a.txt"),
            root.appendingPathComponent("b.txt")
        ]))
        XCTAssertEqual(filePasteboard.fileURLs().map(\.lastPathComponent), ["a.txt", "b.txt"])

        pasteboard.clearContents()
        pasteboard.setString(root.path, forType: .string)
        XCTAssertTrue(filePasteboard.fileURLs().isEmpty)
        let webURL = try XCTUnwrap(URL(string: "https://example.com"))
        XCTAssertFalse(filePasteboard.write([webURL]))
    }

    @MainActor
    func testCopiesSelectionAndPastesIntoAnotherPane() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDirectory = root.appendingPathComponent("Source", isDirectory: true)
        let destinationDirectory = root.appendingPathComponent("Destination", isDirectory: true)
        for directory in [sourceDirectory, destinationDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let source = sourceDirectory.appendingPathComponent("report.txt")
        try Data("report".utf8).write(to: source)

        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let history = OperationHistoryModel(store: OperationHistoryStore(fileURL: root.appendingPathComponent("history.json")))
        let suiteName = "PaneSpaceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(
            defaults: defaults,
            operationHistory: history,
            filePasteboard: FilePasteboard(pasteboard: pasteboard)
        )
        model.paneLayout = .twoColumns
        model.primaryPane.navigate(to: sourceDirectory)
        model.secondaryPane.navigate(to: destinationDirectory)
        try await waitForPane {
            !model.primaryPane.isLoading && model.primaryPane.items.map(\.name) == ["report.txt"]
        }

        XCTAssertFalse(model.copySelectionToPasteboard(from: .primary))
        model.primaryPane.selection = Set(model.primaryPane.items.map(\.id))
        XCTAssertTrue(model.copySelectionToPasteboard(from: .primary))
        XCTAssertTrue(model.pasteFromPasteboard(into: .secondary))

        try await waitForPane(timeoutIterations: 500) {
            model.transferQueue.jobs.first.map { [.completed, .failed].contains($0.state) } ?? false
        }
        XCTAssertEqual(model.transferQueue.jobs.first?.state, .completed)
        let pasted = destinationDirectory.appendingPathComponent("report.txt")
        XCTAssertEqual(try String(contentsOf: pasted, encoding: .utf8), "report")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
}
