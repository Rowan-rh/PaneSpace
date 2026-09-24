import AppKit
import Foundation

/// A user-configured sidebar workspace that opens a folder in the active pane.
struct WorkspaceShortcut: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var systemImage: String
    /// Standardized absolute path of the folder.
    var path: String

    init(id: UUID = UUID(), name: String, systemImage: String, path: String) {
        self.id = id
        self.name = name
        self.systemImage = systemImage
        self.path = path
    }

    var url: URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }

    var sidebarID: String {
        "workspace:\(id.uuidString)"
    }

    static let suggestedSymbols = [
        "folder", "folder.fill", "house", "hammer", "chevron.left.forwardslash.chevron.right",
        "terminal", "doc.text", "tray.full", "arrow.down.circle", "photo", "film", "music.note",
        "briefcase", "book", "graduationcap", "paintbrush", "shippingbox", "externaldrive",
        "server.rack", "cloud", "star", "heart", "flag", "archivebox"
    ]

    static func isValidSymbol(_ name: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty && NSImage(systemSymbolName: trimmedName, accessibilityDescription: nil) != nil
    }
}

enum WorkspaceShortcutError: LocalizedError, Equatable {
    case emptyName
    case invalidSymbol

    var errorDescription: String? {
        switch self {
        case .emptyName:
            L10n.text("Enter a workspace name.")
        case .invalidSymbol:
            L10n.text("This is not a valid SF Symbol name.")
        }
    }
}
