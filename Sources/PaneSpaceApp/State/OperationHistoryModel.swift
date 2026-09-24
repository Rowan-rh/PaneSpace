import Foundation

/// Finished file operations, newest first, kept across launches.
@MainActor
final class OperationHistoryModel: ObservableObject {
    static let maximumRecords = 200

    @Published private(set) var records: [OperationRecord] = []
    @Published private(set) var isLoaded = false

    private let store: OperationHistoryStore
    private var saveTask: Task<Void, Never>?
    /// Records added before the stored history finished loading.
    private var pendingRecords: [OperationRecord] = []

    init(store: OperationHistoryStore = OperationHistoryStore()) {
        self.store = store
        Task { [weak self] in
            let stored = await store.load()
            guard let self else { return }
            self.records = Array((self.pendingRecords + stored).prefix(Self.maximumRecords))
            self.pendingRecords = []
            self.isLoaded = true
            if !self.records.isEmpty, self.records.count != stored.count {
                self.scheduleSave()
            }
        }
    }

    func record(_ record: OperationRecord) {
        guard isLoaded else {
            pendingRecords.insert(record, at: 0)
            records.insert(record, at: 0)
            return
        }
        records.insert(record, at: 0)
        if records.count > Self.maximumRecords {
            records.removeLast(records.count - Self.maximumRecords)
        }
        scheduleSave()
    }

    func update(_ record: OperationRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[index] = record
        scheduleSave()
    }

    func clear() {
        records.removeAll()
        pendingRecords.removeAll()
        scheduleSave()
    }

    /// Waits for pending writes, for tests and for quitting.
    func flush() async {
        await saveTask?.value
    }

    private func scheduleSave() {
        let snapshot = records
        let previous = saveTask
        let store = store
        // Writes are chained so an older snapshot can never land after a newer one.
        saveTask = Task {
            await previous?.value
            try? await store.save(snapshot)
        }
    }
}
