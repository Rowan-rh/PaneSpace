import CryptoKit
import Foundation

/// Browses one Baidu Netdisk account through the xpan open platform API.
///
/// Baidu addresses items by path, so URLs map onto it directly; downloads need the numeric file
/// ID, which listings record. Third-party apps may only work inside the folders the user granted,
/// which by default is `/apps/<app name>`, shown in Baidu's own apps as “我的应用数据”.
actor BaiduNetdiskProvider: RemoteFileProviding {
    static let fileEndpoint = URL(string: "https://pan.baidu.com/rest/2.0/xpan/file")!
    static let pageSize = 1_000
    /// Regular accounts must upload in 4 MB slices; larger slices are for paid accounts only.
    static let sliceSize = 4 * 1_024 * 1_024
    /// Every request identifies itself this way; downloads are refused without it.
    static let userAgent = "pan.baidu.com"

    private let accountID: UUID
    private let client: CloudHTTPClient
    private var fileIDs: [String: UInt64] = [:]

    init(accountID: UUID, client: CloudHTTPClient) {
        self.accountID = accountID
        self.client = client
    }

    static func makeClient(accountID: UUID, store: CloudCredentialStore, session: URLSession) -> CloudHTTPClient {
        CloudHTTPClient(
            session: session,
            tokens: CloudAccessTokenSource(accountID: accountID, service: .baiduNetdisk, store: store, session: session)
        ) { request, token in
            if let url = request.url {
                request.url = url.appendingQuery(["access_token": token])
            }
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
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
        var start = 0
        var yieldedAny = false
        while true {
            try Task.checkCancellation()
            let page = try await listPage(of: location.path, start: start)
            let batch = page.compactMap { entry -> FileItem? in
                fileIDs[entry.path] = entry.fsID
                guard showsHiddenFiles || !entry.serverFilename.hasPrefix(".") else { return nil }
                return item(for: entry, in: location)
            }
            let isLastPage = page.count < Self.pageSize
            if !batch.isEmpty || (isLastPage && !yieldedAny) {
                yield(batch)
                yieldedAny = true
            }
            if isLastPage { return }
            start += page.count
        }
    }

    private func listPage(of path: String, start: Int) async throws -> [Entry] {
        let url = Self.fileEndpoint.appendingQuery([
            "method": "list",
            "dir": path,
            "start": String(start),
            "limit": String(Self.pageSize),
            "order": "name"
        ])
        let reply: ListReply = try await send(URLRequest(url: url))
        return reply.list ?? []
    }

    /// Looked up by listing the parent: Baidu's documented metadata calls take file IDs, which a
    /// path from the path bar or a previous session does not carry.
    func item(at url: URL) async throws -> FileItem? {
        let location = try location(of: url)
        if location.isRoot {
            return FileItem(url: location.url, isDirectory: true, isHidden: false, fileSize: nil, modificationDate: nil, kind: L10n.text("Folder"))
        }
        guard let entry = try await entry(at: location) else { return nil }
        return item(for: entry, in: location.parent)
    }

    private func entry(at location: CloudLocation) async throws -> Entry? {
        var start = 0
        while true {
            let page: [Entry]
            do {
                page = try await listPage(of: location.parent.path, start: start)
            } catch FileProviderError.itemUnavailable {
                return nil
            }
            if let match = page.first(where: { $0.serverFilename == location.name }) {
                fileIDs[match.path] = match.fsID
                return match
            }
            if page.count < Self.pageSize { return nil }
            start += page.count
        }
    }

    // MARK: Changes

    func createFolder(named name: String, in directory: URL) async throws -> URL {
        let name = try GoogleDriveProvider.validated(name)
        let created = try location(of: directory).appending(name)
        let request = URLRequest(
            url: Self.fileEndpoint.appendingQuery(["method": "create"]),
            method: "POST",
            form: ["path": created.path, "isdir": "1", "rtype": "0"]
        )
        let reply: CreateReply = try await send(request)
        if let fsID = reply.fsID { fileIDs[created.path] = fsID }
        return created.url
    }

    func rename(_ item: URL, to newName: String) async throws -> URL {
        let newName = try GoogleDriveProvider.validated(newName)
        let location = try location(of: item)
        guard !location.isRoot, newName != location.name else { return item }
        try await manage("rename", [["path": location.path, "newname": newName]])
        forget(location.path)
        return location.parent.appending(newName).url(isDirectory: item.hasDirectoryPath)
    }

    /// Baidu keeps deleted items in its recycle bin for a limited time. The deleted item has no
    /// path a pane could show, so no location is returned.
    func moveToTrash(_ item: URL) async throws -> URL? {
        let location = try location(of: item)
        guard !location.isRoot else { throw FileProviderError.permissionDenied }
        try await manage("delete", [location.path])
        forget(location.path)
        return nil
    }

    func move(_ item: URL, into directory: URL, named name: String) async throws -> URL {
        let source = try location(of: item)
        let target = try location(of: directory)
        try await manage("move", [["path": source.path, "dest": target.path, "newname": name]])
        forget(source.path)
        return target.appending(name).url(isDirectory: item.hasDirectoryPath)
    }

    /// Runs a file-manager operation synchronously and fails on name conflicts rather than
    /// letting the service overwrite or rename anything.
    private func manage(_ operation: String, _ files: [Any]) async throws {
        let list = String(data: try JSONSerialization.data(withJSONObject: files), encoding: .utf8) ?? "[]"
        var form = ["async": "0", "filelist": list]
        if operation != "delete" { form["ondup"] = "fail" }
        let request = URLRequest(
            url: Self.fileEndpoint.appendingQuery(["method": "filemanager", "opera": operation]),
            method: "POST",
            form: form
        )
        let reply: ManageReply = try await send(request)
        if let failure = reply.info?.first(where: { ($0.errno ?? 0) != 0 })?.errno {
            throw Self.error(forErrno: failure, message: nil)
        }
    }

    // MARK: Transfers

    func download(_ url: URL, to localURL: URL, progress: @escaping @Sendable (Int64) -> Void) async throws -> String {
        let location = try location(of: url)
        var fsID = fileIDs[location.path]
        if fsID == nil {
            fsID = try await entry(at: location)?.fsID
        }
        guard let fsID else { throw FileProviderError.itemUnavailable }
        let metadataURL = URL(string: "https://pan.baidu.com/rest/2.0/xpan/multimedia")!.appendingQuery([
            "method": "filemetas",
            "fsids": "[\(fsID)]",
            "dlink": "1"
        ])
        let metadata: MetadataReply = try await send(URLRequest(url: metadataURL))
        guard let link = metadata.list?.first?.dlink, let downloadURL = URL(string: link) else {
            throw FileProviderError.itemUnavailable
        }
        // The link is signed; the token is appended to it by the client, leaving the rest intact.
        _ = try await client.download(URLRequest(url: downloadURL), to: localURL, progress: progress)
        return location.name
    }

    func upload(
        _ localURL: URL,
        named name: String,
        into directory: URL,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws -> URL {
        let name = try GoogleDriveProvider.validated(name)
        let target = try location(of: directory).appending(name)
        let size = (try FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        let digests = try Self.sliceDigests(of: localURL)
        let blockList = String(data: try JSONSerialization.data(withJSONObject: digests), encoding: .utf8) ?? "[]"

        let precreate = URLRequest(
            url: Self.fileEndpoint.appendingQuery(["method": "precreate"]),
            method: "POST",
            form: ["path": target.path, "size": String(size), "isdir": "0", "autoinit": "1", "rtype": "0", "block_list": blockList]
        )
        let plan: PrecreateReply = try await send(precreate)
        guard let uploadID = plan.uploadID else { throw CloudError.server("") }
        // Baidu may already hold some slices; an empty list means only the first is needed.
        let requested = plan.blockList ?? []
        let needed = Set(requested.isEmpty ? [0] : requested)
        let host = try await uploadHost(for: target.path, uploadID: uploadID)

        let handle = try FileHandle(forReadingFrom: localURL)
        defer { try? handle.close() }
        for index in digests.indices {
            try Task.checkCancellation()
            let slice = try handle.read(upToCount: Self.sliceSize) ?? Data()
            guard needed.contains(index) else {
                progress(Int64(slice.count))
                continue
            }
            let url = host.appendingPathComponent("rest/2.0/pcs/superfile2").appendingQuery([
                "method": "upload",
                "type": "tmpfile",
                "path": target.path,
                "uploadid": uploadID,
                "partseq": String(index)
            ])
            let boundary = "PaneSpace-\(UUID().uuidString)"
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.multipartBody(slice, boundary: boundary)
            let _: SliceReply = try await send(request)
            progress(Int64(slice.count))
        }

        let create = URLRequest(
            url: Self.fileEndpoint.appendingQuery(["method": "create"]),
            method: "POST",
            form: ["path": target.path, "size": String(size), "isdir": "0", "rtype": "0", "uploadid": uploadID, "block_list": blockList]
        )
        let created: CreateReply = try await send(create)
        if let fsID = created.fsID { fileIDs[target.path] = fsID }
        return target.url(isDirectory: false)
    }

    private func uploadHost(for path: String, uploadID: String) async throws -> URL {
        let url = URL(string: "https://d.pcs.baidu.com/rest/2.0/pcs/file")!.appendingQuery([
            "method": "locateupload",
            "appid": "250528",
            "path": path,
            "uploadid": uploadID,
            "upload_version": "2.0"
        ])
        let (data, _) = try await client.data(for: URLRequest(url: url))
        let reply = try? JSONDecoder().decode(LocateUploadReply.self, from: data)
        let server = reply?.servers?.compactMap(\.server).first { $0.hasPrefix("https://") }
        return server.flatMap(URL.init(string:)) ?? URL(string: "https://d.pcs.baidu.com")!
    }

    func availableCapacity() async -> Int64? {
        let url = URL(string: "https://pan.baidu.com/api/quota")!.appendingQuery(["checkfree": "1"])
        guard let quota: QuotaReply = try? await send(URLRequest(url: url)) else { return nil }
        if let free = quota.free { return free }
        guard let total = quota.total, let used = quota.used else { return nil }
        return max(total - used, 0)
    }

    static func accountName(client: CloudHTTPClient) async throws -> String {
        let url = URL(string: "https://pan.baidu.com/rest/2.0/xpan/nas")!.appendingQuery(["method": "uinfo"])
        let (data, response) = try await client.data(for: URLRequest(url: url))
        let reply = try decodeChecked(UserReply.self, from: data, statusCode: response.statusCode)
        let name = reply.netdiskName?.isEmpty == false ? reply.netdiskName : reply.baiduName
        return name ?? CloudService.baiduNetdisk.title
    }

    // MARK: Helpers

    private func location(of url: URL) throws -> CloudLocation {
        guard let location = CloudLocation(url), location.service == .baiduNetdisk, location.accountID == accountID else {
            throw FileProviderError.itemUnavailable
        }
        return location
    }

    private func forget(_ path: String) {
        for key in fileIDs.keys where key == path || key.hasPrefix(path + "/") {
            fileIDs[key] = nil
        }
    }

    private func item(for entry: Entry, in directory: CloudLocation) -> FileItem {
        let isFolder = entry.isdir == 1
        let name = entry.serverFilename
        return FileItem(
            url: directory.appending(name).url(isDirectory: isFolder),
            isDirectory: isFolder,
            isHidden: name.hasPrefix("."),
            fileSize: isFolder ? nil : entry.size,
            modificationDate: entry.serverMtime.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            kind: CloudItemKind.kind(forName: name, isFolder: isFolder)
        )
    }

    /// Sends a request and checks Baidu's error number, which arrives in the body of an HTTP 200
    /// reply. An access token the service rejects is refreshed once and the request retried.
    private func send<Value: Decodable>(_ request: URLRequest) async throws -> Value {
        let (data, response) = try await client.data(for: request)
        do {
            return try Self.decodeChecked(Value.self, from: data, statusCode: response.statusCode)
        } catch CloudError.sessionExpired {
            _ = try await client.tokens.accessToken(forceRefresh: true)
            let (retryData, retryResponse) = try await client.data(for: request)
            return try Self.decodeChecked(Value.self, from: retryData, statusCode: retryResponse.statusCode)
        }
    }

    static func decodeChecked<Value: Decodable>(_ type: Value.Type, from data: Data, statusCode: Int) throws -> Value {
        let status = try? JSONDecoder().decode(Status.self, from: data)
        if let errno = status?.errno ?? status?.errorCode, errno != 0 {
            throw error(forErrno: errno, message: status?.message)
        }
        guard (200 ..< 300).contains(statusCode) else { throw CloudHTTPClient.statusError(statusCode) }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw CloudError.server("")
        }
    }

    static func error(forErrno errno: Int, message: String?) -> Error {
        switch errno {
        case -6, 111, 110:
            return CloudError.sessionExpired
        case -9, 31066, 31190:
            return FileProviderError.itemUnavailable
        case -8:
            return FileProviderError.itemAlreadyExists
        case -7, 6, 20013, 31024:
            return FileProviderError.permissionDenied
        case -10, 31365:
            return CloudError.quotaExceeded
        case 31034, 20012:
            return CloudError.rateLimited
        default:
            let detail = message.flatMap { $0.isEmpty ? nil : $0 } ?? "errno \(errno)"
            return CloudError.server(detail)
        }
    }

    /// MD5 of each 4 MB slice, which Baidu needs before accepting any data.
    static func sliceDigests(of url: URL) throws -> [String] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digests: [String] = []
        while let slice = try handle.read(upToCount: sliceSize), !slice.isEmpty {
            digests.append(Insecure.MD5.hash(data: slice).map { String(format: "%02x", $0) }.joined())
        }
        if digests.isEmpty {
            digests.append(Insecure.MD5.hash(data: Data()).map { String(format: "%02x", $0) }.joined())
        }
        return digests
    }

    static func multipartBody(_ slice: Data, boundary: String) -> Data {
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"blob\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8)
        body.append(slice)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }

    // MARK: Replies

    struct Entry: Decodable, Sendable {
        let fsID: UInt64
        let path: String
        let serverFilename: String
        let size: Int64?
        let isdir: Int
        let serverMtime: Int64?

        enum CodingKeys: String, CodingKey {
            case fsID = "fs_id"
            case path
            case serverFilename = "server_filename"
            case size
            case isdir
            case serverMtime = "server_mtime"
        }
    }

    struct Status: Decodable {
        let errno: Int?
        let errorCode: Int?
        let message: String?

        enum CodingKeys: String, CodingKey {
            case errno
            case errorCode = "error_code"
            case message = "show_msg"
        }
    }

    struct ListReply: Decodable { let list: [Entry]? }

    struct CreateReply: Decodable {
        let fsID: UInt64?
        enum CodingKeys: String, CodingKey { case fsID = "fs_id" }
    }

    struct ManageReply: Decodable {
        struct Result: Decodable { let errno: Int? }
        let info: [Result]?
    }

    struct MetadataReply: Decodable {
        struct File: Decodable { let dlink: String? }
        let list: [File]?
    }

    struct PrecreateReply: Decodable {
        let uploadID: String?
        let blockList: [Int]?
        enum CodingKeys: String, CodingKey {
            case uploadID = "uploadid"
            case blockList = "block_list"
        }
    }

    struct SliceReply: Decodable { let md5: String? }

    struct LocateUploadReply: Decodable {
        struct Server: Decodable { let server: String? }
        let servers: [Server]?
    }

    struct QuotaReply: Decodable {
        let total: Int64?
        let used: Int64?
        let free: Int64?
    }

    struct UserReply: Decodable {
        let baiduName: String?
        let netdiskName: String?
        enum CodingKeys: String, CodingKey {
            case baiduName = "baidu_name"
            case netdiskName = "netdisk_name"
        }
    }
}
