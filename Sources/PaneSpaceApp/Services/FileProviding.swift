import Foundation

protocol FileProviding: Sendable {
    func contents(of directory: URL, showsHiddenFiles: Bool) async throws -> [FileItem]
    func contentBatches(of directory: URL, showsHiddenFiles: Bool) -> AsyncThrowingStream<[FileItem], Error>
    func createFolder(named name: String, in directory: URL) async throws -> URL
    func rename(_ item: URL, to newName: String) async throws -> URL
    /// Returns where the item ended up in the Trash when the provider knows it.
    @discardableResult
    func moveToTrash(_ item: URL) async throws -> URL?
    func availableCapacity(for directory: URL) async -> Int64?
}

extension FileProviding {
    func availableCapacity(for directory: URL) async -> Int64? {
        nil
    }

    /// Providers that can list a folder incrementally override this; the default delivers the
    /// whole listing as one batch.
    func contentBatches(of directory: URL, showsHiddenFiles: Bool) -> AsyncThrowingStream<[FileItem], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(try await contents(of: directory, showsHiddenFiles: showsHiddenFiles))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

actor LocalFileProvider: FileProviding {
    private let fileManager: FileManager

    init(fileManager: FileManager = FileManager()) {
        self.fileManager = fileManager
    }

    func contents(of directory: URL, showsHiddenFiles: Bool) throws -> [FileItem] {
        let options: FileManager.DirectoryEnumerationOptions = showsHiddenFiles ? [] : [.skipsHiddenFiles]
        do {
            let urls = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(Self.itemKeys),
                options: options
            )
            return try urls.map(item(for:))
        } catch {
            throw FileProviderError.normalizing(error)
        }
    }

    static let batchSize = 1_000

    /// Lists a folder in batches so large folders appear before they are fully read. Ending the
    /// stream, for example by navigating away, stops the enumeration.
    nonisolated func contentBatches(of directory: URL, showsHiddenFiles: Bool) -> AsyncThrowingStream<[FileItem], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.enumerate(directory, showsHiddenFiles: showsHiddenFiles) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func enumerate(
        _ directory: URL,
        showsHiddenFiles: Bool,
        yield: ([FileItem]) -> Void
    ) throws {
        var options: FileManager.DirectoryEnumerationOptions = [.skipsSubdirectoryDescendants, .skipsPackageDescendants]
        if !showsHiddenFiles { options.insert(.skipsHiddenFiles) }
        var failure: Error?
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(Self.itemKeys),
            options: options,
            errorHandler: { _, error in
                failure = error
                return false
            }
        ) else {
            throw FileProviderError.itemUnavailable
        }

        var batch: [FileItem] = []
        batch.reserveCapacity(Self.batchSize)
        var yieldedAny = false
        while let url = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            guard let item = try? item(for: url) else { continue }
            batch.append(item)
            if batch.count == Self.batchSize {
                yield(batch)
                yieldedAny = true
                batch.removeAll(keepingCapacity: true)
            }
        }
        if let failure {
            throw FileProviderError.normalizing(failure)
        }
        if !batch.isEmpty || !yieldedAny {
            yield(batch)
        }
    }

    static let itemKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isPackageKey,
        .isHiddenKey,
        .isSymbolicLinkKey,
        .isVolumeKey,
        .fileSizeKey,
        .contentModificationDateKey
    ]

    private func item(for url: URL) throws -> FileItem {
        let values = try url.resourceValues(forKeys: Self.itemKeys)
        return FileItem(
            url: url,
            isDirectory: values.isDirectory ?? false,
            isHidden: values.isHidden ?? false,
            fileSize: values.fileSize.map(Int64.init),
            modificationDate: values.contentModificationDate,
            kind: kind(for: url, values: values),
            isPackage: values.isPackage ?? false
        )
    }

    /// Looking up the localized kind costs far more than every other attribute together, so it
    /// is shared by items that must have the same kind: plain folders, and files, packages, or
    /// links with the same extension. Files without an extension are looked up one by one
    /// because the system may identify them from their contents.
    private var kindCache: [String: String] = [:]

    private func kind(for url: URL, values: URLResourceValues) -> String {
        let fileExtension = url.pathExtension.lowercased()
        let cacheKey: String?
        if values.isVolume == true {
            cacheKey = nil
        } else if values.isSymbolicLink == true {
            cacheKey = "link.\(fileExtension)"
        } else if values.isPackage == true {
            cacheKey = "package.\(fileExtension)"
        } else if values.isDirectory == true {
            cacheKey = "folder"
        } else {
            cacheKey = fileExtension.isEmpty ? nil : "file.\(fileExtension)"
        }
        if let cacheKey, let cached = kindCache[cacheKey] {
            return cached
        }
        let kind = (try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey]))?.localizedTypeDescription
            ?? L10n.text("Item")
        if let cacheKey {
            kindCache[cacheKey] = kind
        }
        return kind
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

    func moveToTrash(_ item: URL) throws -> URL? {
        do {
            var resultingURL: NSURL?
            try fileManager.trashItem(at: item, resultingItemURL: &resultingURL)
            return resultingURL as URL?
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
