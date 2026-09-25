import AppKit

/// Reads and writes file references on a pasteboard in the form Finder and other apps exchange,
/// so items copied here can be pasted elsewhere and the other way round.
@MainActor
struct FilePasteboard {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func write(_ urls: [URL]) {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.writeObjects(fileURLs.map { $0 as NSURL })
    }

    func fileURLs() -> [URL] {
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) ?? []
        return objects.compactMap { ($0 as? NSURL) as URL? }
    }
}
