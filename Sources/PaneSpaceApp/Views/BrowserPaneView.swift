import SwiftUI

struct BrowserPaneView: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject var model: BrowserPaneModel
    let slot: PaneSlot

    @AppStorage("addressBarPosition") private var addressBarPosition = "top"
    @AppStorage("showStatusBar") private var showStatusBar = true
    @AppStorage("themeIntensity") private var themeIntensity = 0.12

    @State private var renameText = ""
    @State private var confirmsTrash = false

    var body: some View {
        VStack(spacing: 0) {
            TabStripView(model: model, slot: slot)

            if addressBarPosition == "top" {
                PathBarView(model: model)
                Divider()
            }

            paneContent

            if addressBarPosition == "bottom" {
                Divider()
                PathBarView(model: model)
            }

            if showStatusBar {
                Divider()
                StatusBarView(model: model)
            }
        }
        .background(
            Color.accentColor.opacity(appModel.activePane == slot ? themeIntensity * 0.12 : 0)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(appModel.activePane == slot ? Color.accentColor : Color.clear)
                .frame(height: 2)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            appModel.activePane = slot
        })
        .onDeleteCommand {
            if !model.selection.isEmpty {
                confirmsTrash = true
            }
        }
        .onKeyPress(.space) {
            model.previewSelection()
            return .handled
        }
        .alert("Move to Trash?", isPresented: $confirmsTrash) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) {
                model.trashSelection()
            }
        } message: {
            Text("The selected items will be moved to the Trash.")
        }
        .sheet(item: $model.renameTarget) { item in
            VStack(alignment: .leading, spacing: 16) {
                Text("Rename \(item.name)")
                    .font(.headline)
                TextField("Name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Cancel") { model.renameTarget = nil }
                    Button("Rename") {
                        model.rename(item, to: renameText)
                        model.renameTarget = nil
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 380)
            .onAppear { renameText = item.name }
        }
    }

    @ViewBuilder
    private var paneContent: some View {
        if model.isLoading {
            VStack(spacing: 10) {
                ProgressView()
                Text("Loading folder…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.errorMessage {
            ContentUnavailableView(
                "Folder unavailable",
                systemImage: "exclamationmark.folder",
                description: Text(error)
            )
        } else if model.visibleItems.isEmpty {
            ContentUnavailableView(
                model.searchText.isEmpty ? "Empty folder" : "No results",
                systemImage: model.searchText.isEmpty ? "folder" : "magnifyingglass",
                description: Text(model.searchText.isEmpty ? "There are no items here." : "Try another search term.")
            )
        } else {
            FileListView(model: model, compact: appModel.paneLayout.prefersCompactRows)
        }
    }
}

private struct TabStripView: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject var model: BrowserPaneModel
    let slot: PaneSlot

    @AppStorage("paneCloseButton") private var paneCloseButton = "right"
    @AppStorage("pinnedTabStyle") private var pinnedTabStyle = "iconAndTitle"

    var body: some View {
        HStack(spacing: 4) {
            if paneCloseButton == "left" {
                paneControl
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(model.tabs) { tab in
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill")
                                .font(.caption)
                                .foregroundStyle(model.activeTabID == tab.id ? Color.accentColor : Color.secondary)

                            if pinnedTabStyle != "iconOnly" || model.activeTabID == tab.id {
                                Text(tab.title)
                                    .lineLimit(1)
                            }

                            if model.tabs.count > 1, model.activeTabID == tab.id {
                                Button {
                                    model.closeTab(tab.id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .semibold))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Close tab")
                            }
                        }
                        .font(.callout)
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(model.activeTabID == tab.id ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { model.activateTab(tab.id) }
                    }

                    Button {
                        model.addTab()
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New tab")
                }
                .padding(.horizontal, 6)
            }

            Spacer(minLength: 0)

            if paneCloseButton == "right" {
                paneControl
            }
        }
        .frame(height: 36)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    @ViewBuilder
    private var paneControl: some View {
        if appModel.paneLayout.visiblePaneCount > 1 {
            Button {
                appModel.paneLayout = .single
                appModel.activePane = .primary
            } label: {
                Image(systemName: "minus")
                    .font(.caption2.weight(.semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
            .help("Close extra panes")
        }
    }
}

private struct PathBarView: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject var model: BrowserPaneModel

    @AppStorage("showPaneNavigation") private var showPaneNavigation = true
    @AppStorage("showAddressReload") private var showAddressReload = true
    @AppStorage("showAddressActions") private var showAddressActions = true

    var body: some View {
        HStack(spacing: 6) {
            if showPaneNavigation {
                ControlGroup {
                    Button { model.goBack() } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!model.canGoBack)

                    Button { model.goForward() } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!model.canGoForward)
                }
                .controlSize(.small)
            }

            BreadcrumbView(model: model)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("Search", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 86, idealWidth: 150, maxWidth: 190)

            viewMenu
            filterMenu

            if showAddressReload {
                Button { model.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh")
            }

            if showAddressActions {
                Menu {
                    Button("New Folder") { appModel.requestNewFolder() }
                    Button("Show in Finder") { model.revealSelectionInFinder() }
                        .disabled(model.selection.isEmpty)
                    Divider()
                    Button("Open in Terminal — Planned") {}
                        .disabled(true)
                    Button("Copy Path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.currentURL.path, forType: .string)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 36)
    }

    private var viewMenu: some View {
        Menu {
            Label("List", systemImage: "list.bullet")
            Divider()
            Button("Icons — Planned") {}.disabled(true)
            Button("Columns — Planned") {}.disabled(true)
            Button("Gallery — Planned") {}.disabled(true)
        } label: {
            Image(systemName: "list.bullet")
        }
        .menuStyle(.borderlessButton)
        .frame(width: 24)
        .help("View Mode")
    }

    private var filterMenu: some View {
        Menu {
            ForEach(FileSort.allCases) { option in
                Button {
                    model.setSort(option)
                } label: {
                    if model.sort == option {
                        Label(option.rawValue, systemImage: model.sortAscending ? "arrow.up" : "arrow.down")
                    } else {
                        Text(option.rawValue)
                    }
                }
            }

            Divider()

            Button(model.showsHiddenFiles ? "Hide Hidden Files" : "Show Hidden Files") {
                model.toggleHiddenFiles()
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .menuStyle(.borderlessButton)
        .frame(width: 24)
        .help("Sort and Filter")
    }
}

private struct BreadcrumbView: View {
    @ObservedObject var model: BrowserPaneModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    Button {
                        model.navigate(to: item.url)
                    } label: {
                        HStack(spacing: 4) {
                            if index == 0 {
                                Image(systemName: "externaldrive.fill")
                            }
                            Text(item.title)
                                .lineLimit(1)
                        }
                        .font(.callout)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(index == items.count - 1 ? Color.accentColor.opacity(0.12) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)

                    if index < items.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .help(model.currentURL.path)
    }

    private var items: [(title: String, url: URL)] {
        let components = model.currentURL.standardizedFileURL.pathComponents
        var url = URL(fileURLWithPath: "/", isDirectory: true)
        var result: [(String, URL)] = [("Mac", url)]

        for component in components.dropFirst() {
            url.appendPathComponent(component, isDirectory: true)
            result.append((component, url))
        }
        return result
    }
}

private struct FileListView: View {
    @ObservedObject var model: BrowserPaneModel
    let compact: Bool

    @AppStorage("rowDensity") private var rowDensity = "comfortable"
    @AppStorage("alternateRowBackgrounds") private var alternateRowBackgrounds = false

    var body: some View {
        List(selection: $model.selection) {
            ForEach(Array(model.visibleItems.enumerated()), id: \.element.id) { index, item in
                FileRow(item: item, compact: compact, density: rowDensity)
                    .tag(item.id)
                    .contentShape(Rectangle())
                    .listRowBackground(
                        alternateRowBackgrounds && !index.isMultiple(of: 2)
                            ? Color.secondary.opacity(0.045)
                            : Color.clear
                    )
                    .onTapGesture(count: 2) {
                        model.open(item)
                    }
                    .contextMenu {
                        Button("Open") { model.open(item) }
                        Button("Quick Look") {
                            model.selection = [item.id]
                            model.previewSelection()
                        }
                        Button("Show in Finder") {
                            model.selection = [item.id]
                            model.revealSelectionInFinder()
                        }
                        Divider()
                        Button("Copy to Other Pane — Planned") {}
                            .disabled(true)
                        Button("Rename…") {
                            model.renameTarget = item
                        }
                        Button("Move to Trash", role: .destructive) {
                            model.selection = [item.id]
                            model.trashSelection()
                        }
                    }
            }
        }
        .listStyle(.inset)
    }
}

private struct FileRow: View {
    let item: FileItem
    let compact: Bool
    let density: String

    var body: some View {
        HStack(spacing: 9) {
            Image(nsImage: item.icon)
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)

            if compact {
                VStack(alignment: .leading, spacing: density == "compact" ? 0 : 2) {
                    Text(item.name)
                        .lineLimit(1)
                    Text(item.isDirectory ? item.formattedDate : "\(item.kind)  ·  \(item.formattedSize)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(item.name)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(item.kind)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 124, alignment: .leading)

                Text(item.formattedSize)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 82, alignment: .trailing)

                Text(item.formattedDate)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 146, alignment: .trailing)
            }
        }
        .padding(.vertical, verticalPadding)
    }

    private var iconSize: CGFloat {
        switch density {
        case "compact": 19
        case "spacious": 28
        default: 23
        }
    }

    private var verticalPadding: CGFloat {
        switch density {
        case "compact": 0
        case "spacious": 5
        default: 2
        }
    }
}

private struct StatusBarView: View {
    @ObservedObject var model: BrowserPaneModel

    var body: some View {
        HStack(spacing: 7) {
            Text("\(model.visibleItems.count) items")
            if !model.selection.isEmpty {
                Text("•")
                Text("\(model.selection.count) selected")
            }

            if let freeSpace {
                Text("•")
                Text("\(ByteCountFormatter.string(fromByteCount: freeSpace, countStyle: .file)) available")
            }

            Spacer()

            Button {} label: {
                Image(systemName: "sidebar.right")
            }
            .buttonStyle(.plain)
            .disabled(true)
            .help("Side Preview — Planned")

            Text(model.currentURL.path)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: 220, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 9)
        .frame(height: 24)
    }

    private var freeSpace: Int64? {
        try? model.currentURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
    }
}
