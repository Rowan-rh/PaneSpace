import AppKit
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = SidebarModel()

    @AppStorage("showWorkspaceGroup") private var showWorkspaceGroup = true
    @AppStorage("showVolumesGroup") private var showVolumesGroup = true
    @AppStorage("showTagsGroup") private var showTagsGroup = true

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $appModel.sidebarSelection) {
                Section("Favorites") {
                    ForEach(model.favorites) { location in
                        locationRow(location)
                    }
                }

                if showWorkspaceGroup {
                    Section("Workspaces") {
                        ForEach(workspaceShortcuts.shortcuts) { shortcut in
                            workspaceRow(shortcut)
                        }
                        if workspaceShortcuts.shortcuts.isEmpty {
                            Text("Add workspaces in Settings")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if showVolumesGroup {
                    Section("Locations") {
                        ForEach(model.volumes) { location in
                            locationRow(location)
                        }

                        Label("Connect to Server", systemImage: "network")
                            .foregroundStyle(.secondary)
                            .help("Remote providers are planned")
                    }
                }

                if showTagsGroup {
                    Section("Tags") {
                        tagRow("Red", color: .red)
                        tagRow("Orange", color: .orange)
                        tagRow("Yellow", color: .yellow)
                        tagRow("Green", color: .green)
                        tagRow("Blue", color: .blue)
                        tagRow("Purple", color: .purple)
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack(spacing: 12) {
                Button {} label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .disabled(true)
                .help("Add Bookmark — Planned")

                Button {} label: {
                    Image(systemName: "network")
                }
                .buttonStyle(.plain)
                .disabled(true)
                .help("Server Connections — Planned")

                Spacer()

                Button {
                    appModel.isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .frame(height: 34)
        }
        .navigationTitle("PaneSpace")
        // Rows are plain selectable labels: a button inside a selectable list row only reacts
        // to clicks on its text, so clicks elsewhere in the row selected it without navigating.
        .onChange(of: appModel.sidebarSelection) { _, selectedID in
            guard let selectedID,
                  let location = navigableLocations.first(where: { $0.id == selectedID }) else { return }
            appModel.openSidebarLocation(location)
            if selectedID.hasPrefix("workspace:") {
                // The folder may have disappeared since the last check; grey it out if so.
                workspaceShortcuts.refreshAvailability()
            }
        }
        .onChange(of: appModel.activePaneModel.errorMessage) { _, errorMessage in
            // A folder that fails to load may be a workspace that was just moved or deleted.
            if errorMessage != nil {
                workspaceShortcuts.refreshAvailability()
            }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            refreshLocations()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            refreshLocations()
        }
        .onChange(of: appModel.activePaneModel.currentURL) {
            appModel.syncSidebarSelection(with: navigableLocations)
        }
        .onChange(of: appModel.activePane) {
            appModel.syncSidebarSelection(with: navigableLocations)
        }
        .onChange(of: navigableLocations) {
            appModel.syncSidebarSelection(with: navigableLocations)
        }
        .task {
            model.refresh()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                refreshLocations()
            }
        }
    }

    private func refreshLocations() {
        model.refresh()
        workspaceShortcuts.refreshAvailability()
    }

    private var workspaceShortcuts: WorkspaceShortcutsModel {
        appModel.workspaceShortcuts
    }

    private var availableWorkspaceLocations: [SidebarLocation] {
        workspaceShortcuts.shortcuts
            .filter { !workspaceShortcuts.unavailableIDs.contains($0.id) }
            .map {
                SidebarLocation(id: $0.sidebarID, title: $0.name, systemImage: $0.systemImage, url: $0.url)
            }
    }

    private var navigableLocations: [SidebarLocation] {
        model.favorites
            + (showWorkspaceGroup ? availableWorkspaceLocations : [])
            + (showVolumesGroup ? model.volumes : [])
    }

    // Workspace names are user data, so they are shown verbatim rather than looked up for
    // localization. Missing folders stay listed but untagged, which makes them unselectable and
    // drops a selection they held when their folder disappeared.
    @ViewBuilder
    private func workspaceRow(_ shortcut: WorkspaceShortcut) -> some View {
        let label = Label(shortcut.name, systemImage: shortcut.systemImage)
        if workspaceShortcuts.unavailableIDs.contains(shortcut.id) {
            label
                .foregroundStyle(.secondary)
                .opacity(0.55)
                .help(L10n.text("This folder is currently unavailable."))
        } else {
            label
                .help((shortcut.path as NSString).abbreviatingWithTildeInPath)
                .tag(shortcut.sidebarID)
        }
    }

    private func locationRow(_ location: SidebarLocation) -> some View {
        Label(L10n.text(location.title), systemImage: location.systemImage)
            .tag(location.id)
    }

    private func tagRow(_ title: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            Text(L10n.text(title))
            Spacer()
        }
        .foregroundStyle(.secondary)
    }
}
