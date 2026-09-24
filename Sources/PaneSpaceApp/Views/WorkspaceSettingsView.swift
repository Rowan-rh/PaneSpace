import AppKit
import SwiftUI

/// Settings group listing the sidebar workspaces with add, edit, reorder, and restore controls.
struct WorkspaceSettingsGroup: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var editingShortcut: WorkspaceShortcut?
    @State private var isAddingShortcut = false
    @State private var confirmsRestore = false

    private var workspaces: WorkspaceShortcutsModel {
        appModel.workspaceShortcuts
    }

    var body: some View {
        SettingsGroup(title: "Workspaces") {
            if workspaces.shortcuts.isEmpty {
                Text("No workspaces yet. Add a folder you open often.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }

            ForEach(Array(workspaces.shortcuts.enumerated()), id: \.element.id) { index, shortcut in
                if index > 0 {
                    Divider().padding(.leading, 44)
                }
                row(for: shortcut, at: index)
            }

            Divider()
            HStack {
                Button("Add Workspace…") { isAddingShortcut = true }
                Spacer()
                Button("Restore Default Workspaces…") { confirmsRestore = true }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .sheet(isPresented: $isAddingShortcut) {
            WorkspaceEditorSheet(original: nil) { workspaces.add($0) }
                .environmentObject(appModel)
        }
        .sheet(item: $editingShortcut) { shortcut in
            WorkspaceEditorSheet(original: shortcut) { workspaces.update($0) }
                .environmentObject(appModel)
        }
        .confirmationDialog("Restore default workspaces?", isPresented: $confirmsRestore) {
            Button("Restore Defaults", role: .destructive) { workspaces.restoreDefaults() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your custom workspaces will be replaced. Folders themselves are not changed.")
        }
    }

    private func row(for shortcut: WorkspaceShortcut, at index: Int) -> some View {
        let isAvailable = !workspaces.unavailableIDs.contains(shortcut.id)
        return HStack(spacing: 12) {
            Image(systemName: shortcut.systemImage)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(shortcut.name)
                Text((shortcut.path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            if !isAvailable {
                Label("Unavailable", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help("This folder is currently unavailable.")
            }
            Spacer(minLength: 12)
            iconButton("chevron.up", label: "Move Up") { workspaces.move(shortcut.id, by: -1) }
                .disabled(index == 0)
            iconButton("chevron.down", label: "Move Down") { workspaces.move(shortcut.id, by: 1) }
                .disabled(index == workspaces.shortcuts.count - 1)
            iconButton("pencil", label: "Edit") { editingShortcut = shortcut }
            iconButton("trash", label: "Remove") { workspaces.remove(shortcut.id) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func iconButton(
        _ systemImage: String,
        label: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Form for creating or editing a workspace. Saving is only possible once every field is valid.
private struct WorkspaceEditorSheet: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    let original: WorkspaceShortcut?
    let onSave: (WorkspaceShortcut) -> Void

    @State private var name = ""
    @State private var systemImage = "folder"
    @State private var pathText = ""
    @State private var resolvedPath: String?
    @State private var pathError: String?
    @State private var pathValidationTask: Task<Void, Never>?
    @State private var hasEditedName = false

    private let symbolColumns = Array(repeating: GridItem(.fixed(34), spacing: 6), count: 8)

    private var fieldIssue: WorkspaceShortcutError? {
        appModel.workspaceShortcuts.validationIssue(name: name, systemImage: systemImage)
    }

    private var canSave: Bool {
        fieldIssue == nil && resolvedPath != nil && pathValidationTask == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(original == nil ? "Add Workspace" : "Edit Workspace")
                .font(.headline)

            field("Name") {
                TextField("Workspace name", text: $name)
                    .textFieldStyle(.roundedBorder)
                // Only flag an empty name once the user has typed, not on a fresh form.
                if fieldIssue == .emptyName, hasEditedName {
                    issueText(WorkspaceShortcutError.emptyName.localizedDescription)
                }
            }

            field("Icon") {
                LazyVGrid(columns: symbolColumns, alignment: .leading, spacing: 6) {
                    ForEach(WorkspaceShortcut.suggestedSymbols, id: \.self) { symbol in
                        Button {
                            systemImage = symbol
                        } label: {
                            Image(systemName: symbol)
                                .frame(width: 30, height: 26)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(systemImage == symbol ? Color.accentColor.opacity(0.2) : Color.clear)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(systemImage == symbol ? Color.accentColor : Color.clear, lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .help(symbol)
                        .accessibilityLabel(symbol)
                    }
                }
                HStack(spacing: 8) {
                    TextField("SF Symbol name", text: $systemImage)
                        .textFieldStyle(.roundedBorder)
                    Group {
                        if WorkspaceShortcut.isValidSymbol(systemImage) {
                            Image(systemName: systemImage.trimmingCharacters(in: .whitespacesAndNewlines))
                                .foregroundStyle(Color.accentColor)
                        } else {
                            Image(systemName: "questionmark.square.dashed")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.title3)
                    .frame(width: 26)
                }
                if fieldIssue == .invalidSymbol {
                    issueText(WorkspaceShortcutError.invalidSymbol.localizedDescription)
                }
            }

            field("Folder") {
                HStack(spacing: 8) {
                    TextField("Folder path, such as ~/Code", text: $pathText)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose…", action: chooseFolder)
                }
                if let pathError {
                    issueText(pathError)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear {
            guard let original else { return }
            name = original.name
            systemImage = original.systemImage
            pathText = (original.path as NSString).abbreviatingWithTildeInPath
        }
        .onChange(of: pathText, initial: true) {
            validatePath()
        }
        .onChange(of: name) {
            hasEditedName = true
        }
    }

    private func field<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content()
        }
    }

    private func issueText(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.red)
    }

    private func validatePath() {
        pathValidationTask?.cancel()
        resolvedPath = nil
        let input = pathText
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            pathError = nil
            pathValidationTask = nil
            return
        }
        let workspaces = appModel.workspaceShortcuts
        pathValidationTask = Task {
            // A short pause avoids checking the file system on every keystroke.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            do {
                let path = try await workspaces.resolvedPath(for: input)
                guard !Task.isCancelled else { return }
                resolvedPath = path
                pathError = nil
            } catch {
                guard !Task.isCancelled else { return }
                pathError = error.localizedDescription
            }
            pathValidationTask = nil
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.text("Choose")
        if let resolvedPath {
            panel.directoryURL = URL(fileURLWithPath: resolvedPath, isDirectory: true)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pathText = (url.path as NSString).abbreviatingWithTildeInPath
    }

    private func save() {
        guard canSave, let resolvedPath else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSymbol = systemImage.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(WorkspaceShortcut(
            id: original?.id ?? UUID(),
            name: trimmedName,
            systemImage: trimmedSymbol,
            path: resolvedPath
        ))
        dismiss()
    }
}
