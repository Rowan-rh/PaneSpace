import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @AppStorage("sidebarWidth") private var sidebarWidth = 196.0
    @AppStorage("accentColor") private var accentColor = "indigo"
    @AppStorage("themeIntensity") private var themeIntensity = 0.12
    @AppStorage("showToolbarNavigation") private var showToolbarNavigation = true

    @State private var newFolderName = "New Folder"
    @State private var showsLayoutPicker = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(
                    min: 164,
                    ideal: CGFloat(sidebarWidth),
                    max: 286
                )
        } detail: {
            PaneWorkspaceView()
                .background(Color(nsColor: .windowBackgroundColor))
                .overlay {
                    accent.opacity(themeIntensity * 0.035)
                        .allowsHitTesting(false)
                }
        }
        .tint(accent)
        .toolbar {
            if showToolbarNavigation {
                ToolbarItemGroup(placement: .navigation) {
                    Button {
                        appModel.activePaneModel.goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!appModel.activePaneModel.canGoBack)
                    .help("Back")

                    Button {
                        appModel.activePaneModel.goForward()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!appModel.activePaneModel.canGoForward)
                    .help("Forward")

                    Button {
                        appModel.activePaneModel.goUp()
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                    .help("Parent Folder")
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    appModel.requestNewFolder()
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .help("New Folder")

                Button {
                    appModel.activePaneModel.addTab()
                } label: {
                    Image(systemName: "plus.square.on.square")
                }
                .help("New Tab")

                Button {
                    showsLayoutPicker.toggle()
                } label: {
                    PaneLayoutGlyph(layout: appModel.paneLayout)
                        .frame(width: 23, height: 17)
                }
                .help("Pane Layout")
                .popover(isPresented: $showsLayoutPicker, arrowEdge: .bottom) {
                    PaneLayoutPicker(selection: $appModel.paneLayout)
                }

                Button {
                    appModel.isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
            }
        }
        .sheet(isPresented: $appModel.isCreatingFolder) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Create a folder")
                    .font(.headline)
                TextField("Folder name", text: $newFolderName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Cancel") {
                        appModel.isCreatingFolder = false
                    }
                    Button("Create") {
                        appModel.activePaneModel.createFolder(named: newFolderName)
                        appModel.isCreatingFolder = false
                        newFolderName = "New Folder"
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 360)
        }
        .sheet(isPresented: $appModel.isShowingSettings) {
            SettingsView()
                .frame(width: 860, height: 620)
        }
    }

    private var accent: Color {
        switch accentColor {
        case "blue": .blue
        case "teal": .teal
        case "green": .green
        case "orange": .orange
        case "pink": .pink
        case "purple": .purple
        default: .indigo
        }
    }
}

private struct PaneWorkspaceView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        switch appModel.paneLayout {
        case .single:
            pane(.primary)
        case .twoColumns:
            HSplitView {
                pane(.primary)
                pane(.secondary)
            }
        case .twoRows:
            VSplitView {
                pane(.primary)
                pane(.secondary)
            }
        case .primaryLeft:
            HSplitView {
                pane(.primary)
                    .layoutPriority(1)
                VSplitView {
                    pane(.secondary)
                    pane(.tertiary)
                }
                .frame(minWidth: 260)
            }
        case .primaryRight:
            HSplitView {
                VSplitView {
                    pane(.secondary)
                    pane(.tertiary)
                }
                .frame(minWidth: 260)
                pane(.primary)
                    .layoutPriority(1)
            }
        case .primaryTop:
            VSplitView {
                pane(.primary)
                    .layoutPriority(1)
                HSplitView {
                    pane(.secondary)
                    pane(.tertiary)
                }
                .frame(minHeight: 220)
            }
        case .primaryBottom:
            VSplitView {
                HSplitView {
                    pane(.secondary)
                    pane(.tertiary)
                }
                .frame(minHeight: 220)
                pane(.primary)
                    .layoutPriority(1)
            }
        case .threeColumns:
            HSplitView {
                pane(.primary)
                pane(.secondary)
                pane(.tertiary)
            }
        case .threeRows:
            VSplitView {
                pane(.primary)
                pane(.secondary)
                pane(.tertiary)
            }
        case .fourGrid:
            VSplitView {
                HSplitView {
                    pane(.primary)
                    pane(.secondary)
                }
                HSplitView {
                    pane(.tertiary)
                    pane(.quaternary)
                }
            }
        case .fourColumns:
            HSplitView {
                pane(.primary)
                pane(.secondary)
                pane(.tertiary)
                pane(.quaternary)
            }
        case .fourRows:
            VSplitView {
                pane(.primary)
                pane(.secondary)
                pane(.tertiary)
                pane(.quaternary)
            }
        }
    }

    private func pane(_ slot: PaneSlot) -> some View {
        BrowserPaneView(model: appModel.pane(for: slot), slot: slot)
            .frame(minWidth: 210, minHeight: 150)
    }
}

struct PaneLayoutPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: PaneLayout

    private let columns = Array(repeating: GridItem(.fixed(60), spacing: 8), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pane Layout")
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(PaneLayout.allCases) { layout in
                    Button {
                        selection = layout
                        dismiss()
                    } label: {
                        PaneLayoutGlyph(layout: layout)
                            .frame(width: 42, height: 30)
                            .padding(7)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selection == layout ? Color.accentColor.opacity(0.16) : Color(nsColor: .controlBackgroundColor))
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selection == layout ? Color.accentColor : Color.clear, lineWidth: 1.5)
                            }
                    }
                    .buttonStyle(.plain)
                    .help(L10n.text(layout.title))
                }
            }

            Text(L10n.text(selection.title))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }
}

struct PaneLayoutGlyph: View {
    let layout: PaneLayout

    var body: some View {
        Canvas { context, size in
            for (index, frame) in layout.normalizedFrames.enumerated() {
                let rect = CGRect(
                    x: frame.minX * size.width,
                    y: frame.minY * size.height,
                    width: frame.width * size.width,
                    height: frame.height * size.height
                ).insetBy(dx: 1, dy: 1)
                let path = Path(roundedRect: rect, cornerRadius: 2)
                context.fill(path, with: .color(index == 0 ? Color.accentColor : Color.secondary.opacity(0.55)))
            }
        }
        .accessibilityLabel(L10n.text(layout.title))
    }
}
