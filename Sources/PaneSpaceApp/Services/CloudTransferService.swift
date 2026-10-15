import Foundation
import Synchronization

/// Sends each transfer to the service that can perform it. Transfers between local folders keep
/// the staged `copyfile` path; anything that touches a cloud drive goes to `CloudTransferService`.
struct RoutingTransferService: FileTransferServicing {
    let local: LocalTransferService
    let cloud: CloudTransferService

    init(local: LocalTransferService = LocalTransferService(), cloud: CloudTransferService) {
        self.local = local
        self.cloud = cloud
    }

    private func service(for urls: URL...) -> FileTransferServicing {
        urls.contains(where: CloudLocation.isCloud) ? cloud : local
    }

    func validate(source: URL, destinationDirectory: URL, kind: FileTransferKind) async throws {
        try await service(for: source, destinationDirectory)
            .validate(source: source, destinationDirectory: destinationDirectory, kind: kind)
    }

    func destination(for source: URL, in directory: URL) async -> URL {
        await service(for: source, directory).destination(for: source, in: directory)
    }

    func isDuplicate(source: URL, in destinationDirectory: URL, kind: FileTransferKind) async -> Bool {
        await service(for: source, destinationDirectory).isDuplicate(source: source, in: destinationDirectory, kind: kind)
    }

    func exists(at url: URL) async -> Bool {
        await service(for: url).exists(at: url)
    }

    func transfer(
        source: URL,
        to destinationDirectory: URL,
        kind: FileTransferKind,
        conflictDecision: FileConflictDecision?,
        progress: TransferByteCounter?
    ) async throws -> LocalTransferOutcome? {
        try await service(for: source, destinationDirectory).transfer(
            source: source,
            to: destinationDirectory,
            kind: kind,
            conflictDecision: conflictDecision,
            progress: progress
        )
    }

    func byteCount(of source: URL) async throws -> Int64 {
        try await service(for: source).byteCount(of: source)
    }

    func removeSourceAfterCopy(_ source: URL) async throws -> URL? {
        try await service(for: source).removeSourceAfterCopy(source)
    }
}

/// Copies and moves items between the Mac and cloud drives, or between drives.
///
/// It follows the safety rules of local transfers: the copy is assembled under a hidden staging
/// name and only renamed into place when complete, a replaced item goes to the Trash (or the
/// drive's recycle bin) only after that, and a move removes its source last. A move inside one
/// drive is done by the service itself, without copying any bytes.
struct CloudTransferService: FileTransferServicing {
    private let registry: CloudProviderRegistry
    private let trashLocalItem: @Sendable (URL) throws -> URL?

    init(
        registry: CloudProviderRegistry,
        trashLocalItem: (@Sendable (URL) throws -> URL?)? = nil
    ) {
        self.registry = registry
        self.trashLocalItem = trashLocalItem ?? { url in
            var resultingURL: NSURL?
            try FileManager().trashItem(at: url, resultingItemURL: &resultingURL)
            return resultingURL as URL?
        }
    }

    func validate(source: URL, destinationDirectory: URL, kind: FileTransferKind) async throws {
        if CloudLocation.isCloud(source) {
            _ = try registry.provider(for: source)
        }
        let sourceParent = Self.comparisonKey(source.deletingLastPathComponent())
        let destinationKey = Self.comparisonKey(destinationDirectory)
        guard sourceParent != destinationKey || kind == .copy else {
            throw LocalTransferError.invalidDestination
        }
        let sourceKey = Self.comparisonKey(source)
        if isFolder(source), destinationKey == sourceKey || destinationKey.hasPrefix(sourceKey + "/") {
            throw LocalTransferError.invalidDestination
        }
        if CloudLocation.isCloud(destinationDirectory) {
            // The folder itself is not looked up: that means listing its parent, which Baidu
            // refuses above an app's granted folder. A missing folder fails the upload instead.
            _ = try registry.provider(for: destinationDirectory)
        } else if !FileManager.default.isWritableFile(atPath: destinationDirectory.path) {
            throw LocalTransferError.destinationNotWritable(name: destinationDirectory.lastPathComponent)
        }
    }

