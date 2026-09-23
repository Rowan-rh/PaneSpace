import SwiftUI

struct TransferCenterView: View {
    @ObservedObject var queue: FileTransferQueueModel
    @State private var showsHistory = false
    @State private var appliesToAll = false

    var body: some View {
        if !queue.jobs.isEmpty {
            VStack(spacing: 0) {
                Divider()
                if let conflict = queue.conflict {
                    conflictControls(for: conflict)
                    Divider()
                }
                HStack(spacing: 10) {
                    if let job = displayedJob {
                        Image(systemName: job.kind == .copy ? "doc.on.doc" : "arrow.right.doc.on.clipboard")
                        Text(L10n.text(job.kind == .copy ? "Copy" : "Move"))
                        Text("\(job.completedCount)/\(job.items.count)")
                            .monospacedDigit()
                        Text(L10n.text(job.state.title))
                            .foregroundStyle(job.state == .failed ? .red : .secondary)
                        if let error = job.errorMessage {
                            Text(error)
                                .lineLimit(1)
                                .foregroundStyle(.red)
                        }
                        Spacer(minLength: 8)
                        if job.state.canCancel {
                            Button("Cancel") { queue.cancel(job.id) }
                        } else if job.state.canRetry {
                            Button("Retry") { queue.retry(job.id) }
                        }
                    }
                    Button("Transfers") { showsHistory = true }
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .frame(height: 32)
            }
            .background(.regularMaterial)
            .sheet(isPresented: $showsHistory) {
                historySheet
            }
            .onChange(of: queue.conflict?.id) {
                appliesToAll = false
            }
        }
    }

    private var displayedJob: FileTransferJob? {
        queue.jobs.first(where: { $0.state.canCancel }) ?? queue.jobs.last
    }

    private func conflictControls(for conflict: FileTransferConflict) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(L10n.format("An item named %@ already exists.", conflict.destination.lastPathComponent))
                .lineLimit(1)
            Toggle("Apply to all", isOn: $appliesToAll)
                .toggleStyle(.checkbox)
            Spacer(minLength: 8)
            Button("Skip") { queue.resolveConflict(.skip, applyToAll: appliesToAll) }
            Button("Keep Both") { queue.resolveConflict(.keepBoth, applyToAll: appliesToAll) }
            Button("Replace") { queue.resolveConflict(.replace, applyToAll: appliesToAll) }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(minHeight: 42)
    }

    private var historySheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Transfers")
                    .font(.headline)
                Spacer()
                Button("Done") { showsHistory = false }
            }
            List(queue.jobs.reversed()) { job in
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
        .padding(20)
        .frame(width: 620, height: 360)
    }
}

private extension FileTransferState {
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
