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
    @State private var droppedURLs: [URL] = []
    @State private var showsDropChoices = false

    var body: some View {
        VStack(spacing: 0) {
            TabStripView(model: model, slot: slot)

            if addressBarPosition == "top" {
                PathBarView(model: model, slot: slot)
                Divider()
            }

            paneContent

            if let operationErrorMessage = model.operationErrorMessage {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(operationErrorMessage)
                        .font(.callout)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Button {
                        model.dismissOperationError()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss error")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.orange.opacity(0.08))
            }

            if addressBarPosition == "bottom" {
                Divider()
                PathBarView(model: model, slot: slot)
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
        .dropDestination(for: URL.self) { urls, _ in
            let localURLs = urls.filter(\.isFileURL)
            guard !localURLs.isEmpty else { return false }
            droppedURLs = localURLs
            showsDropChoices = true
            return true
        }
        .confirmationDialog("Transfer dropped items?", isPresented: $showsDropChoices) {
            Button("Copy Here") {
                appModel.transfer(droppedURLs, from: nil, to: slot, kind: .copy)
            }
            Button("Move Here") {
                appModel.transfer(droppedURLs, from: nil, to: slot, kind: .move)
            }
            Button("Cancel", role: .cancel) {}
        }
        .onDeleteCommand {
            if !model.selection.isEmpty {
                confirmsTrash = true
            }
        }
        .alert("Move to Trash?", isPresented: $confirmsTrash) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) {
                model.trashSelection()
            }
            .disabled(model.isPerformingOperation)
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
                    .disabled(model.isPerformingOperation)
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
        } else if model.visibleItems.isEmpty, model.viewMode == .list {
            ContentUnavailableView(
                L10n.text(model.searchText.isEmpty ? "Empty folder" : "No results"),
                systemImage: model.searchText.isEmpty ? "folder" : "magnifyingglass",
                description: Text(L10n.text(model.searchText.isEmpty ? "There are no items here." : "Try another search term."))
            )
        } else {
            switch model.viewMode {
            case .list:
                FileListView(model: model, slot: slot, compact: appModel.paneLayout.prefersCompactRows)
            case .columns:
                ColumnBrowserView(model: model, slot: slot)
            }
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
                        HStack(spacing: 2) {
                            Button {
                                model.activateTab(tab.id)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "folder.fill")
                                        .font(.caption)
                                        .foregroundStyle(
                                            model.activeTabID == tab.id
                                                ? Color.accentColor
                                                : Color.secondary
                                        )

                                    if pinnedTabStyle != "iconOnly" || model.activeTabID == tab.id {
                                        Text(tab.title)
                                            .lineLimit(1)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(tab.title)
                            .accessibilityAddTraits(
                                model.activeTabID == tab.id ? [.isSelected] : []
                            )

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
                appModel.closePane(at: slot)
            } label: {
                Image(systemName: "minus")
                    .font(.caption2.weight(.semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
            .help("Close pane")
            .accessibilityLabel("Close pane")
        }
    }
}

private struct PathBarView: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject var model: BrowserPaneModel
    let slot: PaneSlot

    @State private var isEditingLocation = false
    @State private var locationText = ""
    @FocusState private var isLocationFocused: Bool

    @AppStorage("showPaneNavigation") private var showPaneNavigation = true
    @AppStorage("showAddressReload") private var showAddressReload = true
    @AppStorage("showAddressActions") private var showAddressActions = true

    var body: some View {
        GeometryReader { geometry in
            Group {
                if isEditingLocation {
                    locationControl
                } else if geometry.size.width >= 540 {
                    HStack(spacing: 6) {
                        navigationControls
                        locationControl
                            .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)
                            .layoutPriority(1)
                        searchField
                            .frame(width: 160)
                        expandedActionControls
                    }
                } else if geometry.size.width >= 400 {
                    HStack(spacing: 6) {
                        navigationControls
                        locationControl
                            .frame(minWidth: 40, maxWidth: .infinity, alignment: .leading)
                            .layoutPriority(1)
                        searchField
                            .frame(width: 86)
                        compactActionControls
                    }
                } else {
                    HStack(spacing: 6) {
                        locationControl
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .layoutPriority(1)
                        searchField
                            .frame(width: 60)
                        compactActionControls
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 36)
        .onChange(of: appModel.locationEditRequest) {
            guard appModel.activePane == slot else { return }
            locationText = model.currentURL.path
            model.clearLocationError()
            isEditingLocation = true
            isLocationFocused = true
        }
        .onChange(of: model.locationErrorMessage) {
            if isEditingLocation, model.locationErrorMessage != nil {
                isLocationFocused = true
            }
        }
        .overlay(alignment: .bottomLeading) {
            if isEditingLocation, let error = model.locationErrorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 10)
                    .offset(y: 16)
                    .accessibilityLabel(error)
            }
        }
        .padding(.bottom, isEditingLocation && model.locationErrorMessage != nil ? 16 : 0)
    }

    @ViewBuilder
    private var locationControl: some View {
        if isEditingLocation {
            HStack(spacing: 4) {
                TextField("Folder path", text: $locationText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isLocationFocused)
                    .onSubmit {
                        Task {
                            if await model.navigateToEnteredLocation(locationText) {
                                isEditingLocation = false
                                isLocationFocused = false
                            }
                        }
                    }
                    .onExitCommand { dismissLocationEditor() }
                Button {
                    dismissLocationEditor()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel location editing")
            }
            .frame(minWidth: 40, maxWidth: .infinity)
            .layoutPriority(1)
        } else {
            BreadcrumbView(model: model)
                .frame(minWidth: 40, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
        }
    }

    private func dismissLocationEditor() {
        isEditingLocation = false
        isLocationFocused = false
        model.clearLocationError()
    }

    @ViewBuilder
    private var navigationControls: some View {
        if showPaneNavigation {
            ControlGroup {
                Button { model.goBack() } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!model.canGoBack)
                .accessibilityLabel("Back")

                Button { model.goForward() } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!model.canGoForward)
                .accessibilityLabel("Forward")
            }
            .controlSize(.small)
            .fixedSize()
        }
    }

    private var searchField: some View {
        TextField("Search", text: $model.searchText)
            .textFieldStyle(.roundedBorder)
    }

    private var expandedActionControls: some View {
        HStack(spacing: 8) {
            viewMenu
            filterMenu

            if showAddressReload {
                Button { model.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .frame(width: 24)
                .help("Refresh")
                .accessibilityLabel("Refresh")
            }

            if showAddressActions {
                actionsMenu
            }
        }
        .fixedSize()
    }

    private var compactActionControls: some View {
        HStack(spacing: 2) {
            viewMenu
            filterMenu

            if showAddressReload {
                Button { model.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .frame(width: 22)
                .help("Refresh")
                .accessibilityLabel("Refresh")
            }

            if showAddressActions {
                actionsMenu
            }
        }
        .fixedSize()
    }

    private var viewMenu: some View {
        Menu {
            viewMenuItems
        } label: {
            Image(systemName: model.viewMode.systemImage)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 24)
        .help("View Mode")
        .accessibilityLabel("View Mode")
    }

    private var filterMenu: some View {
        Menu {
            filterMenuItems
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 24)
        .help("Sort and Filter")
        .accessibilityLabel("Sort and Filter")
    }

    private var actionsMenu: some View {
        Menu {
            actionMenuItems
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 24)
        .help("Actions")
        .accessibilityLabel("Actions")
    }

    @ViewBuilder
    private var viewMenuItems: some View {
        ForEach(BrowserViewMode.allCases) { mode in
            Button {
                model.setViewMode(mode)
            } label: {
                if model.viewMode == mode {
                    Label(L10n.text(mode.title), systemImage: "checkmark")
                } else {
                    Label(L10n.text(mode.title), systemImage: mode.systemImage)
                }
            }
        }
        Divider()
        Button("Icons — Planned") {}.disabled(true)
        Button("Gallery — Planned") {}.disabled(true)
    }

    @ViewBuilder
    private var filterMenuItems: some View {
        ForEach(FileSort.allCases) { option in
            Button {
                model.setSort(option)
            } label: {
                if model.sort == option {
                    Label(L10n.text(option.rawValue), systemImage: model.sortAscending ? "arrow.up" : "arrow.down")
                } else {
                    Text(L10n.text(option.rawValue))
                }
            }
        }

        Divider()

        Button {
            model.toggleHiddenFiles()
        } label: {
            Text(L10n.text(model.showsHiddenFiles ? "Hide Hidden Files" : "Show Hidden Files"))
        }
    }

    @ViewBuilder
    private var actionMenuItems: some View {
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
    }
}

private struct ColumnBrowserView: View {
    @ObservedObject var model: BrowserPaneModel
    let slot: PaneSlot

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(model.columns) { column in
                        ColumnView(model: model, slot: slot, column: column)
                            .frame(width: 250)
                            .id(column.id)
                        Divider()
                    }
                }
            }
            .onChange(of: model.columns.count) {
                guard let lastColumn = model.columns.last else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(lastColumn.id, anchor: .trailing)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }
}

private struct ColumnView: View {
    @ObservedObject var model: BrowserPaneModel
    let slot: PaneSlot
    let column: BrowserColumn

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(column.directory.lastPathComponent.isEmpty ? column.directory.path : column.directory.lastPathComponent)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(L10n.format("%lld items", Int64(column.items.count)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)

            Divider()

            if column.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = column.errorMessage {
                ContentUnavailableView(
                    "Folder unavailable",
                    systemImage: "exclamationmark.folder",
                    description: Text(errorMessage)
                )
            } else if model.displayedItems(from: column.items).isEmpty {
                ContentUnavailableView(
                    L10n.text(model.searchText.isEmpty ? "Empty folder" : "No results"),
                    systemImage: model.searchText.isEmpty ? "folder" : "magnifyingglass"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(model.displayedItems(from: column.items)) { item in
                            Button {
                                model.selectColumnItem(item, in: column.id)
                            } label: {
                                ColumnItemRow(
                                    item: item,
                                    isSelected: column.selectedItemID == item.id
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .draggable(item.url)
                            .accessibilityLabel(item.name)
                            .accessibilityValue(item.isDirectory ? "Folder" : item.kind)
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded {
                                    if !item.isDirectory {
                                        model.open(item)
                                    }
                                }
                            )
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
                                TransferActionsMenu(model: model, slot: slot, item: item)
                                Button("Rename…") { model.renameTarget = item }
                                    .disabled(model.isPerformingOperation)
                                Button("Move to Trash", role: .destructive) {
                                    model.selection = [item.id]
                                    model.trashSelection()
                                }
                                .disabled(model.isPerformingOperation)
                            }
                        }
                    }
                    .padding(4)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct ColumnItemRow: View {
    let item: FileItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(nsImage: item.icon)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
            Text(item.name)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if item.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.callout)
        .padding(.horizontal, 7)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        )
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
    let slot: PaneSlot
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
                    .draggable(item.url)
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
                        TransferActionsMenu(model: model, slot: slot, item: item)
                        Button("Rename…") {
                            model.renameTarget = item
                        }
                        .disabled(model.isPerformingOperation)
                        Button("Move to Trash", role: .destructive) {
                            model.selection = [item.id]
                            model.trashSelection()
                        }
                        .disabled(model.isPerformingOperation)
                    }
            }
        }
        .listStyle(.inset)
    }
}

