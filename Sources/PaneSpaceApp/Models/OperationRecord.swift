import Foundation

enum OperationKind: String, Codable, Sendable {
    case copy
    case move
    case rename
    case trash
    case newFolder
}

enum OperationOutcome: String, Codable, Sendable {
    case completed
    case failed
    case cancelled
}

/// One item touched by an operation, with enough locations to reverse it later.
struct OperationRecordItem: Codable, Equatable, Sendable {
    /// Where the item was before the operation. For a new folder this is the folder itself.
    let original: URL
    /// Where the item is after the operation, if it still exists outside the Trash.
    var result: URL?
    /// Where the operation put an item in the Trash: the trashed item itself, or for a move the
    /// source that was trashed after copying.
    var trashed: URL?
    /// An existing item that a Replace decision moved to the Trash.
    var replacedInTrash: URL?

    init(original: URL, result: URL? = nil, trashed: URL? = nil, replacedInTrash: URL? = nil) {
        self.original = original
        self.result = result
        self.trashed = trashed
        self.replacedInTrash = replacedInTrash
    }
}

struct OperationRecord: Codable, Identifiable, Equatable, Sendable {
    static let maximumStoredItems = 500

    let id: UUID
    let date: Date
    let kind: OperationKind
    var outcome: OperationOutcome
    /// Destination folder for copies and moves, containing folder otherwise.
    let directory: URL
    /// Only items that were actually changed; skipped conflicts are left out.
    var items: [OperationRecordItem]
    /// How many items the user asked for, which can exceed `items` for partial results.
    let requestedCount: Int
    var errorMessage: String?
    /// Set once the operation was undone so it is not undone twice.
    var isUndone = false

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        kind: OperationKind,
        outcome: OperationOutcome,
        directory: URL,
        items: [OperationRecordItem],
        requestedCount: Int,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.outcome = outcome
        self.directory = directory
        self.items = Array(items.prefix(Self.maximumStoredItems))
        self.requestedCount = requestedCount
        self.errorMessage = errorMessage
    }

    var title: String {
        let count = Int64(requestedCount)
        switch kind {
        case .copy:
            return L10n.format("Copy %lld items to “%@”", count, directory.lastPathComponent)
        case .move:
            return L10n.format("Move %lld items to “%@”", count, directory.lastPathComponent)
        case .rename:
            if requestedCount == 1, let item = items.first, let result = item.result {
                return L10n.format("Rename “%@” to “%@”", item.original.lastPathComponent, result.lastPathComponent)
            }
            return L10n.format("Rename %lld items", count)
        case .trash:
            if requestedCount == 1, let item = items.first {
                return L10n.format("Move “%@” to the Trash", item.original.lastPathComponent)
            }
            return L10n.format("Move %lld items to the Trash", count)
        case .newFolder:
            return L10n.format("New folder “%@”", items.first?.original.lastPathComponent ?? "")
        }
    }

    var systemImage: String {
        switch kind {
        case .copy: "doc.on.doc"
        case .move: "arrow.right.doc.on.clipboard"
        case .rename: "character.cursor.ibeam"
        case .trash: "trash"
        case .newFolder: "folder.badge.plus"
        }
    }
}
