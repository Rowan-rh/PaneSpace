import Foundation

struct BrowserTab: Identifiable, Hashable {
    let id: UUID
    var url: URL
    var backHistory: [URL]
    var forwardHistory: [URL]

    init(
        id: UUID = UUID(),
        url: URL,
        backHistory: [URL] = [],
        forwardHistory: [URL] = []
    ) {
        self.id = id
        self.url = url
        self.backHistory = backHistory
        self.forwardHistory = forwardHistory
    }

    var title: String {
        if url.path == FileManager.default.homeDirectoryForCurrentUser.path {
            return "Home"
        }
        return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }
}
