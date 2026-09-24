import Foundation

enum BrowserViewMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case list
    case columns

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: "List"
        case .columns: "Columns"
        }
    }

    var systemImage: String {
        switch self {
        case .list: "list.bullet"
        case .columns: "rectangle.split.3x1"
        }
    }
}

struct BrowserColumn: Identifiable {
    let directory: URL
    var items: [FileItem] {
        didSet { itemsRevision = UUID() }
    }
    var selectedItemID: FileItem.ID?
    var isLoading: Bool
    var errorMessage: String?
    /// Changes whenever `items` changes so sorted and filtered results can be cached per revision.
    private(set) var itemsRevision = UUID()

    init(
        directory: URL,
        items: [FileItem],
        selectedItemID: FileItem.ID?,
        isLoading: Bool,
        errorMessage: String?
    ) {
        self.directory = directory
        self.items = items
        self.selectedItemID = selectedItemID
        self.isLoading = isLoading
        self.errorMessage = errorMessage
    }

    var id: URL { directory }
}
