import Foundation

/// The developer app registered with a cloud service. PaneSpace ships without one, so each user
/// enters the identifiers of an app they registered themselves; see docs/DEVELOPMENT.md.
struct CloudAppCredentials: Codable, Equatable, Sendable {
    var clientID: String
    var clientSecret: String
    /// Baidu only: the folder name the app was registered with, found under `/apps`.
    var appFolder: String?

    init(clientID: String, clientSecret: String, appFolder: String? = nil) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.appFolder = appFolder
    }

    var isComplete: Bool {
        !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Credentials a build can embed so users only have to sign in. `scripts/build-app.sh` writes
    /// them into Info.plist from environment variables; the repository never contains them.
    static func bundled(for service: CloudService, in bundle: Bundle = .main) -> CloudAppCredentials? {
        let prefix = "PaneSpace\(service.rawValue.prefix(1).uppercased())\(service.rawValue.dropFirst())"
        let credentials = CloudAppCredentials(
            clientID: bundle.object(forInfoDictionaryKey: "\(prefix)ClientID") as? String ?? "",
            clientSecret: bundle.object(forInfoDictionaryKey: "\(prefix)ClientSecret") as? String ?? "",
            appFolder: bundle.object(forInfoDictionaryKey: "\(prefix)AppFolder") as? String
        ).trimmed
        return credentials.isComplete ? credentials : nil
    }

    var trimmed: CloudAppCredentials {
        let folder = appFolder?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(["/"]))
        return CloudAppCredentials(
            clientID: clientID.trimmingCharacters(in: .whitespacesAndNewlines),
            clientSecret: clientSecret.trimmingCharacters(in: .whitespacesAndNewlines),
            appFolder: folder?.isEmpty == false ? folder : nil
        )
    }
}

struct CloudTokens: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
}

/// Reads and writes everything secret about cloud drives. All of it lives in Keychain; nothing
/// here is ever written to preferences or logs.
struct CloudCredentialStore: Sendable {
    let secrets: SecretStoring

    init(secrets: SecretStoring = KeychainStore()) {
        self.secrets = secrets
    }

    func appCredentials(for service: CloudService) -> CloudAppCredentials? {
        secrets.value(CloudAppCredentials.self, for: "app.\(service.rawValue)")
    }

    func setAppCredentials(_ credentials: CloudAppCredentials, for service: CloudService) throws {
        try secrets.setValue(credentials.trimmed, for: "app.\(service.rawValue)")
    }

    func tokens(for accountID: UUID) -> CloudTokens? {
        secrets.value(CloudTokens.self, for: "tokens.\(accountID.uuidString.lowercased())")
    }

    func setTokens(_ tokens: CloudTokens, for accountID: UUID) throws {
        try secrets.setValue(tokens, for: "tokens.\(accountID.uuidString.lowercased())")
    }

    func removeTokens(for accountID: UUID) {
        try? secrets.remove("tokens.\(accountID.uuidString.lowercased())")
    }
}

/// The token endpoint reply both services share, including their error form.
struct OAuthTokenResponse: Decodable, Sendable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Double?
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case error
        case errorDescription = "error_description"
    }

    /// Builds stored tokens, keeping the previous refresh token when the service did not issue a
    /// new one. Google reuses its refresh token; Baidu replaces it on every refresh.
    func tokens(previousRefreshToken: String? = nil, now: Date = .now) throws -> CloudTokens {
        guard let accessToken, let refreshToken = refreshToken ?? previousRefreshToken else {
            throw CloudError.authorizationFailed(errorDescription ?? error ?? "")
        }
        // Renewing a minute early keeps a request from starting with a token about to expire.
        let lifetime = max((expiresIn ?? 3_600) - 60, 0)
        return CloudTokens(accessToken: accessToken, refreshToken: refreshToken, expiresAt: now.addingTimeInterval(lifetime))
    }
}

