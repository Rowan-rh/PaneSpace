import Foundation

enum FileTransferKind: String, Codable, Sendable {
    case copy
    case move
}

enum FileConflictDecision: String, Sendable {
    case keepBoth
    case replace
    case skip
}

enum FileTransferState: String, Sendable {
    case queued
    case running
    case waitingForDecision
    case cancelling
    case completed
    case failed
    case cancelled
}

struct FileTransferItem: Identifiable, Sendable {
    let id: UUID
    let source: URL
    var destination: URL?
    /// Measured before the job copies anything; nil until then.
    var byteCount: Int64?
    var isComplete = false
    var needsSourceRemoval = false
    var errorMessage: String?

    init(source: URL) {
        id = UUID()
        self.source = source
    }
}

struct FileTransferJob: Identifiable, Sendable {
    let id: UUID
    let kind: FileTransferKind
    let destinationDirectory: URL
    var items: [FileTransferItem]
    var state: FileTransferState = .queued
    var completedCount = 0
    /// Total bytes of all items; nil while the job has not been measured yet.
    var totalBytes: Int64?
    var completedBytes: Int64 = 0
    var errorMessage: String?

    /// Fraction of bytes done, falling back to items for jobs made only of empty files.
    var fractionCompleted: Double {
        if let totalBytes, totalBytes > 0 {
            return min(1, Double(completedBytes) / Double(totalBytes))
        }
        return items.isEmpty ? 0 : Double(completedCount) / Double(items.count)
    }

    init(kind: FileTransferKind, sources: [URL], destinationDirectory: URL) {
        id = UUID()
        self.kind = kind
        self.destinationDirectory = destinationDirectory
        items = sources.map(FileTransferItem.init)
    }
}

struct FileTransferConflict: Identifiable, Sendable {
    let jobID: UUID
    let source: URL
    let destination: URL

    var id: UUID { jobID }
}

enum LocalTransferError: LocalizedError, Sendable {
    case invalidDestination
    case destinationExists
    case destinationNotWritable(name: String)
    case sourceRemovalFailed(destination: URL, reason: String)

    var errorDescription: String? {
        switch self {
        case .invalidDestination:
            return L10n.text("The destination is inside the source or is the same folder.")
        case .destinationExists:
            return L10n.text("An item with that name already exists.")
        case let .destinationNotWritable(name):
            return L10n.format("You don’t have permission to write to “%@”.", name)
        case let .sourceRemovalFailed(_, reason):
            return L10n.format("The copy completed, but the source could not be moved to Trash: %@", reason)
        }
    }
}
