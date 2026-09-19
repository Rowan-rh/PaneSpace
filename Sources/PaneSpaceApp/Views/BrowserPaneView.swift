import SwiftUI

struct BrowserPaneView: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject var model: BrowserPaneModel
    let slot: PaneSlot

    @State private var renameText = ""
    @State private var confirmsTrash = false

    var body: some View {
        VStack(spacing: 0) {
            TabStripView(model: model)
            PathBarView(model: model)
            Divider()

            if let error = model.errorMessage {
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
                FileListView(model: model, compact: appModel.isDualPane)
            }

            Divider()
            StatusBarView(model: model)
        }
        .background(
            RoundedRectangle(cornerRadius: 0)
                .fill(appModel.activePane == slot ? Color.accentColor.opacity(0.035) : Color.clear)
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
}

private struct TabStripView: View {
    @ObservedObject var model: BrowserPaneModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(model.tabs) { tab in
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(tab.title)
                            .lineLimit(1)
                        if model.tabs.count > 1 {
                            Button {
                                model.closeTab(tab.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
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
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

private struct PathBarView: View {
    @ObservedObject var model: BrowserPaneModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)
            Text(model.currentURL.path)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.head)
                .textSelection(.enabled)

            Spacer(minLength: 8)

            TextField("Search", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 120, idealWidth: 180, maxWidth: 220)

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
            .frame(width: 28)

            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Refresh")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
}

private struct FileListView: View {
    @ObservedObject var model: BrowserPaneModel
    let compact: Bool

    var body: some View {
        List(model.visibleItems, selection: $model.selection) { item in
            FileRow(item: item, compact: compact)
                .tag(item.id)
                .contentShape(Rectangle())
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
                    Button("Rename…") {
                        model.renameTarget = item
                    }
                    Button("Move to Trash", role: .destructive) {
                        model.selection = [item.id]
                        model.trashSelection()
                    }
                }
        }
        .listStyle(.inset)
    }
}

private struct FileRow: View {
    let item: FileItem
    let compact: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: item.icon)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)

            if compact {
                VStack(alignment: .leading, spacing: 2) {
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
                    .frame(width: 110, alignment: .leading)

                Text(item.formattedSize)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 78, alignment: .trailing)

                Text(item.formattedDate)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 138, alignment: .trailing)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct StatusBarView: View {
    @ObservedObject var model: BrowserPaneModel

    var body: some View {
        HStack {
            Text("\(model.visibleItems.count) items")
            if !model.selection.isEmpty {
                Text("•")
                Text("\(model.selection.count) selected")
            }
            Spacer()
            Text(model.currentURL.path)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }
}
