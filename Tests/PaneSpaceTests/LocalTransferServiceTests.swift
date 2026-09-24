import Darwin
import Foundation
import XCTest
@testable import PaneSpaceApp

final class LocalTransferServiceTests: XCTestCase {
    func testCopyPreservesMetadataAndDoesNotFollowDirectorySymlinks() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent("Destination", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let file = source.appendingPathComponent("note.txt")
        try Data("hello".utf8).write(to: file)
        let timestamp = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes([.modificationDate: timestamp], ofItemAtPath: file.path)
        let attribute = Array("preserved".utf8)
        let setResult = attribute.withUnsafeBytes {
            setxattr(file.path, "com.panespace.transfer-test", $0.baseAddress, attribute.count, 0, 0)
        }
        XCTAssertEqual(setResult, 0)
        try FileManager.default.createSymbolicLink(
            at: source.appendingPathComponent("loop"),
            withDestinationURL: source
        )

        let service = LocalTransferService()
        let transferred = try await service.transfer(
            source: source,
            to: destination,
            kind: .copy,
            conflictDecision: nil
        )
        let copied = try XCTUnwrap(transferred)

        let copiedFile = copied.appendingPathComponent("note.txt")
        XCTAssertEqual(try Data(contentsOf: copiedFile), Data("hello".utf8))
        let copiedDate = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: copiedFile.path)[.modificationDate] as? Date)
        XCTAssertEqual(copiedDate.timeIntervalSince1970, timestamp.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(getxattr(copiedFile.path, "com.panespace.transfer-test", nil, 0, 0, 0), attribute.count)
        let linkValues = try copied.appendingPathComponent("loop").resourceValues(forKeys: [.isSymbolicLinkKey])
        XCTAssertEqual(linkValues.isSymbolicLink, true)
    }

    func testRejectsDestinationInsideSource() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let nested = source.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let service = LocalTransferService()
        do {
            _ = try await service.transfer(source: source, to: nested, kind: .copy, conflictDecision: nil)
            XCTFail("Expected invalid destination")
        } catch LocalTransferError.invalidDestination {
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: nested.path), [])
        }

        let nestedAlias = root.appendingPathComponent("NestedAlias")
        try FileManager.default.createSymbolicLink(at: nestedAlias, withDestinationURL: nested)
        do {
            _ = try await service.transfer(source: source, to: nestedAlias, kind: .copy, conflictDecision: nil)
            XCTFail("Expected symlinked nested destination to be rejected")
        } catch LocalTransferError.invalidDestination {
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: nested.path), [])
        }

        let rootAlias = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: rootAlias) }
        try FileManager.default.createSymbolicLink(at: rootAlias, withDestinationURL: root)
        do {
            _ = try await service.transfer(source: source, to: rootAlias, kind: .move, conflictDecision: .replace)
            XCTFail("Expected aliased source directory to be rejected")
        } catch LocalTransferError.invalidDestination {
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        }
    }

    func testReplaceMovesExistingDestinationToRecoverableTrash() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDirectory = root.appendingPathComponent("Source", isDirectory: true)
        let destinationDirectory = root.appendingPathComponent("Destination", isDirectory: true)
        let testTrash = root.appendingPathComponent("TestTrash", isDirectory: true)
        for directory in [sourceDirectory, destinationDirectory, testTrash] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let source = sourceDirectory.appendingPathComponent("same.txt")
        let existing = destinationDirectory.appendingPathComponent("same.txt")
        try Data("new".utf8).write(to: source)
        try Data("old".utf8).write(to: existing)
        let service = LocalTransferService(trashItem: { url in
            try FileManager.default.moveItem(at: url, to: testTrash.appendingPathComponent(url.lastPathComponent))
        })

        _ = try await service.transfer(source: source, to: destinationDirectory, kind: .copy, conflictDecision: .replace)

        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "new")
        XCTAssertEqual(try String(contentsOf: testTrash.appendingPathComponent("same.txt"), encoding: .utf8), "old")
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "new")
    }

    func testReadOnlyDestinationFailsBeforeStaging() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceDirectory = root.appendingPathComponent("Source", isDirectory: true)
        let readOnly = root.appendingPathComponent("Locked Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: readOnly, withIntermediateDirectories: true)
        let source = sourceDirectory.appendingPathComponent("note.txt")
        try Data("note".utf8).write(to: source)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readOnly.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: readOnly.path)
            try? FileManager.default.removeItem(at: root)
        }

        let service = LocalTransferService()
        do {
            _ = try await service.transfer(source: source, to: readOnly, kind: .move, conflictDecision: nil)
            XCTFail("Expected the read-only destination to be rejected")
        } catch let LocalTransferError.destinationNotWritable(name) {
            XCTAssertEqual(name, "Locked Folder")
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: readOnly.path), [])
    }

    func testFailureRemovesPartialStagingItem() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("Destination", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.txt")
        try Data("source".utf8).write(to: source)
        let service = LocalTransferService(copyItem: { _, staging in
            try Data("partial".utf8).write(to: staging)
            throw CocoaError(.fileReadCorruptFile)
        })

        do {
            _ = try await service.transfer(source: source, to: destination, kind: .copy, conflictDecision: nil)
            XCTFail("Expected copy failure")
        } catch {
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path), [])
        }
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
