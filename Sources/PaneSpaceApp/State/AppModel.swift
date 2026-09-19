import Foundation

enum PaneSlot {
    case primary
    case secondary
}

@MainActor
final class AppModel: ObservableObject {
    @Published var isDualPane = true
    @Published var activePane: PaneSlot = .primary
    @Published var sidebarSelection: SidebarLocation.ID?
    @Published var isCreatingFolder = false

    let primaryPane = BrowserPaneModel()
    let secondaryPane = BrowserPaneModel(url: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser)

    var activePaneModel: BrowserPaneModel {
        activePane == .primary ? primaryPane : secondaryPane
    }

    func open(_ url: URL) {
        activePaneModel.navigate(to: url)
    }

    func requestNewFolder() {
        isCreatingFolder = true
    }
}
