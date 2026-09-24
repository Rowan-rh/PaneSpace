import AppKit
import Foundation

@MainActor
final class BrowserPaneModel: ObservableObject, Identifiable {
    let id = UUID()

    @Published var tabs: [BrowserTab]
    @Published var activeTabID: BrowserTab.ID
    @Published var items: [FileItem] = []
    @Published var selection: Set<FileItem.ID> = []
    @Published var searchText = ""
    @Published var sort: FileSort = .name
    @Published var sortAscending = true
    @Published var showsHiddenFiles = false
    @Published var viewMode: BrowserViewMode
    @Published var columns: [BrowserColumn] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var operationErrorMessage: String?
    @Published var isPerformingOperation = false
    @Published var availableCapacity: Int64?
    @Published var renameTarget: FileItem?
    @Published private(set) var locationErrorMessage: String?
    @Published private(set) var isResolvingLocation = false

    private let provider: FileProviding
    private var refreshTask: Task<Void, Never>?
    private var columnLoadTask: Task<Void, Never>?
    private var operationTask: Task<Void, Never>?
    private var directoryObservers: [URL: LocalDirectoryObserver] = [:]
    private let pathResolver = LocalPathResolver()
    private var observesDirectories = false
    private var hasPendingDirectoryLoad = false
    private var selectionURLToRestoreAfterRefresh: URL?

    init(
        url: URL = FileManager.default.homeDirectoryForCurrentUser,
        provider: FileProviding = LocalFileProvider(),
        session: BrowserPaneSession? = nil
    ) {
        let fallbackTab = BrowserTab(url: url)
        let restoredTabs = if let session, !session.tabs.isEmpty {
            session.tabs
        } else {
            [fallbackTab]
        }
        self.tabs = restoredTabs
        if let session, restoredTabs.contains(where: { $0.id == session.activeTabID }) {
            self.activeTabID = session.activeTabID
        } else {
            self.activeTabID = restoredTabs[0].id
        }
        self.provider = provider
        self.viewMode = session?.viewMode ?? BrowserViewMode(
            rawValue: UserDefaults.standard.string(forKey: "defaultViewMode") ?? "list"
        ) ?? .list
        self.showsHiddenFiles = session?.showsHiddenFiles ?? false
        self.sort = session?.sort ?? .name
        self.sortAscending = session?.sortAscending ?? true
        loadCurrentDirectory()
    }

    var session: BrowserPaneSession {
        BrowserPaneSession(
            tabs: tabs,
            activeTabID: activeTabID,
            viewMode: viewMode,
            showsHiddenFiles: showsHiddenFiles,
            sort: sort,
            sortAscending: sortAscending
        )
    }

    var activeTab: BrowserTab {
        get {
            tabs.first(where: { $0.id == activeTabID }) ?? tabs[0]
        }
        set {
            guard let index = tabs.firstIndex(where: { $0.id == newValue.id }) else { return }
            tabs[index] = newValue
        }
    }

    var currentURL: URL { activeTab.url }
    var canGoBack: Bool { !activeTab.backHistory.isEmpty }
    var canGoForward: Bool { !activeTab.forwardHistory.isEmpty }

    var visibleItems: [FileItem] {
        displayedItems(from: items)
    }

    /// The selected items that are currently visible, in display order. Items hidden by the
    /// search filter stay selected but are excluded so actions never touch what the user cannot see.
    var selectedItems: [FileItem] {
        items(for: selection)
    }

    func items(for ids: Set<FileItem.ID>) -> [FileItem] {
        guard !ids.isEmpty else { return [] }
        let displayed = viewMode == .columns
            ? columns.flatMap { displayedItems(from: $0.items) }
            : visibleItems
        var includedIDs: Set<FileItem.ID> = []
        return displayed.filter { ids.contains($0.id) && includedIDs.insert($0.id).inserted }
    }

    func displayedItems(from source: [FileItem]) -> [FileItem] {
        let filtered = searchText.isEmpty
            ? source
            : source.filter { $0.name.localizedCaseInsensitiveContains(searchText) }

        return sortedItems(filtered)
    }

