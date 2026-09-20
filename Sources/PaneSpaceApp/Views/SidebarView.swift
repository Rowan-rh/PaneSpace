import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var appModel: AppModel

    @AppStorage("showWorkspaceGroup") private var showWorkspaceGroup = true
    @AppStorage("showVolumesGroup") private var showVolumesGroup = true
    @AppStorage("showTagsGroup") private var showTagsGroup = true

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $appModel.sidebarSelection) {
                Section("Favorites") {
                    ForEach(SidebarLocation.favorites) { location in
                        locationRow(location)
                    }
                }

                if showWorkspaceGroup {
                    Section("Workspaces") {
                        ForEach(workspaces) { location in
                            locationRow(location)
                        }
                    }
                }

                if showVolumesGroup {
                    Section("Locations") {
                        ForEach(SidebarLocation.volumes) { location in
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
    }

    private var workspaces: [SidebarLocation] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            SidebarLocation(id: "workspace:home", title: "Home Workspace", systemImage: "square.grid.2x2", url: home),
            SidebarLocation(id: "workspace:code", title: "Development", systemImage: "hammer", url: home.appendingPathComponent("Code", isDirectory: true)),
            SidebarLocation(id: "workspace:downloads", title: "Downloads Review", systemImage: "tray.full", url: home.appendingPathComponent("Downloads", isDirectory: true))
        ]
        return candidates.filter { FileManager.default.fileExists(atPath: $0.url.path) }
    }

    private func locationRow(_ location: SidebarLocation) -> some View {
        Label(location.title, systemImage: location.systemImage)
            .tag(location.id)
            .contentShape(Rectangle())
            .onTapGesture {
                appModel.sidebarSelection = location.id
                appModel.open(location.url)
            }
    }

    private func tagRow(_ title: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            Text(title)
            Spacer()
        }
        .foregroundStyle(.secondary)
    }
}
