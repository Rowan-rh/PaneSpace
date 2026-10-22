import Foundation

/// Cloud drives PaneSpace can browse through their own web APIs. Neither offers SMB, WebDAV, or
/// SFTP, so each one has a provider of its own.
enum CloudService: String, Codable, CaseIterable, Identifiable, Sendable {
    case googleDrive
    case baiduNetdisk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .googleDrive: "Google Drive"
        case .baiduNetdisk: "Baidu Netdisk"
        }
    }

    var systemImage: String {
        switch self {
        case .googleDrive: "externaldrive.connected.to.line.below"
        case .baiduNetdisk: "cloud"
        }
    }

    /// Locations in a connected drive are URLs with this scheme, so panes, tabs, and history can
    /// hold them like any folder while the scheme tells which provider serves them.
    var urlScheme: String {
        switch self {
        case .googleDrive: "panespace-gdrive"
        case .baiduNetdisk: "panespace-baidupan"
        }
    }

    init?(urlScheme: String) {
        guard let service = Self.allCases.first(where: { $0.urlScheme == urlScheme.lowercased() }) else { return nil }
        self = service
    }
}

/// A connected cloud drive. Only the non-secret description lives here; tokens are kept in
/// Keychain under the account's identifier.
struct CloudAccount: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let service: CloudService
    /// The name the service reports for the signed-in user, shown as the drive's title.
    var name: String
    /// Where the drive opens. Baidu only lets an app into the folder it was granted, so a Baidu
    /// drive opens there instead of at the root it cannot read.
    var homePath: String

    init(id: UUID = UUID(), service: CloudService, name: String, homePath: String = "/") {
        self.id = id
        self.service = service
        self.name = name
        self.homePath = homePath
    }

    var rootURL: URL {
        CloudLocation(service: service, accountID: id, path: "/").url
    }

    var homeURL: URL {
        CloudLocation(service: service, accountID: id, path: homePath).url
    }

    var sidebarID: String { "cloud:\(id.uuidString.lowercased())" }
}

/// The parts of a cloud location URL: which drive, and the path inside it.
struct CloudLocation: Hashable, Sendable {
    let service: CloudService
    let accountID: UUID
    /// Absolute path inside the drive, "/" for its root, without a trailing slash.
    let path: String

    init(service: CloudService, accountID: UUID, path: String) {
        self.service = service
        self.accountID = accountID
        self.path = Self.normalized(path)
    }

    init?(_ url: URL) {
        guard let scheme = url.scheme,
              let service = CloudService(urlScheme: scheme),
              let host = url.host(percentEncoded: false),
              let accountID = UUID(uuidString: host) else { return nil }
        self.init(service: service, accountID: accountID, path: url.path(percentEncoded: false))
    }

    static func isCloud(_ url: URL) -> Bool {
        url.scheme.flatMap(CloudService.init(urlScheme:)) != nil
    }

    var isRoot: Bool { path == "/" }

    /// A path-like key that differs between drives, for comparing locations textually. A drive's
    /// root has no trailing slash, so a prefix test with "/" appended matches its contents.
    var comparisonKey: String {
        "\(service.urlScheme)://\(accountID.uuidString.lowercased())\(isRoot ? "" : path)"
    }

    var name: String { (path as NSString).lastPathComponent }

    var parent: CloudLocation {
        CloudLocation(service: service, accountID: accountID, path: (path as NSString).deletingLastPathComponent)
    }

    func appending(_ name: String) -> CloudLocation {
        CloudLocation(service: service, accountID: accountID, path: (path as NSString).appendingPathComponent(name))
    }

    /// Folders carry a trailing slash, matching what local listings produce, so a folder reached by
    /// listing and the same folder reached from the path bar compare equal.
    func url(isDirectory: Bool = true) -> URL {
        var components = URLComponents()
        components.scheme = service.urlScheme
        components.host = accountID.uuidString.lowercased()
        components.path = isRoot ? "/" : (isDirectory ? path + "/" : path)
        return components.url ?? URL(fileURLWithPath: "/")
    }

    var url: URL { url(isDirectory: true) }

    private static func normalized(_ path: String) -> String {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        return "/" + components.joined(separator: "/")
    }
}
