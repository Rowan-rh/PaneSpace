import Foundation
import XCTest
@testable import PaneSpaceApp

final class LocalFileProviderTests: XCTestCase {
    private var temporaryDirectory: URL!
    private let provider = LocalFileProvider()

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testCreatesAndListsFolder() async throws {
        let created = try await provider.createFolder(named: "Projects", in: temporaryDirectory)
        let items = try await provider.contents(of: temporaryDirectory, showsHiddenFiles: false)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(
            items.first?.url.resolvingSymlinksInPath(),
            created.resolvingSymlinksInPath()
        )
        XCTAssertEqual(items.first?.isDirectory, true)
    }

    func testMarksApplicationBundlesAsPackagesInsteadOfFolders() async throws {
        let application = temporaryDirectory.appendingPathComponent("Tool.app", isDirectory: true)
        try FileManager.default.createDirectory(
            at: application.appendingPathComponent("Contents", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: temporaryDirectory.appendingPathComponent("Plain", isDirectory: true),
            withIntermediateDirectories: true
        )

        let items = try await provider.contents(of: temporaryDirectory, showsHiddenFiles: false)
        let package = try XCTUnwrap(items.first { $0.name == "Tool.app" })
        let folder = try XCTUnwrap(items.first { $0.name == "Plain" })

        XCTAssertTrue(package.isDirectory)
        XCTAssertTrue(package.isPackage)
        XCTAssertFalse(package.isFolder)
        XCTAssertFalse(folder.isPackage)
        XCTAssertTrue(folder.isFolder)
    }

    func testRenamesItem() async throws {
        let original = temporaryDirectory.appendingPathComponent("before.txt")
        try Data("hello".utf8).write(to: original)

        let renamed = try await provider.rename(original, to: "after.txt")

        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))
    }

    func testRejectsInvalidNames() async throws {
        for name in ["bad/name", ".", "..", "\0"] {
            do {
                _ = try await provider.createFolder(named: name, in: temporaryDirectory)
                XCTFail("Expected invalid name: \(name)")
            } catch let error as FileProviderError {
                XCTAssertEqual(error, .invalidName)
            }
        }
    }

    func testNormalizesNameConflicts() async throws {
        _ = try await provider.createFolder(named: "Projects", in: temporaryDirectory)

        do {
            _ = try await provider.createFolder(named: "Projects", in: temporaryDirectory)
            XCTFail("Expected a name conflict")
        } catch let error as FileProviderError {
            XCTAssertEqual(error, .itemAlreadyExists)
        }
    }
}
