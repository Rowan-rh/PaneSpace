import Foundation

protocol FileProviding: Sendable {
    func contents(of directory: URL, showsHiddenFiles: Bool) async throws -> [FileItem]
    func createFolder(named name: String, in directory: URL) async throws -> URL
    func rename(_ item: URL, to newName: String) async throws -> URL
    func moveToTrash(_ item: URL) async throws
    func availableCapacity(for directory: URL) async -> Int64?
}

extension FileProviding {
    func availableCapacity(for directory: URL) async -> Int64? {
        nil
    }
}

actor LocalFileProvider: FileProviding {
    private let fileManager: FileManager

    init(fileManager: FileManager = FileManager()) {
        self.fileManager = fileManager
    }

    func contents(of directory: URL, showsHiddenFiles: Bool) throws -> [FileItem] {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isPackageKey,
            .isHiddenKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .localizedTypeDescriptionKey
        ]

        let options: FileManager.DirectoryEnumerationOptions = showsHiddenFiles ? [] : [.skipsHiddenFiles]
        do {
            let urls = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(keys),
                options: options
            )
            return try urls.map { url in
                let values = try url.resourceValues(forKeys: keys)
                return FileItem(
                    url: url,
                    isDirectory: values.isDirectory ?? false,
                    isHidden: values.isHidden ?? false,
                    fileSize: values.fileSize.map(Int64.init),
                    modificationDate: values.contentModificationDate,
                    kind: values.localizedTypeDescription ?? L10n.text("Item"),
                    isPackage: values.isPackage ?? false
                )
            }
        } catch {
            throw FileProviderError.normalizing(error)
        }
    }

    func createFolder(named name: String, in directory: URL) throws -> URL {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidName(trimmedName) else {
            throw FileProviderError.invalidName
        }
        let destination = directory.appendingPathComponent(trimmedName, isDirectory: true)
        do {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
            return destination
        } catch {
            throw FileProviderError.normalizing(error)
        }
    }

    func rename(_ item: URL, to newName: String) throws -> URL {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidName(trimmedName) else {
            throw FileProviderError.invalidName
        }
        let destination = item.deletingLastPathComponent().appendingPathComponent(trimmedName)
        guard destination.standardizedFileURL != item.standardizedFileURL else {
            return item
        }
        do {
            try fileManager.moveItem(at: item, to: destination)
            return destination
        } catch {
            throw FileProviderError.normalizing(error)
        }
    }

    func moveToTrash(_ item: URL) throws {
        do {
            try fileManager.trashItem(at: item, resultingItemURL: nil)
        } catch {
            throw FileProviderError.normalizing(error)
        }
    }

    func availableCapacity(for directory: URL) -> Int64? {
        try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
    }

    private static func isValidName(_ name: String) -> Bool {
        !name.isEmpty &&
            name != "." &&
            name != ".." &&
            !name.contains("/") &&
            !name.contains("\0")
    }
}

enum FileProviderError: LocalizedError, Equatable, Sendable {
    case invalidName
    case itemAlreadyExists
    case permissionDenied
    case itemUnavailable
    case operationFailed

    static func normalizing(_ error: Error) -> FileProviderError {
        let cocoaError = error as? CocoaError
        switch cocoaError?.code {
        case .fileWriteFileExists:
            return .itemAlreadyExists
        case .fileReadNoPermission, .fileWriteNoPermission:
            return .permissionDenied
        case .fileNoSuchFile, .fileReadNoSuchFile:
            return .itemUnavailable
        default:
            return .operationFailed
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidName:
            return L10n.text("The name is not valid.")
        case .itemAlreadyExists:
            return L10n.text("An item with that name already exists.")
        case .permissionDenied:
            return L10n.text("PaneSpace does not have permission to complete this operation.")
        case .itemUnavailable:
            return L10n.text("The item is no longer available.")
        case .operationFailed:
            return L10n.text("The file operation could not be completed.")
        }
    }
}
