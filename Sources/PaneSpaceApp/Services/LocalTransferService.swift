import Darwin
import Foundation

actor LocalTransferService {
    typealias CopyItem = @Sendable (_ source: URL, _ destination: URL, _ progress: TransferByteCounter?) throws -> Void

    private let fileManager: FileManager
    private let copyItem: CopyItem
    private let trashItem: @Sendable (URL) throws -> URL?

    init(
        fileManager: FileManager = FileManager(),
        copyItem: CopyItem? = nil,
        trashItem: (@Sendable (URL) throws -> URL?)? = nil
    ) {
        self.fileManager = fileManager
        self.copyItem = copyItem ?? { try LocalFileCopier.copy(from: $0, to: $1, progress: $2) }
        self.trashItem = trashItem ?? { url in
            var resultingURL: NSURL?
            try FileManager().trashItem(at: url, resultingItemURL: &resultingURL)
            return resultingURL as URL?
        }
    }

    func validate(source: URL, destinationDirectory: URL) throws {
        guard source.isFileURL, destinationDirectory.isFileURL,
              let sourceParent = canonicalURL(for: source.deletingLastPathComponent()),
              let destinationDirectory = canonicalURL(for: destinationDirectory),
              sourceParent != destinationDirectory else {
            throw LocalTransferError.invalidDestination
        }

        let values = try? source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        if values?.isDirectory == true,
           values?.isSymbolicLink != true,
           let actualSource = canonicalURL(for: source),
           (destinationDirectory == actualSource || destinationDirectory.path.hasPrefix(actualSource.path + "/")) {
            throw LocalTransferError.invalidDestination
        }

        // Fail before staging anything so the user sees which folder refused the write instead of
        // the system's generic permission message.
        guard fileManager.isWritableFile(atPath: destinationDirectory.path) else {
            throw LocalTransferError.destinationNotWritable(name: destinationDirectory.lastPathComponent)
        }
    }

    func destination(for source: URL, in directory: URL) -> URL {
        directory.appendingPathComponent(source.lastPathComponent)
    }

    func exists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path) ||
            (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    func transfer(
        source: URL,
        to destinationDirectory: URL,
        kind: FileTransferKind,
        conflictDecision: FileConflictDecision?,
        progress: TransferByteCounter? = nil
    ) throws -> LocalTransferOutcome? {
        try validate(source: source, destinationDirectory: destinationDirectory)
        try Task.checkCancellation()

        let proposed = destination(for: source, in: destinationDirectory)
        let target: URL
        if exists(at: proposed) {
            switch conflictDecision {
            case .keepBoth:
                target = uniqueDestination(for: proposed)
            case .replace:
                target = proposed
            case .skip:
                return nil
            case nil:
                throw LocalTransferError.destinationExists
            }
        } else {
            target = proposed
        }

        let staging = destinationDirectory.appendingPathComponent(".panespace-staging-\(UUID().uuidString)")
        defer {
            if exists(at: staging) {
                try? fileManager.removeItem(at: staging)
            }
        }

        try copyItem(source, staging, progress)
        try Task.checkCancellation()

        var replacedItemInTrash: URL?
        if exists(at: target) {
            guard conflictDecision == .replace else {
                throw LocalTransferError.destinationExists
            }
            replacedItemInTrash = try trashItem(target)
        }
        try fileManager.moveItem(at: staging, to: target)

        var sourceInTrash: URL?
        if kind == .move {
            do {
                sourceInTrash = try trashItem(source)
            } catch {
                throw LocalTransferError.sourceRemovalFailed(
                    destination: target,
                    reason: error.localizedDescription
                )
            }
        }
        return LocalTransferOutcome(
            destination: target,
            replacedItemInTrash: replacedItemInTrash,
            sourceInTrash: sourceInTrash
        )
    }

    /// Total bytes a transfer of `source` copies. Unreadable items count as zero so progress
    /// can still be shown for the rest of the job.
    func byteCount(of source: URL) throws -> Int64 {
        do {
            return try LocalFileCopier.byteCount(of: source)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return 0
        }
    }

    @discardableResult
    func removeSourceAfterCopy(_ source: URL) throws -> URL? {
        try trashItem(source)
    }

    private func uniqueDestination(for proposed: URL) -> URL {
        let stem = proposed.deletingPathExtension().lastPathComponent
        let ext = proposed.pathExtension
        let directory = proposed.deletingLastPathComponent()
        var suffix = 2
        while true {
            let name = "\(stem) copy \(suffix)"
            let candidate = directory.appendingPathComponent(ext.isEmpty ? name : "\(name).\(ext)")
            if !exists(at: candidate) { return candidate }
            suffix += 1
        }
    }

    private func canonicalURL(for url: URL) -> URL? {
        guard let resolvedPath = url.standardizedFileURL.path.withCString({ realpath($0, nil) }) else {
            return nil
        }
        defer { free(resolvedPath) }
        return URL(fileURLWithPath: String(cString: resolvedPath))
    }
}

/// Where a transferred item ended up, and where anything it displaced went.
struct LocalTransferOutcome: Sendable {
    let destination: URL
    /// The existing destination item that Replace moved to the Trash.
    let replacedItemInTrash: URL?
    /// For moves, the source item after it was moved to the Trash.
    let sourceInTrash: URL?
}
