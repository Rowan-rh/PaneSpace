import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var paneLayout: PaneLayout {
        didSet {
            UserDefaults.standard.set(paneLayout.rawValue, forKey: "currentPaneLayout")
            if !paneLayout.visibleSlots.contains(activePane) {
                activePane = .primary
            }
        }
    }
    @Published var activePane: PaneSlot = .primary
    @Published var sidebarSelection: SidebarLocation.ID?
    @Published var isCreatingFolder = false
    @Published var isShowingSettings = false

    let primaryPane = BrowserPaneModel()
    let secondaryPane = BrowserPaneModel(url: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser)
    let tertiaryPane = BrowserPaneModel(url: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser)
    let quaternaryPane = BrowserPaneModel(url: URL(fileURLWithPath: "/Applications", isDirectory: true))

    init() {
        let defaults = UserDefaults.standard
        let rawLayout = defaults.string(forKey: "currentPaneLayout")
            ?? defaults.string(forKey: "defaultPaneLayout")
            ?? PaneLayout.twoColumns.rawValue
        paneLayout = PaneLayout(rawValue: rawLayout) ?? .twoColumns
    }

    var activePaneModel: BrowserPaneModel {
        pane(for: activePane)
    }

    func pane(for slot: PaneSlot) -> BrowserPaneModel {
        switch slot {
        case .primary: primaryPane
        case .secondary: secondaryPane
        case .tertiary: tertiaryPane
        case .quaternary: quaternaryPane
        }
    }

    func open(_ url: URL) {
        activePaneModel.navigate(to: url)
    }

    func requestNewFolder() {
        isCreatingFolder = true
    }

    func toggleSecondPane() {
        paneLayout = paneLayout == .single ? .twoColumns : .single
    }
}
