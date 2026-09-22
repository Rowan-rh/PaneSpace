import Foundation

struct BrowserPaneSession: Codable, Equatable, Sendable {
    let tabs: [BrowserTab]
    let activeTabID: BrowserTab.ID
    let viewMode: BrowserViewMode
    let showsHiddenFiles: Bool
    let sort: FileSort
    let sortAscending: Bool
}

struct AppSession: Codable, Equatable, Sendable {
    static let currentVersion = 2

    let version: Int
    let paneLayout: PaneLayout
    let activePane: PaneSlot
    let panes: [PaneSlot: BrowserPaneSession]

    init(
        version: Int = currentVersion,
        paneLayout: PaneLayout,
        activePane: PaneSlot,
        panes: [PaneSlot: BrowserPaneSession]
    ) {
        self.version = version
        self.paneLayout = paneLayout
        self.activePane = activePane
        self.panes = panes
    }
}
