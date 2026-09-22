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

    private let provider: FileProviding
    private var refreshTask: Task<Void, Never>?
    private var columnLoadTask: Task<Void, Never>?
    private var operationTask: Task<Void, Never>?

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
        refresh()
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

    var selectedItems: [FileItem] {
        let availableItems = viewMode == .columns ? columns.flatMap(\.items) : items
        return Array(Dictionary(grouping: availableItems, by: \.id).compactMap { _, values in
            values.first(where: { selection.contains($0.id) })
        })
    }

    func displayedItems(from source: [FileItem]) -> [FileItem] {
        let filtered = searchText.isEmpty
            ? source
            : source.filter { $0.name.localizedCaseInsensitiveContains(searchText) }

        return sortedItems(filtered)
    }

    private func sortedItems(_ source: [FileItem]) -> [FileItem] {
        source.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
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
    }

    func selectColumnItem(_ item: FileItem, in columnID: BrowserColumn.ID) {
        guard let index = columns.firstIndex(where: { $0.id == columnID }) else { return }

        refreshTask?.cancel()
        columnLoadTask?.cancel()
        columns[index].selectedItemID = item.id
        if columns.count > index + 1 {
            columns.removeSubrange((index + 1)...)
        }
        selection = [item.id]

        guard item.isDirectory else {
            let directory = columns[index].directory.standardizedFileURL
            updateActiveTabURL(directory)
            items = columns[index].items
            isLoading = false
            errorMessage = columns[index].errorMessage
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
        activeTabID = id
        refresh()
    }

    func addTab(url: URL? = nil) {
        let tab = BrowserTab(url: url ?? currentURL)
        tabs.append(tab)
        activeTabID = tab.id
        refresh()
    }

    func closeTab(_ id: BrowserTab.ID) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = activeTabID == id
        tabs.remove(at: index)
        if wasActive {
            activeTabID = tabs[min(index, tabs.count - 1)].id
            refresh()
        }
    }

    func navigate(to url: URL, recordsHistory: Bool = true) {
        var tab = activeTab
        if recordsHistory, tab.url != url {
            tab.backHistory.append(tab.url)
            tab.forwardHistory.removeAll()
        }
        tab.url = url.standardizedFileURL
        activeTab = tab
        refresh()
    }

    func goBack() {
        var tab = activeTab
        guard let destination = tab.backHistory.popLast() else { return }
        tab.forwardHistory.append(tab.url)
        tab.url = destination
        activeTab = tab
        refresh()
    }

    func goForward() {
        var tab = activeTab
        guard let destination = tab.forwardHistory.popLast() else { return }
        tab.backHistory.append(tab.url)
        tab.url = destination
        activeTab = tab
        refresh()
    }

    func goUp() {
        let parent = currentURL.deletingLastPathComponent()
        guard parent.path != currentURL.path else { return }
        navigate(to: parent)
    }

    func open(_ item: FileItem) {
        if item.isDirectory {
            navigate(to: item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    func refresh() {
        let directory = currentURL
        let showsHiddenFiles = showsHiddenFiles
        let provider = provider

        refreshTask?.cancel()
        columnLoadTask?.cancel()
        isLoading = true
        refreshTask = Task {
            do {
                let refreshedItems = try await provider.contents(
                    of: directory,
                    showsHiddenFiles: showsHiddenFiles
                )

                guard !Task.isCancelled, currentURL == directory else { return }
                items = refreshedItems
                columns = [
                    BrowserColumn(
                        directory: directory,
                        items: refreshedItems,
                        selectedItemID: nil,
                        isLoading: false,
                        errorMessage: nil
                    )
                ]
                selection = selection.intersection(Set(refreshedItems.map(\.id)))
                isLoading = false
                errorMessage = nil
                let capacity = await provider.availableCapacity(for: directory)
                guard !Task.isCancelled, currentURL == directory else { return }
                availableCapacity = capacity
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
                isLoading = false
                errorMessage = error.localizedDescription
                availableCapacity = nil
            }
        }
    }

    func toggleHiddenFiles() {
        showsHiddenFiles.toggle()
        refresh()
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
                refresh()
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
        guard !isPerformingOperation else { return }
        let items = selectedItems
        guard !items.isEmpty else { return }
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
        let urls = selectedItems.map(\.url)
        QuickLookCoordinator.shared.show(urls: urls)
    }

    func revealSelectionInFinder() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
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
