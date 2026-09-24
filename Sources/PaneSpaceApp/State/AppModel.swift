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
            syncDirectoryObservation()
        }
    }
    @Published var activePane: PaneSlot
    @Published var sidebarSelection: SidebarLocation.ID?
    @Published var isCreatingFolder = false
    @Published var isShowingSettings = false
    @Published private(set) var locationEditRequest = 0
    @Published private(set) var searchFocusRequest = 0
    /// Incremented only when the keyboard changes the active pane, so the new pane can take
    /// keyboard focus without stealing it from a control the user clicked.
    @Published private(set) var paneFocusRequest = 0
    @Published private(set) var transferQueue = FileTransferQueueModel()
    let workspaceShortcuts: WorkspaceShortcutsModel
    let operationHistory: OperationHistoryModel
    @Published var isShowingOperationHistory = false
    @Published private(set) var isUndoing = false
    private let undoService: OperationUndoService

    @Published private(set) var primaryPane: BrowserPaneModel
    @Published private(set) var secondaryPane: BrowserPaneModel
    @Published private(set) var tertiaryPane: BrowserPaneModel
    @Published private(set) var quaternaryPane: BrowserPaneModel

    private let defaults: UserDefaults
    private var paneObservationCancellables: Set<AnyCancellable> = []
    private var visibleWindowCount = 0

    init(
        defaults: UserDefaults = .standard,
        operationHistory: OperationHistoryModel? = nil,
        undoService: OperationUndoService = OperationUndoService()
    ) {
        self.defaults = defaults
        self.undoService = undoService
        self.operationHistory = operationHistory ?? OperationHistoryModel()
        workspaceShortcuts = WorkspaceShortcutsModel(defaults: defaults)
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
        transferQueue.didCompleteItem = { [weak self] sourceDirectory, destinationDirectory in
            self?.refreshOpenPanes(in: [sourceDirectory, destinationDirectory])
        }
        transferQueue.didFinishJob = { [weak self] job in
            self?.recordTransfer(job)
        }
        for pane in [primaryPane, secondaryPane, tertiaryPane, quaternaryPane] {
            pane.didRecordOperation = { [weak self] record in
                self?.operationHistory.record(record)
            }
        }
        self.operationHistory.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &paneObservationCancellables)
        transferQueue.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &paneObservationCancellables)
        workspaceShortcuts.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &paneObservationCancellables)
        syncDirectoryObservation()
    }

    var activePaneModel: BrowserPaneModel {
        pane(for: activePane)
    }

    var canCloseActiveTabOrPane: Bool {
        activePaneModel.tabs.count > 1 || paneLayout.visiblePaneCount > 1
    }

    var canAddPane: Bool {
        paneLayout.visiblePaneCount < PaneSlot.allCases.count
    }

    var canTransferSelection: Bool {
        paneLayout.visiblePaneCount > 1 && !activePaneModel.selectedItems.isEmpty
    }

    func nextVisiblePane(after slot: PaneSlot) -> PaneSlot? {
        let slots = paneLayout.visibleSlots
        guard slots.count > 1, let index = slots.firstIndex(of: slot) else { return nil }
        return slots[(index + 1) % slots.count]
    }

    func cycleActivePane(backward: Bool) {
        let slots = paneLayout.visibleSlots
        guard slots.count > 1, let index = slots.firstIndex(of: activePane) else { return }
        activePane = slots[(index + (backward ? slots.count - 1 : 1)) % slots.count]
        paneFocusRequest += 1
    }

    func requestLocationEditing() {
        locationEditRequest += 1
    }

    func requestSearchFocus() {
        searchFocusRequest += 1
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

    /// Opens a sidebar location in the active pane unless the pane already shows it.
    func openSidebarLocation(_ location: SidebarLocation) {
        guard activePaneModel.currentURL.standardizedFileURL != location.url.standardizedFileURL else { return }
        open(location.url)
    }

    /// Keeps the sidebar highlight on the location the active pane shows. Clearing it after the
    /// pane moves elsewhere lets a second click on the same location open it again.
    func syncSidebarSelection(with locations: [SidebarLocation]) {
        let currentDirectory = activePaneModel.currentURL.standardizedFileURL
        if let selectedID = sidebarSelection,
           locations.contains(where: { $0.id == selectedID && $0.url.standardizedFileURL == currentDirectory }) {
            return
        }
        let matchingID = locations.first { $0.url.standardizedFileURL == currentDirectory }?.id
        if sidebarSelection != matchingID {
            sidebarSelection = matchingID
        }
    }

    func requestNewFolder() {
        isCreatingFolder = true
    }

    func toggleSecondPane() {
        paneLayout = paneLayout == .single ? .twoColumns : .single
    }

    func addPane() {
        guard canAddPane else { return }

        let currentURL = activePaneModel.currentURL
        let nextLayout: PaneLayout
        switch paneLayout {
        case .single:
            let preferredLayout = PaneLayout(rawValue: defaults.string(forKey: "defaultPaneLayout") ?? "")
            switch preferredLayout {
            case .twoRows, .threeRows, .fourRows, .primaryTop, .primaryBottom:
                nextLayout = .twoRows
            default:
                nextLayout = .twoColumns
            }
        case .twoColumns:
            nextLayout = .threeColumns
        case .twoRows:
            nextLayout = .threeRows
        case .primaryLeft, .primaryRight, .primaryTop, .primaryBottom:
            nextLayout = .fourGrid
        case .threeColumns:
            nextLayout = .fourColumns
        case .threeRows:
            nextLayout = .fourRows
        case .fourGrid, .fourColumns, .fourRows:
            return
        }

        paneLayout = nextLayout
        guard let newPaneSlot = nextLayout.visibleSlots.last else { return }
        pane(for: newPaneSlot).navigate(to: currentURL, recordsHistory: false)
        activePane = newPaneSlot
    }

    func transfer(
        _ urls: [URL],
        from sourceSlot: PaneSlot?,
        to destinationSlot: PaneSlot,
        kind: FileTransferKind
    ) {
        guard paneLayout.visibleSlots.contains(destinationSlot),
              sourceSlot != destinationSlot,
              !urls.isEmpty else { return }
        transferQueue.enqueue(
            kind: kind,
            sources: urls,
            destinationDirectory: pane(for: destinationSlot).transferDestinationURL
        )
    }

    func transferSelection(from sourceSlot: PaneSlot, to destinationSlot: PaneSlot, kind: FileTransferKind) {
        let urls = pane(for: sourceSlot).selectedItems.map(\.url)
        transfer(urls, from: sourceSlot, to: destinationSlot, kind: kind)
    }

    // MARK: Undo

    /// The operation ⌘Z reverses: the newest one that has not been undone yet.
    var latestUndoableOperation: OperationRecord? {
        operationHistory.records.first { OperationUndoService.canUndo($0) }
    }

    func undoLatestOperation() {
        guard let record = latestUndoableOperation else { return }
        undo(record)
    }

    func undo(_ record: OperationRecord) {
        guard !isUndoing, OperationUndoService.canUndo(record) else { return }
        isUndoing = true
        let reportingPane = activePaneModel
        Task {
            var updated = record
            do {
                let changed = try await undoService.undo(record)
                updated.isUndone = true
                if record.kind == .rename {
                    for item in record.items {
                        guard let result = item.result else { continue }
                        for slot in PaneSlot.allCases {
                            pane(for: slot).followRename(from: result, to: item.original)
                        }
                    }
                }
                refreshPanes(within: changed)
            } catch let partial as PartialUndo {
                updated.isUndone = true
                refreshPanes(within: partial.changed)
                reportingPane.operationErrorMessage = partial.localizedDescription
            } catch {
                reportingPane.operationErrorMessage = error.localizedDescription
            }
            operationHistory.update(updated)
            isUndoing = false
        }
    }

    /// Undo can bring back a folder a pane was showing as unavailable, so panes inside the
    /// changed folders reload too, not only panes showing them.
    private func refreshPanes(within directories: Set<URL>) {
        let changed = directories.map(BrowserPaneModel.comparablePath)
        for slot in paneLayout.visibleSlots {
            let pane = pane(for: slot)
            let path = BrowserPaneModel.comparablePath(pane.currentURL)
            if changed.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
                pane.refresh()
            }
        }
    }

    private func recordTransfer(_ job: FileTransferJob) {
        let outcome: OperationOutcome
        switch job.state {
        case .completed: outcome = .completed
        case .failed: outcome = .failed
        default: outcome = .cancelled
        }
        let items = job.items.compactMap { item -> OperationRecordItem? in
            // A move whose source could not be trashed still produced a copy worth recording.
            guard let destination = item.destination, item.isComplete || item.needsSourceRemoval else { return nil }
            return OperationRecordItem(
                original: item.source,
                result: destination,
                trashed: item.sourceInTrash,
                replacedInTrash: item.replacedItemInTrash
            )
        }
        // A cancelled run that changed nothing is not worth a history entry.
        guard outcome != .cancelled || !items.isEmpty else { return }
        operationHistory.record(OperationRecord(
            kind: job.kind == .copy ? .copy : .move,
            outcome: outcome,
            directory: job.destinationDirectory,
            items: items,
            requestedCount: job.items.count,
            errorMessage: job.errorMessage
        ))
    }

    private func refreshOpenPanes(in directories: [URL]) {
        let changed = Set(directories.map { $0.standardizedFileURL })
        for slot in paneLayout.visibleSlots {
            let pane = pane(for: slot)
            if changed.contains(pane.currentURL.standardizedFileURL) {
                pane.refresh()
            }
        }
    }

    private func syncDirectoryObservation() {
        for slot in PaneSlot.allCases {
            pane(for: slot).setDirectoryObservationEnabled(
                visibleWindowCount > 0 && paneLayout.visibleSlots.contains(slot)
            )
        }
    }

    func windowDidAppear() {
        visibleWindowCount += 1
        syncDirectoryObservation()
    }

    func windowDidDisappear() {
        visibleWindowCount = max(0, visibleWindowCount - 1)
        syncDirectoryObservation()
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
