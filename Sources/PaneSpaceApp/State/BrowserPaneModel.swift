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
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var renameTarget: FileItem?

    private let provider: FileProviding
    private var refreshTask: Task<Void, Never>?

    init(url: URL = FileManager.default.homeDirectoryForCurrentUser, provider: FileProviding = LocalFileProvider()) {
        let tab = BrowserTab(url: url)
        self.tabs = [tab]
        self.activeTabID = tab.id
        self.provider = provider
        refresh()
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
        let filtered = searchText.isEmpty
            ? items
            : items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }

        return filtered.sorted { lhs, rhs in
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
        isLoading = true
        refreshTask = Task {
            do {
                let refreshedItems = try await Task.detached(priority: .userInitiated) {
                    try provider.contents(of: directory, showsHiddenFiles: showsHiddenFiles)
                }.value

                guard !Task.isCancelled, currentURL == directory else { return }
                items = refreshedItems
                selection = selection.intersection(Set(refreshedItems.map(\.id)))
                isLoading = false
                errorMessage = nil
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, currentURL == directory else { return }
                items = []
                selection = []
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func toggleHiddenFiles() {
        showsHiddenFiles.toggle()
        refresh()
    }

    func createFolder(named name: String) {
        do {
            let folder = try provider.createFolder(named: name, in: currentURL)
            refresh()
            selection = [folder]
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rename(_ item: FileItem, to newName: String) {
        do {
            let destination = try provider.rename(item.url, to: newName)
            refresh()
            selection = [destination]
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func trashSelection() {
        do {
            let selectedItems = items.filter { selection.contains($0.id) }
            for item in selectedItems {
                try provider.moveToTrash(item.url)
            }
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func previewSelection() {
        let urls = visibleItems.filter { selection.contains($0.id) }.map(\.url)
        QuickLookCoordinator.shared.show(urls: urls)
    }

    func revealSelectionInFinder() {
        let urls = visibleItems.filter { selection.contains($0.id) }.map(\.url)
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
}
