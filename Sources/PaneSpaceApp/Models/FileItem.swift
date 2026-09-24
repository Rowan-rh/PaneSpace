import AppKit
import Foundation

struct FileItem: Identifiable, Hashable, Sendable {
    let url: URL
    /// Stored because sorting large folders compares names hundreds of thousands of times, and
    /// deriving `lastPathComponent` from the URL each time dominated the sort.
    let name: String
    let isDirectory: Bool
    let isHidden: Bool
    let fileSize: Int64?
    let modificationDate: Date?
    let kind: String
    let isPackage: Bool

    init(
        url: URL,
        isDirectory: Bool,
        isHidden: Bool,
        fileSize: Int64?,
        modificationDate: Date?,
        kind: String,
        isPackage: Bool = false
    ) {
        self.url = url
        self.name = url.lastPathComponent
        self.isDirectory = isDirectory
        self.isHidden = isHidden
        self.fileSize = fileSize
        self.modificationDate = modificationDate
        self.kind = kind
        self.isPackage = isPackage
    }

    var id: URL { url }

    /// Packages such as applications are directories on disk but behave as single files when browsing.
    var isFolder: Bool { isDirectory && !isPackage }

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
