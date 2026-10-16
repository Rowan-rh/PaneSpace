import Foundation
import Synchronization
@testable import PaneSpaceApp

/// Answers URLSession requests from a handler, so cloud providers can be tested without a network.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        var status = 200
        var headers: [String: String] = [:]
        var body = Data()

        static func json(_ object: Any, status: Int = 200, headers: [String: String] = [:]) -> Reply {
            Reply(status: status, headers: headers, body: (try? JSONSerialization.data(withJSONObject: object)) ?? Data())
        }
    }

    typealias Handler = @Sendable (URLRequest) throws -> Reply

    private static let state = Mutex<(handler: Handler?, requests: [URLRequest])>((nil, []))

    static func session(handler: @escaping Handler) -> URLSession {
        state.withLock { $0 = (handler, []) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static var requests: [URLRequest] {
        state.withLock { $0.requests }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var recorded = request
        // URLSession moves bodies into a stream before protocols see them; read it back for tests.
        if recorded.httpBody == nil, let stream = request.httpBodyStream {
            recorded.httpBody = Self.read(stream)
        }
        let handler = Self.state.withLock { state in
            state.requests.append(recorded)
            return state.handler
        }
        do {
            guard let handler, let url = request.url else { throw URLError(.badServerResponse) }
            let reply = try handler(recorded)
            let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: reply.body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

extension URLRequest {
    func queryValue(_ name: String) -> String? {
        url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems?.first { $0.name == name }?.value
    }

    /// Values of a form-encoded body.
    var formValues: [String: String] {
        guard let body = httpBody, let text = String(data: body, encoding: .utf8),
              let components = URLComponents(string: "http://x/?\(text)") else { return [:] }
        var values: [String: String] = [:]
        for item in components.queryItems ?? [] {
            values[item.name] = item.value?.replacingOccurrences(of: "+", with: " ")
        }
        return values
    }

    var jsonBody: [String: Any] {
        httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    }
}

/// A cloud drive kept in memory, standing in for a real provider in transfer tests.
actor InMemoryCloudDrive: RemoteFileProviding {
    struct Node {
        var isFolder: Bool
        var data: Data
    }

    let accountID: UUID
    let service: CloudService
    private(set) var nodes: [String: Node] = ["/": Node(isFolder: true, data: Data())]
    private(set) var trashed: [String] = []
    private(set) var movedPaths: [(String, String)] = []
    private(set) var downloadCount = 0

    init(accountID: UUID = UUID(), service: CloudService = .googleDrive) {
        self.accountID = accountID
        self.service = service
    }

    func url(_ path: String, isDirectory: Bool = false) -> URL {
        CloudLocation(service: service, accountID: accountID, path: path).url(isDirectory: isDirectory)
    }

    func addFolder(_ path: String) {
        nodes[path] = Node(isFolder: true, data: Data())
    }

    func addFile(_ path: String, contents: String) {
        nodes[path] = Node(isFolder: false, data: Data(contents.utf8))
    }

    func contents(at path: String) -> String? {
        nodes[path].map { String(decoding: $0.data, as: UTF8.self) }
    }

    var paths: [String] { nodes.keys.sorted() }

    private func path(of url: URL) throws -> String {
        guard let location = CloudLocation(url), location.accountID == accountID else {
            throw FileProviderError.itemUnavailable
        }
        return location.path
    }

    private func children(of path: String) -> [String] {
        nodes.keys.filter { $0 != "/" && ($0 as NSString).deletingLastPathComponent == path }.sorted()
    }

    func contents(of directory: URL, showsHiddenFiles: Bool) throws -> [FileItem] {
        let path = try path(of: directory)
        guard nodes[path]?.isFolder == true else { throw FileProviderError.itemUnavailable }
        return children(of: path).compactMap { child in
            let name = (child as NSString).lastPathComponent
            guard showsHiddenFiles || !name.hasPrefix(".") else { return nil }
            return fileItem(at: child)
        }
    }

    private func fileItem(at path: String) -> FileItem? {
        guard let node = nodes[path] else { return nil }
        return FileItem(
            url: url(path, isDirectory: node.isFolder),
            isDirectory: node.isFolder,
            isHidden: false,
            fileSize: node.isFolder ? nil : Int64(node.data.count),
            modificationDate: nil,
            kind: "Item"
        )
    }

    func item(at url: URL) throws -> FileItem? {
        fileItem(at: try path(of: url))
    }

    func createFolder(named name: String, in directory: URL) throws -> URL {
        let path = (try path(of: directory) as NSString).appendingPathComponent(name)
        guard nodes[path] == nil else { throw FileProviderError.itemAlreadyExists }
        nodes[path] = Node(isFolder: true, data: Data())
        return url(path, isDirectory: true)
    }

    func rename(_ item: URL, to newName: String) throws -> URL {
        let source = try path(of: item)
        let destination = ((source as NSString).deletingLastPathComponent as NSString).appendingPathComponent(newName)
        guard nodes[destination] == nil else { throw FileProviderError.itemAlreadyExists }
        relocate(source, to: destination)
        return url(destination, isDirectory: item.hasDirectoryPath)
    }

    func moveToTrash(_ item: URL) throws -> URL? {
        let path = try path(of: item)
        guard nodes[path] != nil else { throw FileProviderError.itemUnavailable }
        trashed.append(path)
        for key in nodes.keys where key == path || key.hasPrefix(path + "/") {
            nodes[key] = nil
        }
        return nil
    }

    func download(_ url: URL, to localURL: URL, progress: @escaping @Sendable (Int64) -> Void) throws -> String {
        let path = try path(of: url)
        guard let node = nodes[path], !node.isFolder else { throw FileProviderError.itemUnavailable }
        downloadCount += 1
        try node.data.write(to: localURL)
        progress(Int64(node.data.count))
        return (path as NSString).lastPathComponent
    }

    func upload(_ localURL: URL, named name: String, into directory: URL, progress: @escaping @Sendable (Int64) -> Void) throws -> URL {
        let path = (try path(of: directory) as NSString).appendingPathComponent(name)
        guard nodes[path] == nil else { throw FileProviderError.itemAlreadyExists }
        let data = try Data(contentsOf: localURL)
        nodes[path] = Node(isFolder: false, data: data)
        progress(Int64(data.count))
        return url(path)
    }

    func move(_ item: URL, into directory: URL, named name: String) throws -> URL {
        let source = try path(of: item)
        let destination = (try path(of: directory) as NSString).appendingPathComponent(name)
        guard nodes[destination] == nil else { throw FileProviderError.itemAlreadyExists }
        movedPaths.append((source, destination))
        relocate(source, to: destination)
        return url(destination, isDirectory: item.hasDirectoryPath)
    }

    func availableCapacity() -> Int64? { 1_000 }

    private func relocate(_ source: String, to destination: String) {
        for key in nodes.keys where key == source || key.hasPrefix(source + "/") {
            let node = nodes.removeValue(forKey: key)
            nodes[destination + key.dropFirst(source.count)] = node
        }
    }
}

extension CloudCredentialStore {
    /// A store holding app credentials and a valid token for `accountID`, kept in memory.
    static func testing(
        accountID: UUID,
        service: CloudService,
        expiresAt: Date = .now.addingTimeInterval(3_600)
    ) throws -> CloudCredentialStore {
        let store = CloudCredentialStore(secrets: InMemorySecretStore())
        try store.setAppCredentials(CloudAppCredentials(clientID: "client", clientSecret: "secret"), for: service)
        try store.setTokens(CloudTokens(accessToken: "access-1", refreshToken: "refresh-1", expiresAt: expiresAt), for: accountID)
        return store
    }
}
