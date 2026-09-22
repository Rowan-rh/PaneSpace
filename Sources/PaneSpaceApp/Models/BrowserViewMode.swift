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
    var items: [FileItem]
    var selectedItemID: FileItem.ID?
    var isLoading: Bool
    var errorMessage: String?

    var id: URL { directory }
}
