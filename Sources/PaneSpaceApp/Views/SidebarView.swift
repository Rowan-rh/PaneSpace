import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        List(selection: $appModel.sidebarSelection) {
            Section("Favorites") {
                ForEach(SidebarLocation.favorites) { location in
                    locationRow(location)
                }
            }

            Section("Locations") {
                ForEach(SidebarLocation.volumes) { location in
                    locationRow(location)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("PaneSpace")
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
}
