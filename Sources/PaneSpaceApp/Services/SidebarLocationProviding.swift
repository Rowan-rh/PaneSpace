import Foundation

struct SidebarLocationSnapshot: Sendable {
    let favorites: [SidebarLocation]
    let volumes: [SidebarLocation]
}

protocol SidebarLocationProviding: Sendable {
    func snapshot() async -> SidebarLocationSnapshot
}

actor LocalSidebarLocationProvider: SidebarLocationProviding {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func snapshot() -> SidebarLocationSnapshot {
        let home = fileManager.homeDirectoryForCurrentUser
        let favorites = [
            SidebarLocation(id: "home", title: "Home", systemImage: "house", url: home),
            SidebarLocation(
                id: "desktop",
                title: "Desktop",
                systemImage: "menubar.dock.rectangle",
                url: fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first ?? home
            ),
            SidebarLocation(
                id: "documents",
                title: "Documents",
                systemImage: "doc",
                url: fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ?? home
            ),
            SidebarLocation(
                id: "downloads",
                title: "Downloads",
                systemImage: "arrow.down.circle",
                url: fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? home
            ),
            SidebarLocation(
                id: "applications",
                title: "Applications",
                systemImage: "square.grid.2x2",
                url: URL(fileURLWithPath: "/Applications", isDirectory: true)
            )
        ]

        let volumeKeys: Set<URLResourceKey> = [.volumeNameKey]
        let volumeURLs = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(volumeKeys),
            options: [.skipHiddenVolumes]
        ) ?? []
        let volumes = volumeURLs.map { url in
            let name = (try? url.resourceValues(forKeys: volumeKeys).volumeName) ?? url.lastPathComponent
            return SidebarLocation(
                id: "volume:\(url.path)",
                title: name,
                systemImage: "externaldrive",
                url: url
            )
        }

        return SidebarLocationSnapshot(
            favorites: favorites,
            volumes: volumes
        )
    }
}
