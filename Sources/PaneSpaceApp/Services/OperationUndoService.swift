import Foundation

/// Reverses recorded local operations using only recoverable steps: renames, moves back to the
/// original location, and moving items to the Trash. Nothing is deleted permanently, and an
/// item is never moved onto a location that is already taken.
actor OperationUndoService {
    enum UndoError: LocalizedError, Equatable {
        case notUndoable
        case originalLocationTaken(name: String)
        case itemMissing(name: String)
        case folderNotEmpty(name: String)
        /// Some items were restored; the message describes the first failure.
        case partial(restored: Int, failed: Int, reason: String)

        var errorDescription: String? {
            switch self {
            case .notUndoable:
                L10n.text("This operation can no longer be undone.")
            case let .originalLocationTaken(name):
                L10n.format("“%@” cannot be restored because another item now uses its original location.", name)
            case let .itemMissing(name):
                L10n.format("“%@” was moved or deleted after the operation, so it cannot be undone.", name)
            case let .folderNotEmpty(name):
                L10n.format("“%@” is not empty anymore, so it was not moved to the Trash.", name)
            case let .partial(restored, failed, reason):
                L10n.format("%lld items were restored and %lld could not be: %@", Int64(restored), Int64(failed), reason)
            }
        }
    }

    private let fileManager: FileManager
    private let trashItem: @Sendable (URL) throws -> URL?

    init(
        fileManager: FileManager = FileManager(),
        trashItem: (@Sendable (URL) throws -> URL?)? = nil
    ) {
        self.fileManager = fileManager
        self.trashItem = trashItem ?? { url in
            var resultingURL: NSURL?
            try FileManager().trashItem(at: url, resultingItemURL: &resultingURL)
            return resultingURL as URL?
        }
    }

    static func canUndo(_ record: OperationRecord) -> Bool {
        !record.isUndone && !record.items.isEmpty
    }

    /// Returns the folders whose contents changed, so open panes can refresh.
    func undo(_ record: OperationRecord) async throws -> Set<URL> {
        guard Self.canUndo(record) else { throw UndoError.notUndoable }
        switch record.kind {
        case .rename:
            return try await undoRename(record)
        case .trash:
            return try perItem(record.items.reversed()) { item in try self.restoreFromTrash(item) }
        case .newFolder:
            return try perItem(record.items) { item in try self.trashEmptyFolder(item) }
        case .copy:
            return try perItem(record.items.reversed()) { item in try self.undoCopy(item) }
        case .move:
            return try perItem(record.items.reversed()) { item in try self.undoMove(item) }
        }
    }

    // MARK: Steps

    private func undoRename(_ record: OperationRecord) async throws -> Set<URL> {
        let pairs = record.items.compactMap { item in item.result.map { ($0, item.original) } }
        guard !pairs.isEmpty else { throw UndoError.notUndoable }
        let currentKeys = Set(pairs.map { BatchRenamePlan.comparisonKey($0.0.lastPathComponent) })
        for (current, original) in pairs {
            guard exists(current) else { throw UndoError.itemMissing(name: current.lastPathComponent) }
            // Another item of this batch may hold the original name; the renamer handles that.
            if exists(original), !currentKeys.contains(BatchRenamePlan.comparisonKey(original.lastPathComponent)) {
                throw UndoError.originalLocationTaken(name: original.lastPathComponent)
            }
        }
        let plan = BatchRenamePlan(entries: pairs.map { current, original in
            BatchRenameEntry(source: current, newName: original.lastPathComponent, issue: nil)
        })
        _ = try await BatchRenamer(provider: LocalFileProvider(fileManager: FileManager())).apply(plan)
        return Set(pairs.map { $0.1.deletingLastPathComponent().standardizedFileURL })
    }

    private func restoreFromTrash(_ item: OperationRecordItem) throws -> Set<URL> {
        guard let trashed = item.trashed, exists(trashed) else {
            throw UndoError.itemMissing(name: item.original.lastPathComponent)
        }
        try moveBack(trashed, to: item.original)
        return [item.original.deletingLastPathComponent().standardizedFileURL]
    }

    private func trashEmptyFolder(_ item: OperationRecordItem) throws -> Set<URL> {
        let folder = item.result ?? item.original
        guard exists(folder) else { throw UndoError.itemMissing(name: folder.lastPathComponent) }
        let contents = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
        guard contents.allSatisfy({ $0 == ".DS_Store" }) else {
            throw UndoError.folderNotEmpty(name: folder.lastPathComponent)
        }
        _ = try trashItem(folder)
        return [folder.deletingLastPathComponent().standardizedFileURL]
    }

    private func undoCopy(_ item: OperationRecordItem) throws -> Set<URL> {
        guard let result = item.result, exists(result) else {
            throw UndoError.itemMissing(name: (item.result ?? item.original).lastPathComponent)
        }
        _ = try trashItem(result)
        try restoreReplacedItem(item, at: result)
        return [result.deletingLastPathComponent().standardizedFileURL]
    }

    private func undoMove(_ item: OperationRecordItem) throws -> Set<URL> {
        guard let result = item.result, exists(result) else {
            throw UndoError.itemMissing(name: (item.result ?? item.original).lastPathComponent)
        }
        if let trashed = item.trashed, exists(trashed) {
            // Restore the untouched original and retire the copy, so metadata such as the
            // creation date is exactly what it was before the move.
            try moveBack(trashed, to: item.original)
            _ = try trashItem(result)
        } else if item.trashed == nil, exists(item.original) {
            // The source was never removed (its removal failed), so only the copy goes.
            _ = try trashItem(result)
        } else {
            // The Trash was emptied: bring the only remaining copy back instead.
            try moveBack(result, to: item.original)
        }
        try restoreReplacedItem(item, at: result)
        return [
            result.deletingLastPathComponent().standardizedFileURL,
            item.original.deletingLastPathComponent().standardizedFileURL
        ]
    }

    private func restoreReplacedItem(_ item: OperationRecordItem, at location: URL) throws {
        guard let replaced = item.replacedInTrash, exists(replaced) else { return }
        try moveBack(replaced, to: location)
    }

    // MARK: Helpers

    private func moveBack(_ source: URL, to destination: URL) throws {
        guard !exists(destination) else {
            throw UndoError.originalLocationTaken(name: destination.lastPathComponent)
        }
        let parent = destination.deletingLastPathComponent()
        guard exists(parent) else {
            throw UndoError.itemMissing(name: parent.lastPathComponent)
        }
        try fileManager.moveItem(at: source, to: destination)
    }

    private func exists(_ url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path) ||
            (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    /// Undoes items independently so one missing item does not strand the rest.
    private func perItem(
        _ items: some Sequence<OperationRecordItem>,
        _ step: (OperationRecordItem) throws -> Set<URL>
    ) throws -> Set<URL> {
        var changed: Set<URL> = []
        var restored = 0
        var failures: [Error] = []
        for item in items {
            do {
                changed.formUnion(try step(item))
                restored += 1
            } catch {
                failures.append(error)
            }
        }
        if let first = failures.first {
            if restored == 0 { throw first }
            throw PartialUndo(changed: changed, error: .partial(
                restored: restored,
                failed: failures.count,
                reason: first.localizedDescription
            ))
        }
        return changed
    }
}

/// Some items were undone; carries the folders that changed along with the error to show.
struct PartialUndo: LocalizedError {
    let changed: Set<URL>
    let error: OperationUndoService.UndoError

    var errorDescription: String? { error.errorDescription }
}