    func destination(for source: URL, in directory: URL) async -> URL {
        Self.child(named: Self.name(of: source), isDirectory: isFolder(source), in: directory)
    }

    func isDuplicate(source: URL, in destinationDirectory: URL, kind: FileTransferKind) async -> Bool {
        kind == .copy &&
            Self.comparisonKey(source.deletingLastPathComponent()) == Self.comparisonKey(destinationDirectory)
    }

    func exists(at url: URL) async -> Bool {
        guard CloudLocation.isCloud(url) else {
            return FileManager.default.fileExists(atPath: url.path) ||
                (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
        }
        guard let provider = try? registry.provider(for: url) else { return false }
        return (try? await provider.item(at: url)) != nil
    }

    func byteCount(of source: URL) async throws -> Int64 {
        guard CloudLocation.isCloud(source) else {
            return (try? LocalFileCopier.byteCount(of: source)) ?? 0
        }
        do {
            let provider = try registry.provider(for: source)
            guard let item = try await provider.item(at: source) else { return 0 }
            return try await remoteByteCount(of: item, provider: provider)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Progress is still shown for the rest of the job when one item cannot be measured.
            return 0
        }
    }

    func removeSourceAfterCopy(_ source: URL) async throws -> URL? {
        if CloudLocation.isCloud(source) {
            return try await registry.provider(for: source).moveToTrash(source)
        }
        return try trashLocalItem(source)
    }

    func transfer(
        source: URL,
        to destinationDirectory: URL,
        kind: FileTransferKind,
        conflictDecision: FileConflictDecision?,
        progress: TransferByteCounter?
    ) async throws -> LocalTransferOutcome? {
        try await validate(source: source, destinationDirectory: destinationDirectory, kind: kind)
        try Task.checkCancellation()

        let decision: FileConflictDecision? = await isDuplicate(source: source, in: destinationDirectory, kind: kind)
            ? .keepBoth
            : conflictDecision
        guard let target = try await target(for: source, in: destinationDirectory, decision: decision) else {
            return nil
        }
        let counter = ByteAccumulator(reportingTo: progress)

        let destination: URL
        let replacedItemInTrash: URL?
        if kind == .move, let sourceLocation = CloudLocation(source), let destinationLocation = CloudLocation(destinationDirectory),
           sourceLocation.accountID == destinationLocation.accountID {
            let provider = try registry.provider(for: source)
            replacedItemInTrash = try await trashIfReplacing(target, decision: decision)
            destination = try await provider.move(source, into: destinationDirectory, named: target.lastPathComponent)
            counter.add(try await byteCount(of: destination))
            // The service moved the item itself, so there is no source left to remove.
            return LocalTransferOutcome(destination: destination, replacedItemInTrash: replacedItemInTrash, sourceInTrash: nil)
        } else if CloudLocation.isCloud(destinationDirectory) {
            (destination, replacedItemInTrash) = try await upload(source, as: target, decision: decision, counter: counter)
        } else {
            guard let downloaded = try await download(source, as: target, decision: decision, counter: counter) else {
                return nil
            }
            (destination, replacedItemInTrash) = downloaded
        }

        var sourceInTrash: URL?
        if kind == .move {
            do {
                sourceInTrash = try await removeSourceAfterCopy(source)
            } catch {
                throw LocalTransferError.sourceRemovalFailed(destination: destination, reason: error.localizedDescription)
            }
        }
        return LocalTransferOutcome(destination: destination, replacedItemInTrash: replacedItemInTrash, sourceInTrash: sourceInTrash)
    }

    // MARK: Conflicts

    /// Where the item goes once conflicts are settled, or nil when the user chose to skip it.
    private func target(for source: URL, in directory: URL, decision: FileConflictDecision?) async throws -> URL? {
        let proposed = await destination(for: source, in: directory)
        guard await exists(at: proposed) else { return proposed }
        switch decision {
        case .keepBoth:
            return await uniqueDestination(for: proposed, isDirectory: isFolder(source))
        case .replace:
            return proposed
        case .skip:
            return nil
        case nil:
            throw LocalTransferError.destinationExists
        }
    }

    private func uniqueDestination(for proposed: URL, isDirectory: Bool) async -> URL {
        let name = Self.name(of: proposed)
        let stem = (name as NSString).deletingPathExtension
        let pathExtension = (name as NSString).pathExtension
        let directory = proposed.deletingLastPathComponent()
        var suffix = 2
        while true {
            let base = "\(stem) copy \(suffix)"
            let candidate = Self.child(
                named: pathExtension.isEmpty || isDirectory ? base : "\(base).\(pathExtension)",
                isDirectory: isDirectory,
                in: directory
            )
            if await !exists(at: candidate) { return candidate }
            suffix += 1
        }
    }

    /// Replace only ever removes the existing item recoverably, and only once the new copy is
    /// complete; the caller decides when that is.
    private func trashIfReplacing(_ target: URL, decision: FileConflictDecision?) async throws -> URL? {
        guard decision == .replace, await exists(at: target) else { return nil }
        if CloudLocation.isCloud(target) {
            return try await registry.provider(for: target).moveToTrash(target)
        }
        return try trashLocalItem(target)
    }

    // MARK: Into a drive

    private func upload(
        _ source: URL,
        as target: URL,
        decision: FileConflictDecision?,
        counter: ByteAccumulator
    ) async throws -> (URL, URL?) {
        let provider = try registry.provider(for: target)
        let directory = target.deletingLastPathComponent()

        // A cloud source is brought to the Mac first; only the upload counts toward progress so
        // the bar does not run twice.
        var localSource = source
        var temporaryFolder: URL?
        if CloudLocation.isCloud(source) {
            let folder = CloudCache.directory.appendingPathComponent("transfer-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            temporaryFolder = folder
            localSource = try await downloadTree(source, into: folder, counter: ByteAccumulator(reportingTo: nil))
        }
        defer {
            if let temporaryFolder { try? FileManager.default.removeItem(at: temporaryFolder) }
        }

        let stagingName = Self.stagingName()
        let staged: URL
        do {
            staged = try await uploadTree(localSource, named: stagingName, into: directory, provider: provider, counter: counter)
        } catch {
            // A folder upload that stopped halfway leaves its staging folder behind.
            if let location = CloudLocation(directory),
               let leftover = try? await provider.item(at: location.appending(stagingName).url) {
                _ = try? await provider.moveToTrash(leftover.url)
            }
            throw error
        }
        do {
            try Task.checkCancellation()
            let replaced = try await trashIfReplacing(target, decision: decision)
            let published = try await provider.rename(staged, to: target.lastPathComponent)
            return (published, replaced)
        } catch {
            _ = try? await provider.moveToTrash(staged)
            throw error
        }
    }

    private func uploadTree(
        _ localURL: URL,
        named name: String,
        into directory: URL,
        provider: any RemoteFileProviding,
        counter: ByteAccumulator
    ) async throws -> URL {
        try Task.checkCancellation()
        let values = try localURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            return try await provider.upload(localURL, named: name, into: directory) { counter.add($0) }
        }
        let folder = try await provider.createFolder(named: name, in: directory)
        let children = try FileManager.default.contentsOfDirectory(
            at: localURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        for child in children {
            // Links are not followed, so a link cycle cannot make the upload endless, and Finder's
            // view settings are not worth putting in a drive.
            let childValues = try child.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard childValues.isSymbolicLink != true, child.lastPathComponent != ".DS_Store" else { continue }
            _ = try await uploadTree(child, named: child.lastPathComponent, into: folder, provider: provider, counter: counter)
        }
        return folder
    }

    // MARK: Out of a drive

    /// Returns nil when a converted document's new name is taken and the user chose to skip.
    private func download(
        _ source: URL,
        as plannedTarget: URL,
        decision: FileConflictDecision?,
        counter: ByteAccumulator
    ) async throws -> (URL, URL?)? {
        let directory = plannedTarget.deletingLastPathComponent()
        let staging = directory.appendingPathComponent(Self.stagingName(), isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: staging) }

        let downloaded = try await downloadTree(source, into: staging, counter: counter)
        try Task.checkCancellation()

        // A converted document arrives with a new extension, and the conflict check made for
        // its original name no longer applies to it.
        var finalTarget = plannedTarget
        if downloaded.lastPathComponent != Self.name(of: source) {
            let converted = directory.appendingPathComponent(downloaded.lastPathComponent)
            guard let settled = try await target(for: converted, in: directory, decision: decision) else { return nil }
            finalTarget = settled
        }
        let replaced = try await trashIfReplacing(finalTarget, decision: decision)
        try FileManager.default.moveItem(at: downloaded, to: finalTarget)
        return (finalTarget, replaced)
    }

    /// Recreates a cloud item inside a local folder and returns where it ended up.
    private func downloadTree(_ source: URL, into localFolder: URL, counter: ByteAccumulator) async throws -> URL {
        try Task.checkCancellation()
        let provider = try registry.provider(for: source)
        let name = Self.name(of: source)
        guard isFolder(source) else {
            let partial = localFolder.appendingPathComponent(".panespace-partial-\(UUID().uuidString)")
            let savedName = try await provider.download(source, to: partial) { counter.add($0) }
            let destination = localFolder.appendingPathComponent(savedName)
            try FileManager.default.moveItem(at: partial, to: destination)
            return destination
        }
        let folder = localFolder.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        for child in try await provider.contents(of: source, showsHiddenFiles: true) {
            _ = try await downloadTree(child.url, into: folder, counter: counter)
        }
        return folder
    }

    private func remoteByteCount(of item: FileItem, provider: any RemoteFileProviding) async throws -> Int64 {
        guard item.isFolder else { return item.fileSize ?? 0 }
        var total: Int64 = 0
        for child in try await provider.contents(of: item.url, showsHiddenFiles: true) {
            try Task.checkCancellation()
            total += try await remoteByteCount(of: child, provider: provider)
        }
        return total
    }

    // MARK: Helpers

    /// Cloud folders end in a slash, like every folder URL a listing produces; local items are
    /// asked directly because a dropped folder URL may lack the slash.
    private func isFolder(_ url: URL) -> Bool {
        if CloudLocation.isCloud(url) { return url.hasDirectoryPath }
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return values?.isDirectory == true && values?.isSymbolicLink != true
    }

    private static func name(of url: URL) -> String {
        CloudLocation(url)?.name ?? url.lastPathComponent
    }

    private static func child(named name: String, isDirectory: Bool, in directory: URL) -> URL {
        if let location = CloudLocation(directory) {
            return location.appending(name).url(isDirectory: isDirectory)
        }
        return directory.appendingPathComponent(name, isDirectory: isDirectory)
    }

    static func stagingName() -> String {
        ".panespace-staging-\(UUID().uuidString)"
    }

    /// Identifies a location independently of trailing slashes, and keeps paths of different
    /// drives apart.
    static func comparisonKey(_ url: URL) -> String {
        BrowserPaneModel.comparablePath(url)
    }
}

/// Adds up chunk sizes reported from several requests into the queue's per-item counter.
private final class ByteAccumulator: Sendable {
    private let total = Mutex<Int64>(0)
    private let counter: TransferByteCounter?

    init(reportingTo counter: TransferByteCounter?) {
        self.counter = counter
    }

    func add(_ bytes: Int64) {
        let value = total.withLock { total in
            total += bytes
            return total
        }
        counter?.set(value)
    }
}
