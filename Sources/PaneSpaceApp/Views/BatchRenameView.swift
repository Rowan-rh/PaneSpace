import SwiftUI

struct BatchRenameView: View {
    @ObservedObject var model: BrowserPaneModel
    let request: BatchRenameRequest
    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable, Identifiable {
        case replace = "Replace Text"
        case add = "Add Text"
        case format = "Format"

        var id: String { rawValue }
    }

    @State private var mode: Mode = .replace
    @State private var find = ""
    @State private var replacement = ""
    @State private var ignoresCase = true
    @State private var includesExtension = false
    @State private var prefix = ""
    @State private var suffix = ""
    @State private var base = ""
    @State private var separator = " "
    @State private var start = 1
    @State private var digits = 2

    var body: some View {
        let plan = model.batchRenamePlan(for: request.targets, rule: rule)
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.format("Rename %lld Items", Int64(request.targets.count)))
                .font(.headline)

            Picker("Method", selection: $mode) {
                ForEach(Mode.allCases) { mode in
                    Text(L10n.text(mode.rawValue)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ruleFields
                .frame(minHeight: 84, alignment: .top)

            Text("Preview")
                .font(.subheadline.weight(.semibold))
            List(plan.entries) { entry in
                BatchRenamePreviewRow(entry: entry)
            }
            .listStyle(.bordered)
            .frame(minHeight: 200)

            HStack {
                summary(for: plan)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename") {
                    model.applyBatchRename(plan)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!plan.canApply || model.isPerformingOperation)
            }
        }
        .padding(20)
        .frame(width: 560, height: 520)
        .onAppear {
            base = BatchRenameRule.split(request.targets.first?.name ?? "").stem
        }
    }

    private var rule: BatchRenameRule {
        switch mode {
        case .replace:
            .replace(find: find, replacement: replacement, ignoresCase: ignoresCase, includesExtension: includesExtension)
        case .add:
            .add(prefix: prefix, suffix: suffix)
        case .format:
            .format(base: base, separator: separator, start: start, digits: digits)
        }
    }

    @ViewBuilder
    private var ruleFields: some View {
        switch mode {
        case .replace:
            Form {
                TextField("Find", text: $find)
                TextField("Replace with", text: $replacement)
                HStack(spacing: 16) {
                    Toggle("Ignore case", isOn: $ignoresCase)
                    Toggle("Include extension", isOn: $includesExtension)
                }
            }
        case .add:
            Form {
                TextField("Before name", text: $prefix)
                TextField("After name", text: $suffix)
            }
        case .format:
            Form {
                TextField("Name", text: $base)
                TextField("Separator", text: $separator)
                HStack(spacing: 16) {
                    Stepper(value: $start, in: 0...99_999) {
                        Text(L10n.format("Start at %lld", Int64(start)))
                    }
                    Stepper(value: $digits, in: 1...6) {
                        Text(L10n.format("%lld digits", Int64(digits)))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func summary(for plan: BatchRenamePlan) -> some View {
        let problems = plan.entries.filter { $0.issue != nil }.count
        if problems > 0 {
            Label(L10n.format("%lld names need attention", Int64(problems)), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.callout)
        } else {
            Text(L10n.format("%lld items will be renamed", Int64(plan.changedEntries.count)))
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }
}

private struct BatchRenamePreviewRow: View {
    let entry: BatchRenameEntry

    var body: some View {
        HStack(spacing: 8) {
            Text(entry.originalName)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.right")
                .foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.newName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(entry.issue == nil ? (entry.isChanged ? Color.primary : Color.secondary) : Color.red)
                if let issue = entry.issue {
                    Text(issue.message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
