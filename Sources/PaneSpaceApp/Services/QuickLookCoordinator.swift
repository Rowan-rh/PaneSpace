import AppKit
@preconcurrency import QuickLookUI

@MainActor
final class QuickLookCoordinator: NSObject, @preconcurrency QLPreviewPanelDataSource {
    static let shared = QuickLookCoordinator()

    private var previewURLs: [URL] = []

    func show(urls: [URL]) {
        guard !urls.isEmpty else { return }
        previewURLs = urls
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURLs.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard previewURLs.indices.contains(index) else { return nil }
        return previewURLs[index] as NSURL
    }
}
