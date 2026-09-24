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
    var errorMessage: String?

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
