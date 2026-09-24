import Foundation

/// Owns the sidebar workspaces shown in the sidebar and edited in Settings.
@MainActor
final class WorkspaceShortcutsModel: ObservableObject {
    static let defaultsKey = "workspaceShortcuts"

    @Published private(set) var shortcuts: [WorkspaceShortcut]
    /// Workspaces whose folder is currently missing or unreadable.
    @Published private(set) var unavailableIDs: Set<WorkspaceShortcut.ID> = []

    private let defaults: UserDefaults
    private let homeDirectory: URL
    private let pathResolver = LocalPathResolver()
    private var availabilityTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.defaults = defaults
        self.homeDirectory = homeDirectory
        shortcuts = Self.storedShortcuts(in: defaults) ?? Self.defaultShortcuts(home: homeDirectory)
        refreshAvailability()
    }

    /// Re-reads the stored list, for example after all preferences were reset.
    func reload() {
        shortcuts = Self.storedShortcuts(in: defaults) ?? Self.defaultShortcuts(home: homeDirectory)
        refreshAvailability()
    }

    func add(_ shortcut: WorkspaceShortcut) {
        shortcuts.append(shortcut)
        didChangeShortcuts()
    }

    func update(_ shortcut: WorkspaceShortcut) {
        guard let index = shortcuts.firstIndex(where: { $0.id == shortcut.id }) else { return }
        shortcuts[index] = shortcut
        didChangeShortcuts()
    }

    func remove(_ id: WorkspaceShortcut.ID) {
        shortcuts.removeAll { $0.id == id }
        didChangeShortcuts()
    }

    func move(_ id: WorkspaceShortcut.ID, by offset: Int) {
        guard let index = shortcuts.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + offset
        guard shortcuts.indices.contains(destination) else { return }
        shortcuts.swapAt(index, destination)
        didChangeShortcuts()
    }

    func restoreDefaults() {
        defaults.removeObject(forKey: Self.defaultsKey)
        reload()
    }

    func validationIssue(name: String, systemImage: String) -> WorkspaceShortcutError? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .emptyName
        }
        if !WorkspaceShortcut.isValidSymbol(systemImage) {
            return .invalidSymbol
        }
        return nil
    }

    /// Resolves user input such as `~/Code` to an accessible folder, relative paths starting at home.
    func resolvedPath(for input: String) async throws -> String {
        try await pathResolver.resolve(input, relativeTo: homeDirectory).path
    }

    func refreshAvailability() {
        let paths = shortcuts.map { ($0.id, $0.path) }
        availabilityTask?.cancel()
        availabilityTask = Task { [weak self] in
            // Folders on network or removable volumes can be slow to stat, so check off the main actor.
            let unavailable = await Task.detached(priority: .utility) {
                let fileManager = FileManager()
                return Set(paths.compactMap { id, path -> WorkspaceShortcut.ID? in
                    var isDirectory: ObjCBool = false
                    let isAccessibleFolder = fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
                        && isDirectory.boolValue
                        && fileManager.isReadableFile(atPath: path)
                    return isAccessibleFolder ? nil : id
                })
            }.value
            guard !Task.isCancelled, let self, self.unavailableIDs != unavailable else { return }
            self.unavailableIDs = unavailable
        }
    }

    private func didChangeShortcuts() {
        persist()
        refreshAvailability()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(shortcuts) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private static func storedShortcuts(in defaults: UserDefaults) -> [WorkspaceShortcut]? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode([WorkspaceShortcut].self, from: data)
    }

    static func defaultShortcuts(home: URL) -> [WorkspaceShortcut] {
        let candidates = [
            WorkspaceShortcut(
                name: L10n.text("Home Workspace"),
                systemImage: "square.grid.2x2",
                path: home.standardizedFileURL.path
            ),
            WorkspaceShortcut(
                name: L10n.text("Development"),
                systemImage: "hammer",
                path: home.appendingPathComponent("Code", isDirectory: true).standardizedFileURL.path
            ),
            WorkspaceShortcut(
                name: L10n.text("Downloads Review"),
                systemImage: "tray.full",
                path: home.appendingPathComponent("Downloads", isDirectory: true).standardizedFileURL.path
            )
        ]
        return candidates.filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
