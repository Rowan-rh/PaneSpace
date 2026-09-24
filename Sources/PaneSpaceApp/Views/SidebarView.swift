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
                        ForEach(model.workspaces) { location in
                            locationRow(location)
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
                model.refresh()
            }
        }
    }

    private var navigableLocations: [SidebarLocation] {
        model.favorites
            + (showWorkspaceGroup ? model.workspaces : [])
            + (showVolumesGroup ? model.volumes : [])
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
