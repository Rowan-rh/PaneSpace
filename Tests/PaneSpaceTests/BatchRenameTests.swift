import Foundation
import XCTest
@testable import PaneSpaceApp

final class BatchRenameTests: XCTestCase {
    private let folder = URL(fileURLWithPath: "/rename", isDirectory: true)

    private func urls(_ names: [String]) -> [URL] {
        names.map { folder.appendingPathComponent($0) }
    }

    func testRulesKeepExtensionsUnlessAskedAndHandleDotfiles() {
        let replace = BatchRenameRule.replace(find: "IMG", replacement: "Trip", ignoresCase: true, includesExtension: false)
        XCTAssertEqual(replace.newName(for: "img_01.jpg", at: 0), "Trip_01.jpg")
        XCTAssertEqual(
            BatchRenameRule.replace(find: "jpg", replacement: "jpeg", ignoresCase: false, includesExtension: false)
                .newName(for: "a.jpg", at: 0),
            "a.jpg"
        )
        XCTAssertEqual(
            BatchRenameRule.replace(find: "jpg", replacement: "jpeg", ignoresCase: false, includesExtension: true)
                .newName(for: "a.jpg", at: 0),
            "a.jpeg"
        )
        XCTAssertEqual(BatchRenameRule.add(prefix: "old-", suffix: "-v2").newName(for: ".gitignore", at: 0), "old-.gitignore-v2")
        XCTAssertEqual(BatchRenameRule.add(prefix: "", suffix: "_x").newName(for: "archive.tar.gz", at: 0), "archive.tar_x.gz")
        XCTAssertEqual(
            BatchRenameRule.format(base: "Photo", separator: " ", start: 9, digits: 3).newName(for: "x.png", at: 2),
            "Photo 011.png"
        )
    }

    func testPlanReportsDuplicatesExistingItemsAndInvalidNames() {
        let sources = urls(["a.txt", "b.txt", "c.txt"])
        let plan = BatchRenamePlan(
            sources: sources,
            rule: .format(base: "N", separator: "", start: 1, digits: 1),
            existingNames: ["a.txt", "b.txt", "c.txt", "n2.txt"]
        )
        XCTAssertEqual(plan.entries.map(\.newName), ["N1.txt", "N2.txt", "N3.txt"])
        XCTAssertEqual(plan.entries.map(\.issue), [nil, .existingItem, nil], "Conflicts ignore case")
        XCTAssertFalse(plan.canApply)

        let duplicate = BatchRenamePlan(
            sources: urls(["a.txt", "b.txt"]),
            rule: .replace(find: "a", replacement: "b", ignoresCase: false, includesExtension: false),
            existingNames: ["a.txt", "b.txt"]
        )
        XCTAssertEqual(duplicate.entries.map(\.issue), [.duplicateInBatch, .duplicateInBatch])

        let invalid = BatchRenamePlan(
            sources: urls(["a.txt"]),
            rule: .add(prefix: "x/", suffix: ""),
            existingNames: ["a.txt"]
        )
        XCTAssertEqual(invalid.entries.first?.issue, .invalidName)
    }

    func testSwappingNamesWithinTheBatchIsAllowed() {
        let plan = BatchRenamePlan(
            sources: urls(["one.txt", "two.txt"]),
            rule: .format(base: "x", separator: "", start: 1, digits: 1),
            existingNames: ["one.txt", "two.txt", "x3.txt"]
        )
        XCTAssertTrue(plan.canApply)
    }

    func testRenamerSwapsNamesAndCaseOnDisk() async throws {
        let directory = try makeDirectory(files: ["a.txt", "b.txt", "Case.txt"])
        defer { try? FileManager.default.removeItem(at: directory) }
        try "A".write(to: directory.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        // Swapping names and a case-only change both need the temporary first phase.
        let swap = BatchRenamePlanFixture.plan(
            directory: directory,
            renames: [("a.txt", "b.txt"), ("b.txt", "a.txt"), ("Case.txt", "case.txt")]
        )
        XCTAssertTrue(swap.canApply)
        let result = try await BatchRenamer(provider: LocalFileProvider()).apply(swap)
        XCTAssertEqual(result.count, 3)

        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        XCTAssertEqual(names, ["a.txt", "b.txt", "case.txt"])
        XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent("b.txt"), encoding: .utf8), "A")
    }

    func testRenamerRestoresOriginalNamesWhenAStepFails() async throws {
        let directory = try makeDirectory(files: ["a.txt", "b.txt"])
        defer { try? FileManager.default.removeItem(at: directory) }
        let plan = BatchRenamePlanFixture.plan(directory: directory, renames: [("a.txt", "one.txt"), ("b.txt", "two.txt")])
        let provider = FailingRenameProvider(failOnName: "two.txt")

        do {
            _ = try await BatchRenamer(provider: provider).apply(plan)
            XCTFail("Expected the rename to fail")
        } catch let failure as BatchRenamer.Failure {
            XCTAssertTrue(failure.unrecoveredItems.isEmpty)
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        XCTAssertEqual(names, ["a.txt", "b.txt"])
    }

    @MainActor
    func testPaneAppliesBatchRenameAndSelectsResults() async throws {
        let directory = try makeDirectory(files: ["a.txt", "b.txt", "folder"])
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = BrowserPaneModel(url: directory, provider: LocalFileProvider())
        try await waitForPane { !model.isLoading && model.items.count == 3 }

        let targets = model.visibleItems
        model.requestRename(targets)
        XCTAssertEqual(model.batchRenameRequest?.targets.count, 3)

        let plan = model.batchRenamePlan(for: targets, rule: .add(prefix: "new-", suffix: ""))
        model.applyBatchRename(plan)
        try await waitForPane { !model.isPerformingOperation && model.items.allSatisfy { $0.name.hasPrefix("new-") } }
        try await waitForPane { model.selectedItems.count == 3 }
        XCTAssertNil(model.operationErrorMessage)
    }

    private func makeDirectory(files: [String]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in files {
            if name.contains(".") {
                FileManager.default.createFile(atPath: directory.appendingPathComponent(name).path, contents: Data())
            } else {
                try FileManager.default.createDirectory(
                    at: directory.appendingPathComponent(name, isDirectory: true),
                    withIntermediateDirectories: false
                )
            }
        }
        return directory
    }
}

private enum BatchRenamePlanFixture {
    /// Builds a plan with explicit target names, which no single rule can express.
    static func plan(directory: URL, renames: [(String, String)]) -> BatchRenamePlan {
        BatchRenamePlan(entries: renames.map { original, newName in
            BatchRenameEntry(source: directory.appendingPathComponent(original), newName: newName, issue: nil)
        })
    }
}

/// Renames through the local provider but fails when asked for one specific final name.
private struct FailingRenameProvider: FileProviding {
    let failOnName: String
    private let local = LocalFileProvider()

    func contents(of directory: URL, showsHiddenFiles: Bool) async throws -> [FileItem] {
        try await local.contents(of: directory, showsHiddenFiles: showsHiddenFiles)
    }

    func createFolder(named name: String, in directory: URL) async throws -> URL {
        throw FileProviderError.operationFailed
    }

    func rename(_ item: URL, to newName: String) async throws -> URL {
        if newName == failOnName { throw FileProviderError.permissionDenied }
        return try await local.rename(item, to: newName)
    }

    func moveToTrash(_ item: URL) async throws -> URL? {
        throw FileProviderError.operationFailed
    }
}
