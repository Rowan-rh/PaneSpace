import Foundation

protocol FileProviding: Sendable {
    func contents(of directory: URL, showsHiddenFiles: Bool) throws -> [FileItem]
    func createFolder(named name: String, in directory: URL) throws -> URL
    func rename(_ item: URL, to newName: String) throws -> URL
    func moveToTrash(_ item: URL) throws
}

// FileManager documents its methods as safe to call from multiple threads. The instance is
// immutable here, so the provider can cross the task boundary used for directory loading.
struct LocalFileProvider: FileProviding, @unchecked Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func contents(of directory: URL, showsHiddenFiles: Bool) throws -> [FileItem] {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isHiddenKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .localizedTypeDescriptionKey
        ]

        let options: FileManager.DirectoryEnumerationOptions = showsHiddenFiles ? [] : [.skipsHiddenFiles]
        return try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: options
        ).compactMap { url in
            let values = try? url.resourceValues(forKeys: keys)
            return FileItem(
                url: url,
                isDirectory: values?.isDirectory ?? false,
                isHidden: values?.isHidden ?? false,
                fileSize: values?.fileSize.map(Int64.init),
                modificationDate: values?.contentModificationDate,
                kind: values?.localizedTypeDescription ?? "Item"
            )
        }
    }

    func createFolder(named name: String, in directory: URL) throws -> URL {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedName.contains("/") else {
            throw FileProviderError.invalidName
        }
        let destination = directory.appendingPathComponent(trimmedName, isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
        return destination
    }

    func rename(_ item: URL, to newName: String) throws -> URL {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedName.contains("/") else {
            throw FileProviderError.invalidName
        }
        let destination = item.deletingLastPathComponent().appendingPathComponent(trimmedName)
        try fileManager.moveItem(at: item, to: destination)
        return destination
    }

    func moveToTrash(_ item: URL) throws {
        try fileManager.trashItem(at: item, resultingItemURL: nil)
    }
}

enum FileProviderError: LocalizedError {
    case invalidName

    var errorDescription: String? {
        switch self {
        case .invalidName:
            return "The name cannot be empty or contain a slash."
        }
    }
}
