import AppKit
import Foundation

struct FileItem: Identifiable, Hashable, Sendable {
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

    @MainActor var icon: NSImage {
        FileIconCache.shared.image(for: url)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

@MainActor
private final class FileIconCache {
    static let shared = FileIconCache()

    private let images = NSCache<NSURL, NSImage>()

    func image(for url: URL) -> NSImage {
        let key = url as NSURL
        if let cached = images.object(forKey: key) {
            return cached
        }

        let image = NSWorkspace.shared.icon(forFile: url.path)
        images.setObject(image, forKey: key)
        return image
    }
}

enum FileSort: String, CaseIterable, Identifiable, Codable, Sendable {
    case name = "Name"
    case date = "Modified"
    case size = "Size"
    case kind = "Kind"

    var id: String { rawValue }
}