private struct TransferActionsMenu: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject var model: BrowserPaneModel
    let slot: PaneSlot
    let item: FileItem

    var body: some View {
        if !targets.isEmpty {
            Menu("Copy to Pane") {
                ForEach(targets) { target in
                    Button(title(for: target)) {
                        appModel.transfer(urls, from: slot, to: target, kind: .copy)
                    }
                }
            }
            Menu("Move to Pane") {
                ForEach(targets) { target in
                    Button(title(for: target)) {
                        appModel.transfer(urls, from: slot, to: target, kind: .move)
                    }
                }
            }
        }
    }

    private var targets: [PaneSlot] {
        appModel.paneLayout.visibleSlots.filter { $0 != slot }
    }

    private var urls: [URL] {
        if model.selection.contains(item.id) {
            return model.selectedItems.map(\.url)
        }
        return [item.url]
    }

    private func title(for target: PaneSlot) -> String {
        let index = PaneSlot.allCases.firstIndex(of: target) ?? 0
        return L10n.format("Pane %lld", Int64(index + 1))
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
            Text(L10n.format("%lld items", Int64(model.visibleItems.count)))
            if !model.selection.isEmpty {
                Text("•")
                Text(L10n.format("%lld selected", Int64(model.selection.count)))
            }

            if let freeSpace = model.availableCapacity {
                Text("•")
                Text(L10n.format("%@ available", ByteCountFormatter.string(fromByteCount: freeSpace, countStyle: .file)))
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

}