enum OAuthEndpoints {
    static func refreshRequest(
        for service: CloudService,
        refreshToken: String,
        credentials: CloudAppCredentials
    ) -> URLRequest {
        tokenRequest(for: service, parameters: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": credentials.clientID,
            "client_secret": credentials.clientSecret
        ])
    }

    /// Google takes a form-encoded POST; Baidu documents its token endpoint with query parameters.
    static func tokenRequest(for service: CloudService, parameters: [String: String]) -> URLRequest {
        switch service {
        case .googleDrive:
            var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(formEncoded(parameters).utf8)
            return request
        case .baiduNetdisk:
            var components = URLComponents(string: "https://openapi.baidu.com/oauth/2.0/token")!
            components.queryItems = parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            return URLRequest(url: components.url!)
        }
    }

    static func formEncoded(_ parameters: [String: String]) -> String {
        parameters.sorted { $0.key < $1.key }
            .map { "\(percentEncoded($0.key))=\(percentEncoded($0.value))" }
            .joined(separator: "&")
    }

    static func percentEncoded(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

/// Hands out a valid access token for one account, refreshing and persisting it when it expires.
/// Being an actor means parallel requests that find the token expired share a single refresh.
actor CloudAccessTokenSource {
    private let accountID: UUID
    private let service: CloudService
    private let store: CloudCredentialStore
    private let session: URLSession
    private var refreshTask: Task<CloudTokens, Error>?

    init(accountID: UUID, service: CloudService, store: CloudCredentialStore, session: URLSession) {
        self.accountID = accountID
        self.service = service
        self.store = store
        self.session = session
    }

    func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard let tokens = store.tokens(for: accountID) else { throw CloudError.accountNotConnected }
        if !forceRefresh, tokens.expiresAt > .now {
            return tokens.accessToken
        }
        return try await refreshed(from: tokens).accessToken
    }

    private func refreshed(from tokens: CloudTokens) async throws -> CloudTokens {
        if let refreshTask {
            return try await refreshTask.value
        }
        guard let credentials = store.appCredentials(for: service), credentials.isComplete else {
            throw CloudError.missingAppCredentials
        }
        let request = OAuthEndpoints.refreshRequest(for: service, refreshToken: tokens.refreshToken, credentials: credentials)
        let session = session
        let store = store
        let accountID = accountID
        let task = Task<CloudTokens, Error> {
            let (data, _) = try await session.data(for: request)
            let reply = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
            guard reply.accessToken != nil else {
                // A refresh token the service refuses cannot recover by retrying; the user has
                // to sign in again.
                throw CloudError.sessionExpired
            }
            let renewed = try reply.tokens(previousRefreshToken: tokens.refreshToken)
            try store.setTokens(renewed, for: accountID)
            return renewed
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }
}

enum CloudError: LocalizedError, Equatable, Sendable {
    case accountNotConnected
    case missingAppCredentials
    case authorizationFailed(String)
    case authorizationCancelled
    case authorizationTimedOut
    case sessionExpired
    case quotaExceeded
    case rateLimited
    case unsupportedItem(name: String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .accountNotConnected:
            L10n.text("This cloud drive is not connected. Connect it again from the sidebar.")
        case .missingAppCredentials:
            L10n.text("Enter the app credentials for this service before connecting.")
        case let .authorizationFailed(reason):
            reason.isEmpty
                ? L10n.text("Authorization failed.")
                : L10n.format("Authorization failed: %@", reason)
        case .authorizationCancelled:
            L10n.text("Authorization was cancelled.")
        case .authorizationTimedOut:
            L10n.text("Authorization timed out. Try connecting again.")
        case .sessionExpired:
            L10n.text("The sign-in for this cloud drive has expired. Connect it again from the sidebar.")
        case .quotaExceeded:
            L10n.text("The cloud drive is full.")
        case .rateLimited:
            L10n.text("The cloud service is receiving too many requests. Try again shortly.")
        case let .unsupportedItem(name):
            L10n.format("“%@” cannot be downloaded from this service.", name)
        case let .server(message):
            message.isEmpty
                ? L10n.text("The cloud service could not complete the request.")
                : L10n.format("The cloud service could not complete the request: %@", message)
        }
    }
}
