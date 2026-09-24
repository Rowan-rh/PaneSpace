import SwiftUI

/// Current transfer jobs and the persistent history of finished operations.
struct OperationHistoryView: View {
    @ObservedObject var queue: FileTransferQueueModel
    @ObservedObject var history: OperationHistoryModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Operation History")
                    .font(.headline)
                Spacer()
                Button("Clear History…") { confirmsClear = true }
                    .disabled(history.records.isEmpty)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            List {
                if !queue.jobs.isEmpty {
                    Section("This Session") {
                        ForEach(queue.jobs.reversed()) { job in
                            TransferJobRow(queue: queue, job: job)
                        }
                    }
                }
                Section("History") {
                    if history.records.isEmpty {
                        Text("Finished file operations appear here.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(history.records) { record in
                        OperationRecordRow(record: record)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 680, height: 460)
        .confirmationDialog("Clear operation history?", isPresented: $confirmsClear) {
            Button("Clear History", role: .destructive) { history.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Files are not changed. Cleared operations can no longer be undone.")
        }
    }
}

struct TransferJobRow: View {
    @ObservedObject var queue: FileTransferQueueModel
    let job: FileTransferJob

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: job.kind == .copy ? "doc.on.doc" : "arrow.right.doc.on.clipboard")
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.text(job.kind == .copy ? "Copy" : "Move"))
                    .font(.body.weight(.medium))
                Text(job.destinationDirectory.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error = job.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Spacer()
            if let bytes = job.byteSummary {
                Text(bytes)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Text("\(job.completedCount)/\(job.items.count)")
                .monospacedDigit()
            Text(L10n.text(job.state.title))
                .foregroundStyle(.secondary)
            if job.state.canCancel {
                Button("Cancel") { queue.cancel(job.id) }
            } else if job.state.canRetry {
                Button("Retry") { queue.retry(job.id) }
            }
        }
    }
}

private struct OperationRecordRow: View {
    let record: OperationRecord

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: record.systemImage)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(record.date, format: .dateTime.month().day().hour().minute())
                    if record.items.count < record.requestedCount {
                        Text(L10n.format("%lld of %lld items changed", Int64(record.items.count), Int64(record.requestedCount)))
                    }
                    if record.isUndone {
                        Text("Undone")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let error = record.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            Spacer()
            Text(L10n.text(record.outcome.title))
                .foregroundStyle(record.outcome == .failed ? .red : .secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

extension OperationOutcome {
    var title: String {
        switch self {
        case .completed: "Completed"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }
}

extension FileTransferJob {
    /// "1.2 MB of 4 GB" while bytes are known.
    var byteSummary: String? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return L10n.format(
            "%@ of %@",
            ByteCountFormatter.string(fromByteCount: completedBytes, countStyle: .file),
            ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        )
    }
}

extension FileTransferState {
    var title: String {
        switch self {
        case .queued: "Queued"
        case .running: "Running"
        case .waitingForDecision: "Waiting for decision"
        case .cancelling: "Cancelling"
        case .completed: "Completed"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }

    var canCancel: Bool {
        self == .queued || self == .running || self == .waitingForDecision
    }

    var canRetry: Bool {
        self == .failed || self == .cancelled
    }
}