    private func sortedItems(_ source: [FileItem]) -> [FileItem] {
        source.sorted { lhs, rhs in
            if lhs.isFolder != rhs.isFolder {
                return lhs.isFolder
            }

            let result: ComparisonResult
            switch sort {
            case .name:
                result = lhs.name.localizedStandardCompare(rhs.name)
            case .date:
                result = compare(lhs.modificationDate, rhs.modificationDate)
            case .size:
                result = compare(lhs.fileSize, rhs.fileSize)
            case .kind:
                result = lhs.kind.localizedStandardCompare(rhs.kind)
            }
            return sortAscending ? result == .orderedAscending : result == .orderedDescending
        }
    }

    func setViewMode(_ mode: BrowserViewMode) {
        viewMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "defaultViewMode")
        if mode == .columns, columns.isEmpty {
            columns = [BrowserColumn(directory: currentURL, items: items, selectedItemID: nil, isLoading: false, errorMessage: nil)]
        } else if mode == .list {
            selection.formIntersection(Set(items.map(\.id)))
        }
        syncDirectoryObservers()
    }

    func selectColumnItem(_ item: FileItem, in columnID: BrowserColumn.ID) {
        guard let index = columns.firstIndex(where: { $0.id == columnID }) else { return }

        selectionURLToRestoreAfterRefresh = nil
        refreshTask?.cancel()
        columnLoadTask?.cancel()
        columns[index].selectedItemID = item.id
        if columns.count > index + 1 {
            columns.removeSubrange((index + 1)...)
        }
        selection = [item.id]

        guard item.isFolder else {
            let directory = columns[index].directory.standardizedFileURL
            updateActiveTabURL(directory)
            items = columns[index].items
            isLoading = false
            errorMessage = columns[index].errorMessage
            syncDirectoryObservers()
            return
        }

        var tab = activeTab
        if tab.url != item.url {
            tab.backHistory.append(tab.url)
            tab.forwardHistory.removeAll()
        }
        tab.url = item.url.standardizedFileURL
        activeTab = tab

        columns.append(
            BrowserColumn(directory: item.url, items: [], selectedItemID: nil, isLoading: true, errorMessage: nil)
        )
        items = []
        syncDirectoryObservers()

        let directory = item.url
        let showsHiddenFiles = showsHiddenFiles
        let provider = provider
        columnLoadTask = Task {
            do {
                let loadedItems = try await provider.contents(
                    of: directory,
                    showsHiddenFiles: showsHiddenFiles
                )

                guard !Task.isCancelled,
                      let lastIndex = columns.indices.last,
                      columns[lastIndex].directory == directory else { return }
                columns[lastIndex].items = loadedItems
                columns[lastIndex].isLoading = false
                items = loadedItems
                errorMessage = nil
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled,
                      let lastIndex = columns.indices.last,
                      columns[lastIndex].directory == directory else { return }
                columns[lastIndex].isLoading = false
                columns[lastIndex].errorMessage = error.localizedDescription
                items = []
            }
        }
    }

    func activateTab(_ id: BrowserTab.ID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectionURLToRestoreAfterRefresh = nil
        activeTabID = id
        loadCurrentDirectory()
    }

    func addTab(url: URL? = nil) {
        selectionURLToRestoreAfterRefresh = nil
        let tab = BrowserTab(url: url ?? currentURL)
        tabs.append(tab)
        activeTabID = tab.id
        loadCurrentDirectory()
    }

    func closeTab(_ id: BrowserTab.ID) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = activeTabID == id
        tabs.remove(at: index)
        if wasActive {
            selectionURLToRestoreAfterRefresh = nil
            activeTabID = tabs[min(index, tabs.count - 1)].id
            loadCurrentDirectory()
        }
    }

    func navigate(
        to url: URL,
        recordsHistory: Bool = true,
        restoringSelectionAt selectionURL: URL? = nil
    ) {
        selectionURLToRestoreAfterRefresh = selectionURL?.standardizedFileURL
        var tab = activeTab
        if recordsHistory, tab.url != url {
            tab.backHistory.append(tab.url)
            tab.forwardHistory.removeAll()
        }
        tab.url = url.standardizedFileURL
        activeTab = tab
        loadCurrentDirectory()
    }

    func navigateToEnteredLocation(_ input: String) async -> Bool {
        guard !isResolvingLocation else { return false }
        isResolvingLocation = true
        locationErrorMessage = nil
        let baseDirectory = currentURL
        do {
            let destination = try await pathResolver.resolve(input, relativeTo: baseDirectory)
            guard currentURL == baseDirectory else {
                isResolvingLocation = false
                return false
            }
            navigate(to: destination)
            isResolvingLocation = false
            return true
        } catch {
            locationErrorMessage = error.localizedDescription
            isResolvingLocation = false
            return false
        }
    }

    func clearLocationError() {
        locationErrorMessage = nil
    }

    func goBack() {
        var tab = activeTab
        guard let destination = tab.backHistory.popLast() else { return }
        selectionURLToRestoreAfterRefresh = nil
        tab.forwardHistory.append(tab.url)
        tab.url = destination
        activeTab = tab
        loadCurrentDirectory()
    }

    func goForward() {
        var tab = activeTab
        guard let destination = tab.forwardHistory.popLast() else { return }
        selectionURLToRestoreAfterRefresh = nil
        tab.backHistory.append(tab.url)
        tab.url = destination
        activeTab = tab
        loadCurrentDirectory()
    }

    @discardableResult
    func goUp() -> Bool {
        goUp(from: currentURL)
    }

    @discardableResult
    func goUp(from directory: URL) -> Bool {
        let departedDirectory = directory.standardizedFileURL
        let parent = departedDirectory.deletingLastPathComponent().standardizedFileURL
        guard parent.path != departedDirectory.path else { return false }
        navigate(to: parent, restoringSelectionAt: departedDirectory)
        return true
    }

    @discardableResult
    func enterSelectedFolderFromKeyboard() -> Bool {
        guard selection.count == 1,
              let selectedID = selection.first,
              let item = visibleItems.first(where: { $0.id == selectedID }),
              item.isFolder else { return false }
        navigate(to: item.url)
        return true
    }

    func moveColumnSelection(by offset: Int, in columnID: BrowserColumn.ID) -> Bool {
        guard offset == -1 || offset == 1,
              let columnIndex = columns.firstIndex(where: { $0.id == columnID }) else { return false }
        let column = columns[columnIndex]
        let visibleItems = displayedItems(from: column.items)
        guard !column.isLoading, !visibleItems.isEmpty else { return false }

        let selectedIndex = visibleItems.firstIndex { $0.id == column.selectedItemID }
        let nextIndex: Int
        if let selectedIndex {
            nextIndex = min(max(selectedIndex + offset, 0), visibleItems.count - 1)
            guard nextIndex != selectedIndex else { return true }
        } else {
            nextIndex = offset > 0 ? 0 : visibleItems.count - 1
        }

        selectColumnItem(visibleItems[nextIndex], in: columnID)
        return true
    }

    func enterSelectedColumnFolderFromKeyboard(in columnID: BrowserColumn.ID) -> BrowserColumn.ID? {
        guard let columnIndex = columns.firstIndex(where: { $0.id == columnID }),
              let selectedID = columns[columnIndex].selectedItemID,
              let folder = displayedItems(from: columns[columnIndex].items)
                .first(where: { $0.id == selectedID && $0.isFolder }) else { return nil }

        let childDirectory = folder.url.standardizedFileURL
        if let childColumn = columns.dropFirst(columnIndex + 1).first(where: {
            $0.directory.standardizedFileURL == childDirectory
        }) {
            if !childColumn.isLoading,
               let firstItem = displayedItems(from: childColumn.items).first {
                selectColumnItem(firstItem, in: childColumn.id)
            }
            return childColumn.id
        }

        selectColumnItem(folder, in: columnID)
        return childDirectory
    }

    func returnToPreviousColumnFromKeyboard(in columnID: BrowserColumn.ID) -> BrowserColumn.ID? {
        guard let columnIndex = columns.firstIndex(where: { $0.id == columnID }),
              columnIndex > 0 else { return nil }

        let parentColumn = columns[columnIndex - 1]
        guard let selectedID = parentColumn.selectedItemID,
              let parentFolder = parentColumn.items.first(where: {
                  $0.id == selectedID && $0.isFolder
              }),
              parentFolder.url.standardizedFileURL == columns[columnIndex].directory.standardizedFileURL else {
            return nil
        }

        // Like Finder, only move focus back one column: earlier columns and the current column
        // stay visible, and nothing is reloaded.
        selectionURLToRestoreAfterRefresh = nil
        columnLoadTask?.cancel()
        if columns.count > columnIndex + 1 {
            columns.removeSubrange((columnIndex + 1)...)
        }
        columns[columnIndex].selectedItemID = nil
        selection = [parentFolder.id]
        updateActiveTabURL(parentFolder.url)
        items = columns[columnIndex].items
        errorMessage = columns[columnIndex].errorMessage
        syncDirectoryObservers()
        return parentColumn.id
    }

    /// Where items transferred into this pane land. In the column browser this is the folder the
    /// visible selection lives in, not a folder that is merely selected but not opened.
    var transferDestinationURL: URL {
        guard viewMode == .columns, let lastColumn = columns.last else { return currentURL }
        return columns.last(where: { $0.selectedItemID != nil })?.directory ?? lastColumn.directory
    }

    func open(_ item: FileItem) {
        if item.isFolder {
            navigate(to: item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    /// Opens several items at once. A pane can show only one folder, so folders are entered
    /// only when a single folder is targeted; everything else goes to its default application.
    func open(_ targets: [FileItem]) {
        if targets.count == 1, let item = targets.first {
            open(item)
            return
        }
        for item in targets where !item.isFolder {
            NSWorkspace.shared.open(item.url)
        }
    }

    /// Reloads the visible contents. In the column browser this keeps the column path and
    /// per-column selection; explicit navigation uses `loadCurrentDirectory()` instead.
    func refresh() {
        let currentDirectory = currentURL.standardizedFileURL
        guard viewMode == .columns,
              !hasPendingDirectoryLoad,
              columns.contains(where: { $0.directory.standardizedFileURL == currentDirectory }) else {
            loadCurrentDirectory()
            return
        }
        refreshColumnsInPlace()
    }

    private func loadCurrentDirectory() {
        let directory = currentURL
        let selectionURLToRestore = selectionURLToRestoreAfterRefresh
        let showsHiddenFiles = showsHiddenFiles
        let provider = provider

        refreshTask?.cancel()
        columnLoadTask?.cancel()
        isLoading = true
        hasPendingDirectoryLoad = true
        refreshTask = Task {
            do {
                let refreshedItems = try await provider.contents(
                    of: directory,
                    showsHiddenFiles: showsHiddenFiles
                )

                guard !Task.isCancelled, currentURL == directory else { return }
                items = refreshedItems
                let restoredItem = selectionURLToRestore.flatMap { selectionURL in
                    refreshedItems.first {
                        $0.url.standardizedFileURL == selectionURL
                    }
                }
                columns = [
                    BrowserColumn(
                        directory: directory,
                        items: refreshedItems,
                        selectedItemID: viewMode == .columns ? restoredItem?.id : nil,
                        isLoading: false,
                        errorMessage: nil
                    )
                ]
                if let selectionURLToRestore {
                    selection = restoredItem.map { [$0.id] } ?? []
                    if selectionURLToRestoreAfterRefresh == selectionURLToRestore {
                        selectionURLToRestoreAfterRefresh = nil
                    }
                } else {
                    selection = selection.intersection(Set(refreshedItems.map(\.id)))
                }
                isLoading = false
                hasPendingDirectoryLoad = false
                errorMessage = nil
                syncDirectoryObservers()
                await updateAvailableCapacity(for: directory)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, currentURL == directory else { return }
                items = []
                columns = [
                    BrowserColumn(
                        directory: directory,
                        items: [],
                        selectedItemID: nil,
                        isLoading: false,
                        errorMessage: error.localizedDescription
                    )
                ]
                selection = []
                selectionURLToRestoreAfterRefresh = nil
                isLoading = false
                hasPendingDirectoryLoad = false
                errorMessage = error.localizedDescription
                availableCapacity = nil
                syncDirectoryObservers()
            }
        }
    }

    private func refreshColumnsInPlace() {
        let snapshot = columns
        let showsHiddenFiles = showsHiddenFiles
        let provider = provider

        refreshTask?.cancel()
        columnLoadTask?.cancel()
        refreshTask = Task {
            var results: [Result<[FileItem], Error>] = []
            for column in snapshot {
                do {
                    let columnItems = try await provider.contents(
                        of: column.directory,
                        showsHiddenFiles: showsHiddenFiles
                    )
                    results.append(.success(columnItems))
                } catch is CancellationError {
                    return
                } catch {
                    // Columns after an unreadable directory are dropped, so there is no need to read them.
                    results.append(.failure(error))
                    break
                }
            }
            guard !Task.isCancelled, columns.map(\.id) == snapshot.map(\.id) else { return }
            applyColumnRefresh(snapshot: snapshot, results: results)
            await updateAvailableCapacity(for: currentURL)
        }
    }

    private func applyColumnRefresh(snapshot: [BrowserColumn], results: [Result<[FileItem], Error>]) {
        var refreshedColumns: [BrowserColumn] = []
        for (index, result) in results.enumerated() {
            var column = snapshot[index]
            column.isLoading = false
            switch result {
            case let .failure(error):
                column.items = []
                column.selectedItemID = nil
                column.errorMessage = error.localizedDescription
                refreshedColumns.append(column)
            case let .success(columnItems):
                column.items = columnItems
                column.errorMessage = nil
                if let selectedID = column.selectedItemID,
                   !columnItems.contains(where: { $0.id == selectedID }) {
                    column.selectedItemID = nil
                }
                refreshedColumns.append(column)
            }
            guard index + 1 < snapshot.count,
                  let selectedID = column.selectedItemID,
                  let selectedItem = column.items.first(where: { $0.id == selectedID }),
                  selectedItem.isFolder,
                  selectedItem.url.standardizedFileURL == snapshot[index + 1].directory.standardizedFileURL else {
                break
            }
        }

        columns = refreshedColumns
        let currentColumn = refreshedColumns.last(where: { $0.errorMessage == nil }) ?? refreshedColumns[0]
        let currentDirectory = currentColumn.directory.standardizedFileURL
        if activeTab.url.standardizedFileURL != currentDirectory {
            // A refresh correcting the location for a removed folder is not user navigation, so
            // it does not add a history entry.
            var tab = activeTab
            tab.url = currentDirectory
            activeTab = tab
        }
        items = currentColumn.items
        errorMessage = currentColumn.errorMessage
        let availableIDs = Set(refreshedColumns.flatMap(\.items).map(\.id))
        selection.formIntersection(availableIDs)
        syncDirectoryObservers()
    }

    private func updateAvailableCapacity(for directory: URL) async {
        let capacity = await provider.availableCapacity(for: directory)
        guard !Task.isCancelled, currentURL == directory else { return }
        availableCapacity = capacity
    }

    func setDirectoryObservationEnabled(_ enabled: Bool) {
        observesDirectories = enabled
        syncDirectoryObservers()
    }

    private func syncDirectoryObservers() {
        let observedDirectories = directoriesToObserve
        for (directory, observer) in directoryObservers where !observedDirectories.contains(directory) {
            observer.stop()
            directoryObservers[directory] = nil
        }
        for directory in observedDirectories where directoryObservers[directory] == nil {
            let observer = LocalDirectoryObserver()
            observer.observe(directory) { [weak self] in self?.refresh() }
            directoryObservers[directory] = observer
        }
    }

    private var directoriesToObserve: Set<URL> {
        guard observesDirectories else { return [] }
        if viewMode == .columns, !columns.isEmpty {
            return Set(columns.map { $0.directory.standardizedFileURL })
        }
        return [currentURL.standardizedFileURL]
    }

    func toggleHiddenFiles() {
        showsHiddenFiles.toggle()
        loadCurrentDirectory()
    }

    func createFolder(named name: String) {
        guard !isPerformingOperation else { return }
        let directory = currentURL
        let provider = provider
        beginOperation()
        operationTask = Task {
            do {
                let folder = try await provider.createFolder(named: name, in: directory)
                guard !Task.isCancelled else { return }
                finishOperation()
                refresh()
                selection = [folder]
            } catch is CancellationError {
                finishOperation()
            } catch {
                finishOperation(error: error)
            }
        }
    }

    func rename(_ item: FileItem, to newName: String) {
        guard !isPerformingOperation else { return }
        let provider = provider
        beginOperation()
        operationTask = Task {
            do {
                let destination = try await provider.rename(item.url, to: newName)
                guard !Task.isCancelled else { return }
                finishOperation()
                remapTabs(from: item.url, to: destination)
                loadCurrentDirectory()
                selection = destination.deletingLastPathComponent().standardizedFileURL == currentURL.standardizedFileURL
                    ? [destination]
                    : []
            } catch is CancellationError {
                finishOperation()
            } catch {
                finishOperation(error: error)
            }
        }
    }

    func trashSelection() {
        trash(selectedItems)
    }

    func trash(_ items: [FileItem]) {
        guard !isPerformingOperation, !items.isEmpty else { return }
        let provider = provider
        beginOperation()
        operationTask = Task {
            var failures: [Error] = []
            for item in items {
                guard !Task.isCancelled else { break }
                do {
                    try await provider.moveToTrash(item.url)
                } catch {
                    failures.append(error)
                }
            }
            guard !Task.isCancelled else {
                finishOperation()
                return
            }
            isPerformingOperation = false
            refresh()
            if let firstFailure = failures.first {
                operationErrorMessage = L10n.format(
                    "%lld items could not be moved to the Trash: %@",
                    Int64(failures.count),
                    firstFailure.localizedDescription
                )
            } else {
                operationErrorMessage = nil
            }
        }
    }

    func dismissOperationError() {
        operationErrorMessage = nil
    }

    func previewSelection() {
        preview(selectedItems)
    }

    func preview(_ targets: [FileItem]) {
        QuickLookCoordinator.shared.show(urls: targets.map(\.url))
    }

    func revealSelectionInFinder() {
        reveal(selectedItems)
    }

    func reveal(_ targets: [FileItem]) {
        guard !targets.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(targets.map(\.url))
    }

    func setSort(_ newSort: FileSort) {
        if sort == newSort {
            sortAscending.toggle()
        } else {
            sort = newSort
            sortAscending = true
        }
        columns = columns.map { column in
            var updatedColumn = column
            updatedColumn.items = sortedItems(column.items)
            return updatedColumn
        }
    }

    private func compare<T: Comparable>(_ lhs: T?, _ rhs: T?) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            if lhs == rhs { return .orderedSame }
            return lhs < rhs ? .orderedAscending : .orderedDescending
        case (nil, nil):
            return .orderedSame
        case (nil, _?):
            return .orderedDescending
        case (_?, nil):
            return .orderedAscending
        }
    }

    private func beginOperation() {
        operationErrorMessage = nil
        isPerformingOperation = true
    }

    private func finishOperation(error: Error? = nil) {
        isPerformingOperation = false
        operationErrorMessage = error?.localizedDescription
    }

    private func updateActiveTabURL(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        var tab = activeTab
        guard tab.url.standardizedFileURL != standardizedURL else { return }
        tab.backHistory.append(tab.url)
        tab.forwardHistory.removeAll()
        tab.url = standardizedURL
        activeTab = tab
    }

    private func remapTabs(from source: URL, to destination: URL) {
        tabs = tabs.map { tab in
            var updatedTab = tab
            updatedTab.url = remapping(tab.url, from: source, to: destination)
            updatedTab.backHistory = tab.backHistory.map {
                remapping($0, from: source, to: destination)
            }
            updatedTab.forwardHistory = tab.forwardHistory.map {
                remapping($0, from: source, to: destination)
            }
            return updatedTab
        }
    }

    private func remapping(_ url: URL, from source: URL, to destination: URL) -> URL {
        let standardizedURL = url.standardizedFileURL
        let standardizedSource = source.standardizedFileURL
        let standardizedDestination = destination.standardizedFileURL
        guard standardizedURL == standardizedSource ||
                standardizedURL.path.hasPrefix(standardizedSource.path + "/") else {
            return url
        }

        let relativePath = String(standardizedURL.path.dropFirst(standardizedSource.path.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relativePath.isEmpty else { return standardizedDestination }
        return standardizedDestination.appendingPathComponent(relativePath, isDirectory: true)
    }
}
