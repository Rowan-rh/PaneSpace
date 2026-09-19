import Foundation

struct SidebarLocation: Identifiable, Hashable {
    let id: String
    let title: String
    let systemImage: String
    let url: URL

    static var favorites: [SidebarLocation] {
        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser
        return [
            SidebarLocation(id: "home", title: "Home", systemImage: "house", url: home),
            SidebarLocation(id: "desktop", title: "Desktop", systemImage: "menubar.dock.rectangle", url: manager.urls(for: .desktopDirectory, in: .userDomainMask).first ?? home),
            SidebarLocation(id: "documents", title: "Documents", systemImage: "doc", url: manager.urls(for: .documentDirectory, in: .userDomainMask).first ?? home),
            SidebarLocation(id: "downloads", title: "Downloads", systemImage: "arrow.down.circle", url: manager.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? home),
            SidebarLocation(id: "applications", title: "Applications", systemImage: "square.grid.2x2", url: URL(fileURLWithPath: "/Applications"))
        ]
    }

    static var volumes: [SidebarLocation] {
        let keys: [URLResourceKey] = [.volumeNameKey]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []
        return urls.map { url in
            let name = (try? url.resourceValues(forKeys: Set(keys)).volumeName) ?? url.lastPathComponent
            return SidebarLocation(id: "volume:\(url.path)", title: name, systemImage: "externaldrive", url: url)
        }
    }
}
