import XCTest
@testable import PaneSpaceApp

final class LocalPathResolverTests: XCTestCase {
    func testResolvesAbsoluteRelativeHomeAndFileURLPaths() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let child = root.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let resolver = LocalPathResolver()

        let absolute = try await resolver.resolve(child.path, relativeTo: root)
        let relative = try await resolver.resolve("Child", relativeTo: root)
        let fileURL = try await resolver.resolve(child.absoluteString, relativeTo: root)
        let home = try await resolver.resolve("~/", relativeTo: root)
        let expectedChild = child.standardizedFileURL
        XCTAssertEqual(absolute, expectedChild)
        XCTAssertEqual(relative, expectedChild)
        XCTAssertEqual(fileURL, expectedChild)
        XCTAssertEqual(home, FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL)
        let symlink = root.appendingPathComponent("Shortcut")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: child)
        let followed = try await resolver.resolve(symlink.path, relativeTo: root)
        XCTAssertEqual(followed, symlink.standardizedFileURL)
        let temporary = try await resolver.resolve("/tmp", relativeTo: root)
        XCTAssertEqual(temporary.path, "/tmp")
    }

    func testRejectsInvalidAndNonDirectoryLocations() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("note.txt")
        try Data().write(to: file)
        let resolver = LocalPathResolver()

        await XCTAssertThrowsErrorAsync(try await resolver.resolve("", relativeTo: root))
        await XCTAssertThrowsErrorAsync(try await resolver.resolve("https://example.com", relativeTo: root))
        await XCTAssertThrowsErrorAsync(try await resolver.resolve(file.path, relativeTo: root))
        await XCTAssertThrowsErrorAsync(try await resolver.resolve("missing", relativeTo: root))

        let blocked = root.appendingPathComponent("blocked", isDirectory: true)
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: blocked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: blocked.path) }
        await XCTAssertThrowsErrorAsync(try await resolver.resolve(blocked.path, relativeTo: root))
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error", file: file, line: line)
    } catch {}
}
