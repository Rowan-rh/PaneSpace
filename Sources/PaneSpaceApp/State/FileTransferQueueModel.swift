import Combine
import Foundation

@MainActor
final class FileTransferQueueModel: ObservableObject {
    @Published private(set) var jobs: [FileTransferJob] = []
    @Published private(set) var conflict: FileTransferConflict?

    private let service: LocalTransferService
    var didCompleteItem: @MainActor (URL, URL) -> Void
    private var processingTask: Task<Void, Never>?
    private var pendingDecision: CheckedContinuation<FileConflictDecision?, Never>?
    private var decisionForRemainingConflicts: FileConflictDecision?

    init(
        service: LocalTransferService = LocalTransferService(),
        didCompleteItem: @escaping @MainActor (URL, URL) -> Void = { _, _ in }
    ) {
        self.service = service
        self.didCompleteItem = didCompleteItem
    }

    func enqueue(kind: FileTransferKind, sources: [URL], destinationDirectory: URL) {
        guard !sources.isEmpty else { return }
        jobs.append(FileTransferJob(kind: kind, sources: sources, destinationDirectory: destinationDirectory))
        startNextJob()
    }

    func cancel(_ jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        switch jobs[index].state {
        case .queued:
            jobs[index].state = .cancelled
        case .running, .waitingForDecision:
            jobs[index].state = .cancelling
            processingTask?.cancel()
            pendingDecision?.resume(returning: nil)
            pendingDecision = nil
            conflict = nil
        case .cancelling, .completed, .failed, .cancelled:
            break
        }
    }

    func retry(_ jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }),
              jobs[index].state == .failed || jobs[index].state == .cancelled else { return }
        jobs[index].state = .queued
        jobs[index].errorMessage = nil
        startNextJob()
    }

    func resolveConflict(_ decision: FileConflictDecision, applyToAll: Bool) {
        guard pendingDecision != nil else { return }
        if applyToAll { decisionForRemainingConflicts = decision }
        conflict = nil
        pendingDecision?.resume(returning: decision)
        pendingDecision = nil
    }

    private func startNextJob() {
        guard processingTask == nil,
              let index = jobs.firstIndex(where: { $0.state == .queued }) else { return }
        let jobID = jobs[index].id
        processingTask = Task { [weak self] in
            await self?.run(jobID)
            guard let self else { return }
            self.processingTask = nil
            self.decisionForRemainingConflicts = nil
            self.startNextJob()
        }
    }

    private func run(_ jobID: UUID) async {
        guard let jobIndex = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[jobIndex].state = .running

        do {
            try await measure(jobIndex: jobIndex)
        } catch {
            jobs[jobIndex].state = .cancelled
            return
        }

        for itemIndex in jobs[jobIndex].items.indices {
            if Task.isCancelled {
                jobs[jobIndex].state = .cancelled
                return
            }
            if jobs[jobIndex].items[itemIndex].isComplete { continue }
            let finishedBytes = jobs[jobIndex].items.filter(\.isComplete).reduce(Int64(0)) { $0 + ($1.byteCount ?? 0) }
            let itemBytes = jobs[jobIndex].items[itemIndex].byteCount ?? 0
            jobs[jobIndex].completedBytes = finishedBytes
            let counter = TransferByteCounter()
            let progressTask = trackProgress(of: counter, jobID: jobID, finishedBytes: finishedBytes, itemBytes: itemBytes)
            defer { progressTask.cancel() }

            let source = jobs[jobIndex].items[itemIndex].source
            let directory = jobs[jobIndex].destinationDirectory
            do {
                if jobs[jobIndex].items[itemIndex].needsSourceRemoval {
                    try await service.removeSourceAfterCopy(source)
                    jobs[jobIndex].items[itemIndex].needsSourceRemoval = false
                } else {
                    try await service.validate(source: source, destinationDirectory: directory)
                    let proposed = await service.destination(for: source, in: directory)
                    let decision: FileConflictDecision?
                    if await service.exists(at: proposed) {
                        decision = await requestDecision(jobID: jobID, source: source, destination: proposed)
                        try Task.checkCancellation()
                    } else {
                        decision = nil
                    }
                    let destination = try await service.transfer(
                        source: source,
                        to: directory,
                        kind: jobs[jobIndex].kind,
                        conflictDecision: decision,
                        progress: counter
                    )
                    jobs[jobIndex].items[itemIndex].destination = destination
                    if destination != nil {
                        didCompleteItem(source.deletingLastPathComponent(), directory)
                    }
                }
                progressTask.cancel()
                jobs[jobIndex].items[itemIndex].isComplete = true
                jobs[jobIndex].completedCount += 1
                jobs[jobIndex].completedBytes = finishedBytes + itemBytes
            } catch is CancellationError {
                jobs[jobIndex].state = .cancelled
                return
            } catch let error as LocalTransferError {
                if case let .sourceRemovalFailed(destination, _) = error {
                    jobs[jobIndex].items[itemIndex].destination = destination
                    jobs[jobIndex].items[itemIndex].needsSourceRemoval = true
                    didCompleteItem(source.deletingLastPathComponent(), directory)
                }
                fail(jobIndex: jobIndex, itemIndex: itemIndex, error: error)
                return
            } catch {
                fail(jobIndex: jobIndex, itemIndex: itemIndex, error: error)
                return
            }
        }

        jobs[jobIndex].state = .completed
    }

    /// Sizes every item once per job so retries keep the same total.
    private func measure(jobIndex: Int) async throws {
        guard jobs[jobIndex].totalBytes == nil else { return }
        var total: Int64 = 0
        for itemIndex in jobs[jobIndex].items.indices {
            try Task.checkCancellation()
            let size = try await service.byteCount(of: jobs[jobIndex].items[itemIndex].source)
            jobs[jobIndex].items[itemIndex].byteCount = size
            total += size
        }
        jobs[jobIndex].totalBytes = total
    }

    /// Copies report progress from the transfer actor; the queue samples it a few times a second
    /// instead of publishing every callback to the main actor.
    private func trackProgress(
        of counter: TransferByteCounter,
        jobID: UUID,
        finishedBytes: Int64,
        itemBytes: Int64
    ) -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled, let self,
                      let index = self.jobs.firstIndex(where: { $0.id == jobID }) else { return }
                let bytes = finishedBytes + min(counter.value, itemBytes)
                if self.jobs[index].completedBytes != bytes {
                    self.jobs[index].completedBytes = bytes
                }
            }
        }
    }

    private func requestDecision(jobID: UUID, source: URL, destination: URL) async -> FileConflictDecision? {
        if let decisionForRemainingConflicts { return decisionForRemainingConflicts }
        guard let jobIndex = jobs.firstIndex(where: { $0.id == jobID }) else { return nil }
        jobs[jobIndex].state = .waitingForDecision
        conflict = FileTransferConflict(jobID: jobID, source: source, destination: destination)
        let decision = await withCheckedContinuation { continuation in
            pendingDecision = continuation
        }
        if jobs[jobIndex].state != .cancelling {
            jobs[jobIndex].state = .running
        }
        return decision
    }

    private func fail(jobIndex: Int, itemIndex: Int, error: Error) {
        let message = error.localizedDescription
        jobs[jobIndex].items[itemIndex].errorMessage = message
        jobs[jobIndex].errorMessage = message
        jobs[jobIndex].state = .failed
    }
}
