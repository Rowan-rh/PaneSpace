import Foundation

@MainActor
final class SidebarModel: ObservableObject {
    @Published private(set) var favorites: [SidebarLocation] = []
    @Published private(set) var workspaces: [SidebarLocation] = []
    @Published private(set) var volumes: [SidebarLocation] = []

    private let provider: SidebarLocationProviding
    private var refreshTask: Task<Void, Never>?

    init(provider: SidebarLocationProviding = LocalSidebarLocationProvider()) {
        self.provider = provider
    }

    func refresh() {
        let provider = provider
        refreshTask?.cancel()
        refreshTask = Task {
            let snapshot = await provider.snapshot()
            guard !Task.isCancelled else { return }
            favorites = snapshot.favorites
            workspaces = snapshot.workspaces
            volumes = snapshot.volumes
        }
    }
}
