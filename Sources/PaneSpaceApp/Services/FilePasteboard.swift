import AppKit

/// Reads and writes file URLs in the pasteboard format other apps exchange, so items copied in
/// PaneSpace can be pasted in Finder and items copied in Finder can be pasted into a pane.
@MainActor
struct FilePasteboard {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    /// Replaces the pasteboard contents with `urls`. Only references are written; nothing is
    /// copied on disk until the items are pasted.
    @discardableResult
    func write(_ urls: [URL]) -> Bool {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else { return false }
        pasteboard.clearContents()
        return pasteboard.writeObjects(fileURLs.map { $0 as NSURL })
    }

    func fileURLs() -> [URL] {
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
        return objects?.compactMap { $0 as? URL } ?? []
    }
}
