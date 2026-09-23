import Foundation

struct SidebarLocation: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let systemImage: String
    let url: URL
}
