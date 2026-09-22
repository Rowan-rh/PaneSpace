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

    let primaryPane: BrowserPaneModel
    let secondaryPane: BrowserPaneModel
    let tertiaryPane: BrowserPaneModel
    let quaternaryPane: BrowserPaneModel

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
}
