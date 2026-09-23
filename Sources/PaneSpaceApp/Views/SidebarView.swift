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
        .task {
            model.refresh()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                model.refresh()
            }
        }
    }

    private func locationRow(_ location: SidebarLocation) -> some View {
        Button {
            appModel.sidebarSelection = location.id
            appModel.open(location.url)
        } label: {
            Label(L10n.text(location.title), systemImage: location.systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
            .tag(location.id)
            .contentShape(Rectangle())
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
