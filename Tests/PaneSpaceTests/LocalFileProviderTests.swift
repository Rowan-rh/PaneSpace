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

    func testCreatesAndListsFolder() throws {
        let created = try provider.createFolder(named: "Projects", in: temporaryDirectory)
        let items = try provider.contents(of: temporaryDirectory, showsHiddenFiles: false)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(
            items.first?.url.resolvingSymlinksInPath(),
            created.resolvingSymlinksInPath()
        )
        XCTAssertEqual(items.first?.isDirectory, true)
    }

    func testRenamesItem() throws {
        let original = temporaryDirectory.appendingPathComponent("before.txt")
        try Data("hello".utf8).write(to: original)

        let renamed = try provider.rename(original, to: "after.txt")

        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))
    }

    func testRejectsInvalidNames() throws {
        XCTAssertThrowsError(try provider.createFolder(named: "bad/name", in: temporaryDirectory))
    }
}
