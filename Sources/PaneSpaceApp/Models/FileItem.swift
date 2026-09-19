import AppKit
import Foundation

struct FileItem: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    let isHidden: Bool
    let fileSize: Int64?
    let modificationDate: Date?
    let kind: String

    var id: URL { url }
    var name: String { url.lastPathComponent }

    var formattedSize: String {
        guard !isDirectory, let fileSize else { return "—" }
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var formattedDate: String {
        guard let modificationDate else { return "—" }
        return Self.dateFormatter.string(from: modificationDate)
    }

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

enum FileSort: String, CaseIterable, Identifiable {
    case name = "Name"
    case date = "Modified"
    case size = "Size"
    case kind = "Kind"

    var id: String { rawValue }
}
