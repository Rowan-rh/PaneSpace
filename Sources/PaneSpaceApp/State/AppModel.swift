import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var paneLayout: PaneLayout {
        didSet {
            defaults.set(paneLayout.rawValue, forKey: "currentPaneLayout")
            if !paneLayout.visibleSlots.contains(activePane) {
                activePane = .primary
            }
        }
    }
    @Published var activePane: PaneSlot
    @Published var sidebarSelection: SidebarLocation.ID?
    @Published var isCreatingFolder = false
    @Published var isShowingSettings = false

    @Published private(set) var primaryPane: BrowserPaneModel
    @Published private(set) var secondaryPane: BrowserPaneModel
    @Published private(set) var tertiaryPane: BrowserPaneModel
    @Published private(set) var quaternaryPane: BrowserPaneModel

    private let defaults: UserDefaults
    private var paneObservationCancellables: Set<AnyCancellable> = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let downloads = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? home
        let applications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let storedSession = Self.loadSession(from: defaults)
        let shouldRestore = defaults.object(forKey: "restoreLastSession") == nil
            ? true
            : defaults.bool(forKey: "restoreLastSession")
        let restoredSession = shouldRestore ? storedSession : nil

        let startupURL: URL
        switch defaults.string(forKey: "startupLocation") ?? "home" {
        case "downloads":
            startupURL = downloads
        case "last":
            startupURL = storedSession?.panes[.primary]?.tabs.first(where: {
                $0.id == storedSession?.panes[.primary]?.activeTabID
            })?.url ?? home
        default:
            startupURL = home
        }

        primaryPane = BrowserPaneModel(
            url: startupURL,
            session: restoredSession?.panes[.primary]
        )
        secondaryPane = BrowserPaneModel(
            url: applications,
            session: restoredSession?.panes[.secondary]
        )
        tertiaryPane = BrowserPaneModel(
            url: home,
            session: restoredSession?.panes[.tertiary]
        )
        quaternaryPane = BrowserPaneModel(
            url: home,
            session: restoredSession?.panes[.quaternary]
        )

        let defaultLayout = defaults.string(forKey: "defaultPaneLayout")
            ?? PaneLayout.twoColumns.rawValue
        let rawLayout = shouldRestore
            ? defaults.string(forKey: "currentPaneLayout") ?? defaultLayout
            : defaultLayout
        let restoredLayout = restoredSession?.paneLayout
            ?? PaneLayout(rawValue: rawLayout)
            ?? .twoColumns
        paneLayout = restoredLayout
        let restoredActivePane = restoredSession?.activePane ?? .primary
        activePane = restoredLayout.visibleSlots.contains(restoredActivePane)
            ? restoredActivePane
            : .primary

        for pane in [primaryPane, secondaryPane, tertiaryPane, quaternaryPane] {
            pane.objectWillChange
                .sink { [weak self] in
                    self?.objectWillChange.send()
                }
                .store(in: &paneObservationCancellables)
        }
    }

    var activePaneModel: BrowserPaneModel {
        pane(for: activePane)
    }

    var canCloseActiveTabOrPane: Bool {
        activePaneModel.tabs.count > 1 || paneLayout.visiblePaneCount > 1
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

    func closeActiveTabOrPane() {
        let pane = activePaneModel
        if pane.tabs.count > 1 {
            pane.closeTab(pane.activeTabID)
            return
        }

        closePane(at: activePane)
    }

    func closePane(at slot: PaneSlot) {
        let visibleSlots = paneLayout.visibleSlots
        guard visibleSlots.count > 1,
              let closingIndex = visibleSlots.firstIndex(of: slot) else { return }

        var panes = [primaryPane, secondaryPane, tertiaryPane, quaternaryPane]
        let closedPane = panes.remove(at: closingIndex)
        panes.append(closedPane)
        primaryPane = panes[0]
        secondaryPane = panes[1]
        tertiaryPane = panes[2]
        quaternaryPane = panes[3]

        paneLayout = reducedLayout(afterClosingPaneFrom: paneLayout)
        activePane = PaneSlot.allCases[min(closingIndex, paneLayout.visiblePaneCount - 1)]
    }

    func saveSession() {
        let session = AppSession(
            paneLayout: paneLayout,
            activePane: activePane,
            panes: [
                .primary: primaryPane.session,
                .secondary: secondaryPane.session,
                .tertiary: tertiaryPane.session,
                .quaternary: quaternaryPane.session
            ]
        )
        guard let data = try? JSONEncoder().encode(session) else { return }
        defaults.set(data, forKey: "appSession")
    }

    private static func loadSession(from defaults: UserDefaults) -> AppSession? {
        guard let data = defaults.data(forKey: "appSession"),
              let session = try? JSONDecoder().decode(AppSession.self, from: data),
              session.version == AppSession.currentVersion else {
            return nil
        }
        return session
    }

    private func reducedLayout(afterClosingPaneFrom layout: PaneLayout) -> PaneLayout {
        switch layout {
        case .fourRows:
            .threeRows
        case .fourColumns:
            .threeColumns
        case .fourGrid:
            .primaryLeft
        case .threeRows, .primaryTop, .primaryBottom:
            .twoRows
        case .threeColumns, .primaryLeft, .primaryRight:
            .twoColumns
        case .twoColumns, .twoRows:
            .single
        case .single:
            .single
        }
    }
}
