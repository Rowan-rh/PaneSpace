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
        let cloudURLs = urls.filter(CloudLocation.isCloud)
        guard !fileURLs.isEmpty || !cloudURLs.isEmpty else { return }
        pasteboard.clearContents()
        var objects: [NSPasteboardWriting] = fileURLs.map { $0 as NSURL }
        // Cloud items mean nothing to other apps, so they travel in a type only PaneSpace reads.
        if !cloudURLs.isEmpty {
            let item = NSPasteboardItem()
            item.setString(cloudURLs.map(\.absoluteString).joined(separator: "\n"), forType: .cloudLocations)
            objects.append(item)
        }
        pasteboard.writeObjects(objects)
    }

    /// Items copied from a cloud drive in PaneSpace.
    func cloudURLs() -> [URL] {
        (pasteboard.pasteboardItems ?? [])
            .compactMap { $0.string(forType: .cloudLocations) }
            .flatMap { $0.split(separator: "\n") }
            .compactMap { URL(string: String($0)) }
            .filter(CloudLocation.isCloud)
    }

    func fileURLs() -> [URL] {
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) ?? []
        return objects.compactMap { ($0 as? NSURL) as URL? }
    }
}

extension NSPasteboard.PasteboardType {
    static let cloudLocations = NSPasteboard.PasteboardType("org.panespace.cloud-locations")
}
