import Foundation
import UniformTypeIdentifiers

/// Browses "My Drive" of one Google account through the Drive v3 REST API.
///
/// Drive identifies items by ID and allows several items with the same name in one folder, while
/// panes work with paths. The provider keeps a path-to-ID map filled by every listing and falls
/// back to looking names up folder by folder. Duplicate names in a listing are told apart by a
/// short ID suffix, so each row keeps a distinct URL.
actor GoogleDriveProvider: RemoteFileProviding {
    static let apiBase = URL(string: "https://www.googleapis.com/drive/v3")!
    static let uploadBase = URL(string: "https://www.googleapis.com/upload/drive/v3/files")!
    static let folderMimeType = "application/vnd.google-apps.folder"
    static let itemFields = "id,name,mimeType,size,modifiedTime"
    /// Resumable uploads must send chunks in multiples of 256 KiB.
    static let uploadChunkSize = 32 * 256 * 1_024

    struct Entry: Equatable, Sendable {
        let id: String
        let mimeType: String
        var isFolder: Bool { mimeType == GoogleDriveProvider.folderMimeType }
    }

    private let accountID: UUID
    private let client: CloudHTTPClient
    private var entries: [String: Entry] = ["/": Entry(id: "root", mimeType: GoogleDriveProvider.folderMimeType)]

    init(accountID: UUID, client: CloudHTTPClient) {
        self.accountID = accountID
        self.client = client
    }

    static func makeClient(accountID: UUID, store: CloudCredentialStore, session: URLSession) -> CloudHTTPClient {
        CloudHTTPClient(
            session: session,
            tokens: CloudAccessTokenSource(accountID: accountID, service: .googleDrive, store: store, session: session)
        ) { request, token in
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    // MARK: Listing

    func contents(of directory: URL, showsHiddenFiles: Bool) async throws -> [FileItem] {
        var items: [FileItem] = []
        for try await batch in contentBatches(of: directory, showsHiddenFiles: showsHiddenFiles) {
            items.append(contentsOf: batch)
        }
        return items
    }

    nonisolated func contentBatches(of directory: URL, showsHiddenFiles: Bool) -> AsyncThrowingStream<[FileItem], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.list(directory, showsHiddenFiles: showsHiddenFiles) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func list(_ directory: URL, showsHiddenFiles: Bool, yield: ([FileItem]) -> Void) async throws {
        let location = try location(of: directory)
        guard let folder = try await resolve(location.path), folder.isFolder else {
            throw FileProviderError.itemUnavailable
        }
        var pageToken: String?
        var usedNames: Set<String> = []
        var yieldedAny = false
        repeat {
            try Task.checkCancellation()
            var query = [
                "q": "'\(Self.escaped(folder.id))' in parents and trashed = false",
                "fields": "nextPageToken,files(\(Self.itemFields))",
                "pageSize": "1000",
                "orderBy": "createdTime"
            ]
            query["pageToken"] = pageToken
            let page: FileList = try await request(Self.apiBase.appendingPathComponent("files").appendingQuery(query))
            var batch: [FileItem] = []
            for file in page.files {
                let name = Self.uniqueName(for: file, among: &usedNames)
                let childPath = location.appending(name).path
                entries[childPath] = Entry(id: file.id, mimeType: file.mimeType)
                guard showsHiddenFiles || !name.hasPrefix(".") else { continue }
                batch.append(item(for: file, named: name, in: location))
            }
            pageToken = page.nextPageToken
            if !batch.isEmpty || (pageToken == nil && !yieldedAny) {
                yield(batch)
                yieldedAny = true
            }
        } while pageToken != nil
    }

    func item(at url: URL) async throws -> FileItem? {
        let location = try location(of: url)
        if location.isRoot {
            return FileItem(url: location.url, isDirectory: true, isHidden: false, fileSize: nil, modificationDate: nil, kind: L10n.text("Folder"))
        }
        // Looked up afresh rather than from the map: transfers ask this to decide about conflicts.
        guard let parent = try await resolve(location.parent.path), parent.isFolder,
              let file = try await child(named: location.name, of: parent.id) else { return nil }
        entries[location.path] = Entry(id: file.id, mimeType: file.mimeType)
        return item(for: file, named: location.name, in: location.parent)
    }

    // MARK: Changes

    func createFolder(named name: String, in directory: URL) async throws -> URL {
        let name = try Self.validated(name)
        let location = try location(of: directory)
        let parent = try await folderEntry(at: location.path)
        guard try await child(named: name, of: parent.id) == nil else { throw FileProviderError.itemAlreadyExists }
        let request = URLRequest(
            url: Self.apiBase.appendingPathComponent("files").appendingQuery(["fields": Self.itemFields]),
            method: "POST",
            json: ["name": name, "mimeType": Self.folderMimeType, "parents": [parent.id]]
        )
        let file: DriveFile = try await send(request)
        let created = location.appending(name)
        entries[created.path] = Entry(id: file.id, mimeType: file.mimeType)
        return created.url
    }

    func rename(_ item: URL, to newName: String) async throws -> URL {
        let newName = try Self.validated(newName)
        let location = try location(of: item)
        guard !location.isRoot, newName != location.name else { return item }
        guard let entry = try await resolve(location.path),
              let parent = try await resolve(location.parent.path) else { throw FileProviderError.itemUnavailable }
        // A change of case only is a rename of the same item, not a conflict.
        if let existing = try await child(named: newName, of: parent.id), existing.id != entry.id {
            throw FileProviderError.itemAlreadyExists
        }
        let request = URLRequest(
            url: Self.apiBase.appendingPathComponent("files/\(entry.id)").appendingQuery(["fields": Self.itemFields]),
            method: "PATCH",
            json: ["name": newName]
        )
        let _: DriveFile = try await send(request)
        let renamed = location.parent.appending(newName)
        forget(location.path)
        entries[renamed.path] = entry
        return renamed.url(isDirectory: entry.isFolder)
    }

    /// Drive keeps trashed items for 30 days, so this is recoverable like the Finder Trash. The
    /// trashed item has no path a pane could show, so no location is returned.
    func moveToTrash(_ item: URL) async throws -> URL? {
        let location = try location(of: item)
        guard !location.isRoot, let entry = try await resolve(location.path) else {
            throw FileProviderError.itemUnavailable
        }
        let request = URLRequest(
            url: Self.apiBase.appendingPathComponent("files/\(entry.id)").appendingQuery(["fields": "id"]),
            method: "PATCH",
            json: ["trashed": true]
        )
        let _: DriveFile.Identifier = try await send(request)
        forget(location.path)
        return nil
    }

    func move(_ item: URL, into directory: URL, named name: String) async throws -> URL {
        let source = try location(of: item)
        let target = try location(of: directory)
        guard let entry = try await resolve(source.path),
              let oldParent = try await resolve(source.parent.path) else { throw FileProviderError.itemUnavailable }
        let newParent = try await folderEntry(at: target.path)
        let request = URLRequest(
            url: Self.apiBase.appendingPathComponent("files/\(entry.id)").appendingQuery([
                "addParents": newParent.id,
                "removeParents": oldParent.id,
                "fields": Self.itemFields
            ]),
            method: "PATCH",
            json: ["name": name]
        )
        let _: DriveFile = try await send(request)
        forget(source.path)
        let moved = target.appending(name)
        entries[moved.path] = entry
        return moved.url(isDirectory: entry.isFolder)
    }

    // MARK: Transfers

    func download(_ url: URL, to localURL: URL, progress: @escaping @Sendable (Int64) -> Void) async throws -> String {
        let location = try location(of: url)
        guard let entry = try await resolve(location.path), !entry.isFolder else {
            throw FileProviderError.itemUnavailable
        }
        let fileURL = Self.apiBase.appendingPathComponent("files/\(entry.id)")
        let requestURL: URL
        var savedName = location.name
        if entry.mimeType.hasPrefix("application/vnd.google-apps.") {
            // Google's own formats have no file to download; they are exported to an equivalent
            // format, and the saved name gets that format's extension.
            guard let export = Self.exportFormats[entry.mimeType] else {
                throw CloudError.unsupportedItem(name: location.name)
            }
            requestURL = fileURL.appendingPathComponent("export").appendingQuery(["mimeType": export.mimeType])
            savedName += ".\(export.pathExtension)"
        } else {
            requestURL = fileURL.appendingQuery(["alt": "media"])
        }
        _ = try await client.download(URLRequest(url: requestURL), to: localURL, progress: progress)
        return savedName
    }

    func upload(
        _ localURL: URL,
        named name: String,
        into directory: URL,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws -> URL {
        let name = try Self.validated(name)
        let location = try location(of: directory)
        let parent = try await folderEntry(at: location.path)
        guard try await child(named: name, of: parent.id) == nil else { throw FileProviderError.itemAlreadyExists }
        let size = (try FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? NSNumber)?.int64Value ?? 0

        var start = URLRequest(
            url: Self.uploadBase.appendingQuery(["uploadType": "resumable", "fields": Self.itemFields]),
            method: "POST",
            json: ["name": name, "parents": [parent.id]]
        )
        start.setValue(String(size), forHTTPHeaderField: "X-Upload-Content-Length")
        let (startData, startResponse) = try await client.data(for: start)
        guard (200 ..< 300).contains(startResponse.statusCode),
              let sessionLocation = startResponse.value(forHTTPHeaderField: "Location"),
              let sessionURL = URL(string: sessionLocation) else {
            throw Self.error(from: startData, statusCode: startResponse.statusCode)
        }

        let handle = try FileHandle(forReadingFrom: localURL)
        defer { try? handle.close() }
        var offset: Int64 = 0
        repeat {
            try Task.checkCancellation()
            let chunk = try handle.read(upToCount: Self.uploadChunkSize) ?? Data()
            var put = URLRequest(url: sessionURL)
            put.httpMethod = "PUT"
            put.httpBody = chunk
            let range = chunk.isEmpty ? "bytes */\(size)" : "bytes \(offset)-\(offset + Int64(chunk.count) - 1)/\(size)"
            put.setValue(range, forHTTPHeaderField: "Content-Range")
            let (data, response) = try await client.data(for: put)
            offset += Int64(chunk.count)
            progress(Int64(chunk.count))
            switch response.statusCode {
            case 308 where offset < size:
                continue
            case 200, 201:
                let file = try JSONDecoder().decode(DriveFile.self, from: data)
                let uploaded = location.appending(name)
                entries[uploaded.path] = Entry(id: file.id, mimeType: file.mimeType)
                return uploaded.url(isDirectory: false)
            default:
                throw Self.error(from: data, statusCode: response.statusCode)
            }
        } while true
    }

    func availableCapacity() async -> Int64? {
        let url = Self.apiBase.appendingPathComponent("about").appendingQuery(["fields": "storageQuota(limit,usage)"])
        guard let about: About = try? await request(url),
              let limit = about.storageQuota?.limit.flatMap(Int64.init),
              let usage = about.storageQuota?.usage.flatMap(Int64.init) else { return nil }
        return max(limit - usage, 0)
    }

    /// The account's display name, used as the drive's title when it is connected.
    static func accountName(client: CloudHTTPClient) async throws -> String {
        let url = apiBase.appendingPathComponent("about").appendingQuery(["fields": "user(displayName,emailAddress)"])
        let (data, response) = try await client.data(for: URLRequest(url: url))
        guard (200 ..< 300).contains(response.statusCode) else { throw error(from: data, statusCode: response.statusCode) }
        let about = try JSONDecoder().decode(About.self, from: data)
        return about.user?.emailAddress ?? about.user?.displayName ?? CloudService.googleDrive.title
    }

    // MARK: Paths

    private func location(of url: URL) throws -> CloudLocation {
        guard let location = CloudLocation(url), location.service == .googleDrive, location.accountID == accountID else {
            throw FileProviderError.itemUnavailable
        }
        return location
    }

    /// Finds the entry for a path, filling the map one folder at a time for paths not seen in a
    /// listing, such as a location restored from the last session.
    private func resolve(_ path: String) async throws -> Entry? {
        if let entry = entries[path] { return entry }
        let location = CloudLocation(service: .googleDrive, accountID: accountID, path: path)
        guard !location.isRoot,
              let parent = try await resolve(location.parent.path), parent.isFolder,
              let file = try await child(named: location.name, of: parent.id) else { return nil }
        let entry = Entry(id: file.id, mimeType: file.mimeType)
        entries[path] = entry
        return entry
    }

    private func folderEntry(at path: String) async throws -> Entry {
        guard let entry = try await resolve(path), entry.isFolder else { throw FileProviderError.itemUnavailable }
        return entry
    }

    private func child(named name: String, of parentID: String) async throws -> DriveFile? {
        let url = Self.apiBase.appendingPathComponent("files").appendingQuery([
            "q": "name = '\(Self.escaped(name))' and '\(Self.escaped(parentID))' in parents and trashed = false",
            "fields": "files(\(Self.itemFields))",
            "pageSize": "10",
            "orderBy": "createdTime"
        ])
        let list: FileList = try await request(url)
        return list.files.first
    }

    /// Drops a path and everything below it from the map after it was renamed, moved, or trashed.
    private func forget(_ path: String) {
        for key in entries.keys where key == path || key.hasPrefix(path + "/") {
            entries[key] = nil
        }
    }

    // MARK: Requests

    private func request<Value: Decodable>(_ url: URL) async throws -> Value {
        try await send(URLRequest(url: url))
    }

    private func send<Value: Decodable>(_ request: URLRequest) async throws -> Value {
        let (data, response) = try await client.data(for: request)
        guard (200 ..< 300).contains(response.statusCode) else {
            throw Self.error(from: data, statusCode: response.statusCode)
        }
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            throw CloudError.server("")
        }
    }

    static func error(from data: Data, statusCode: Int) -> Error {
        let reply = try? JSONDecoder().decode(ErrorReply.self, from: data)
        let reason = reply?.error.errors?.first?.reason ?? ""
        switch (statusCode, reason) {
        case (404, _):
            return FileProviderError.itemUnavailable
        case (_, "storageQuotaExceeded"), (_, "quotaExceeded"):
            return CloudError.quotaExceeded
        case (429, _), (_, "userRateLimitExceeded"), (_, "rateLimitExceeded"):
            return CloudError.rateLimited
        case (401, _):
            return CloudError.sessionExpired
        case (403, "insufficientPermissions"), (403, "insufficientFilePermissions"), (403, "appNotAuthorizedToFile"):
            return FileProviderError.permissionDenied
        default:
            return CloudError.server(reply?.error.message ?? HTTPURLResponse.localizedString(forStatusCode: statusCode))
        }
    }

    // MARK: Items

    private func item(for file: DriveFile, named name: String, in directory: CloudLocation) -> FileItem {
        let isFolder = file.mimeType == Self.folderMimeType
        return FileItem(
            url: directory.appending(name).url(isDirectory: isFolder),
            isDirectory: isFolder,
            isHidden: name.hasPrefix("."),
            fileSize: isFolder ? nil : file.size.flatMap(Int64.init),
            modificationDate: file.modifiedTime.flatMap(Self.parseDate),
            kind: Self.googleKinds[file.mimeType].map(L10n.text) ?? CloudItemKind.kind(forName: name, isFolder: isFolder)
        )
    }

    /// The first item keeps its name; later items with the same name get the start of their ID.
    static func uniqueName(for file: DriveFile, among usedNames: inout Set<String>) -> String {
        var name = file.name.replacingOccurrences(of: "/", with: "∕")
        if usedNames.contains(name) {
            let stem = (name as NSString).deletingPathExtension
            let pathExtension = (name as NSString).pathExtension
            let suffix = " [\(file.id.prefix(6))]"
            name = pathExtension.isEmpty ? stem + suffix : "\(stem)\(suffix).\(pathExtension)"
        }
        usedNames.insert(name)
        return name
    }

    static func validated(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != ".", trimmed != "..", !trimmed.contains("/") else {
            throw FileProviderError.invalidName
        }
        return trimmed
    }

    /// Drive's query language quotes strings with single quotes and escapes with backslashes.
    static func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    static let exportFormats: [String: (mimeType: String, pathExtension: String)] = [
        "application/vnd.google-apps.document": ("application/vnd.openxmlformats-officedocument.wordprocessingml.document", "docx"),
        "application/vnd.google-apps.spreadsheet": ("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "xlsx"),
        "application/vnd.google-apps.presentation": ("application/vnd.openxmlformats-officedocument.presentationml.presentation", "pptx"),
        "application/vnd.google-apps.drawing": ("application/pdf", "pdf")
    ]

    private static let googleKinds: [String: String] = [
        "application/vnd.google-apps.document": "Google Docs document",
        "application/vnd.google-apps.spreadsheet": "Google Sheets spreadsheet",
        "application/vnd.google-apps.presentation": "Google Slides presentation",
        "application/vnd.google-apps.drawing": "Google Drawings drawing",
        "application/vnd.google-apps.form": "Google Forms form",
        "application/vnd.google-apps.shortcut": "Google Drive shortcut"
    ]

    // MARK: Replies

    struct DriveFile: Decodable, Sendable {
        let id: String
        let name: String
        let mimeType: String
        let size: String?
        let modifiedTime: String?

        struct Identifier: Decodable, Sendable {
            let id: String
        }
    }

    struct FileList: Decodable, Sendable {
        let files: [DriveFile]
        let nextPageToken: String?
    }

    struct About: Decodable, Sendable {
        struct User: Decodable, Sendable {
            let displayName: String?
            let emailAddress: String?
        }

        struct Quota: Decodable, Sendable {
            let limit: String?
            let usage: String?
        }

        let user: User?
        let storageQuota: Quota?
    }

    struct ErrorReply: Decodable, Sendable {
        struct Detail: Decodable, Sendable {
            struct Reason: Decodable, Sendable {
                let reason: String?
            }

            let message: String?
            let errors: [Reason]?
        }

        let error: Detail
    }
}

/// Kind descriptions for cloud items, which have no local file the system could describe.
enum CloudItemKind {
    static func kind(forName name: String, isFolder: Bool) -> String {
        if isFolder { return L10n.text("Folder") }
        let pathExtension = (name as NSString).pathExtension
        guard !pathExtension.isEmpty, let type = UTType(filenameExtension: pathExtension) else {
            return L10n.text("Document")
        }
        return type.localizedDescription ?? L10n.text("Document")
    }
}
