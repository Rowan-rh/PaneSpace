import Foundation
@testable import PaneSpaceApp

/// In-memory provider whose directory contents can be replaced between refreshes.
actor StaticDirectoryProvider: FileProviding {
    private var contentsByDirectory: [URL: [FileItem]]
    private(set) var trashedURLs: [URL] = []
    private var loadDelay: Duration = .zero

    init(_ contentsByDirectory: [URL: [FileItem]]) {
        self.contentsByDirectory = Dictionary(
            uniqueKeysWithValues: contentsByDirectory.map { ($0.key.standardizedFileURL, $0.value) }
        )
    }

    func setContents(_ items: [FileItem]?, of directory: URL) {
        contentsByDirectory[directory.standardizedFileURL] = items
    }

    func setLoadDelay(_ delay: Duration) {
        loadDelay = delay
    }

    func contents(of directory: URL, showsHiddenFiles: Bool) async throws -> [FileItem] {
        if loadDelay > .zero {
            try await Task.sleep(for: loadDelay)
        }
        guard let items = contentsByDirectory[directory.standardizedFileURL] else {
            throw FileProviderError.itemUnavailable
        }
        return items
    }

    func createFolder(named name: String, in directory: URL) throws -> URL {
        throw FileProviderError.operationFailed
    }

    func rename(_ item: URL, to newName: String) throws -> URL {
        throw FileProviderError.operationFailed
    }

    func moveToTrash(_ item: URL) -> URL? {
        trashedURLs.append(item)
        for (directory, items) in contentsByDirectory {
            contentsByDirectory[directory] = items.filter { $0.url != item }
        }
        return nil
    }
}

extension FileItem {
    static func stub(
        _ name: String,
        in directory: URL,
        folder: Bool = false,
        package: Bool = false
    ) -> FileItem {
        FileItem(
            url: directory.appendingPathComponent(name, isDirectory: folder || package),
            isDirectory: folder || package,
            isHidden: false,
            fileSize: folder || package ? nil : 1,
            modificationDate: nil,
            kind: "Item",
            isPackage: package
        )
    }
}

@MainActor
func waitForPane(
    timeoutIterations: Int = 200,
    condition: () -> Bool
) async throws {
    for _ in 0 ..< timeoutIterations {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw PaneWaitTimeout()
}

struct PaneWaitTimeout: Error {}
