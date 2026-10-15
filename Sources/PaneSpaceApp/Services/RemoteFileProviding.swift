import Foundation
import Synchronization

/// What a cloud drive provider offers beyond the shared browsing primitives: looking up single
/// items and moving bytes to and from the Mac. Transfers build on these, so a provider never has
/// to know about the operation queue.
protocol RemoteFileProviding: FileProviding {
    /// The item at `url`, or nil when nothing is there.
    func item(at url: URL) async throws -> FileItem?
    /// Writes the file at `url` to `localURL`, reporting each chunk's byte count to `progress`.
    /// Returns the file's name as saved, which differs from the remote name when the service
    /// converts the file, as Google does for its own document formats.
    @discardableResult
    func download(_ url: URL, to localURL: URL, progress: @escaping @Sendable (Int64) -> Void) async throws -> String
    /// Uploads a local file into `directory` under `name`, failing if that name is taken.
    func upload(
        _ localURL: URL,
        named name: String,
        into directory: URL,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws -> URL
    /// Moves an item to another folder of the same drive, giving it `name` there.
    func move(_ item: URL, into directory: URL, named name: String) async throws -> URL
    /// Free space left in the drive, if the service reports it.
    func availableCapacity() async -> Int64?
}

extension RemoteFileProviding {
    func availableCapacity(for directory: URL) async -> Int64? {
        await availableCapacity()
    }

    /// Opening or previewing a cloud file needs a local copy; it goes into a fresh folder in the
    /// caches directory so two files with the same name never collide.
    func materialize(_ item: URL) async throws -> URL {
        let folder = CloudCache.directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let partial = folder.appendingPathComponent(".download")
        let savedName = try await download(item, to: partial) { _ in }
        let destination = folder.appendingPathComponent(savedName)
        try FileManager.default.moveItem(at: partial, to: destination)
        return destination
    }
}

enum CloudCache {
    static var directory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("org.panespace.app/Cloud", isDirectory: true)
    }

    /// Opened copies are disposable; clearing them at launch keeps the cache from growing.
    static func clear() {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Connected cloud providers by account. Shared by every pane and the transfer queue, and
/// updated by `CloudAccountsModel` as accounts are connected and removed.
final class CloudProviderRegistry: Sendable {
    private let providers = Mutex<[UUID: any RemoteFileProviding]>([:])

    func provider(for accountID: UUID) -> (any RemoteFileProviding)? {
        providers.withLock { $0[accountID] }
    }

    func provider(for url: URL) throws -> any RemoteFileProviding {
        guard let location = CloudLocation(url), let provider = provider(for: location.accountID) else {
            throw CloudError.accountNotConnected
        }
        return provider
    }

    func register(_ provider: any RemoteFileProviding, for accountID: UUID) {
        providers.withLock { $0[accountID] = provider }
    }

    func remove(_ accountID: UUID) {
        _ = providers.withLock { $0.removeValue(forKey: accountID) }
    }
}

/// Serves local folders and cloud drives through one provider, chosen by each URL's scheme, so a
/// pane can move between them without knowing which kind of storage it shows.
struct RoutingFileProvider: FileProviding {
    let local: FileProviding
    let cloud: CloudProviderRegistry

    init(local: FileProviding = LocalFileProvider(), cloud: CloudProviderRegistry) {
        self.local = local
        self.cloud = cloud
    }

    private func provider(for url: URL) throws -> FileProviding {
        CloudLocation.isCloud(url) ? try cloud.provider(for: url) : local
    }

    func contents(of directory: URL, showsHiddenFiles: Bool) async throws -> [FileItem] {
        try await provider(for: directory).contents(of: directory, showsHiddenFiles: showsHiddenFiles)
    }

    func contentBatches(of directory: URL, showsHiddenFiles: Bool) -> AsyncThrowingStream<[FileItem], Error> {
        do {
            return try provider(for: directory).contentBatches(of: directory, showsHiddenFiles: showsHiddenFiles)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
    }

    func createFolder(named name: String, in directory: URL) async throws -> URL {
        try await provider(for: directory).createFolder(named: name, in: directory)
    }

    func rename(_ item: URL, to newName: String) async throws -> URL {
        try await provider(for: item).rename(item, to: newName)
    }

    func moveToTrash(_ item: URL) async throws -> URL? {
        try await provider(for: item).moveToTrash(item)
    }

    func availableCapacity(for directory: URL) async -> Int64? {
        guard let provider = try? provider(for: directory) else { return nil }
        return await provider.availableCapacity(for: directory)
    }

    func materialize(_ item: URL) async throws -> URL {
        try await provider(for: item).materialize(item)
    }
}
