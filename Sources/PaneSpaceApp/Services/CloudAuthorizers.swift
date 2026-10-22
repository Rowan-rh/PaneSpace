import CryptoKit
import Foundation
import Network
import Synchronization

/// Google's sign-in for desktop apps: the browser sends the user back to a one-off server on a
/// loopback port, and PKCE ties the returned code to this app instance.
struct GoogleAuthorizer: Sendable {
    static let scope = "https://www.googleapis.com/auth/drive"

    let session: URLSession

    /// Opens the consent page with `openBrowser` and waits up to five minutes for the user.
    func authorize(
        with credentials: CloudAppCredentials,
        openBrowser: @escaping @Sendable (URL) async -> Void
    ) async throws -> CloudTokens {
        let server = try LoopbackRedirectServer()
        defer { server.stop() }
        let redirectURI = try await server.start()
        let verifier = PKCE.makeVerifier()
        let state = UUID().uuidString

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: credentials.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            // Offline access with explicit consent is what makes Google issue a refresh token.
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        guard let authorizationURL = components.url else { throw CloudError.authorizationFailed("") }
        await openBrowser(authorizationURL)

        let parameters = try await withTimeout(.seconds(300)) { try await server.redirectParameters() }
        if let error = parameters["error"] {
            throw error == "access_denied" ? CloudError.authorizationCancelled : CloudError.authorizationFailed(error)
        }
        guard parameters["state"] == state, let code = parameters["code"] else {
            throw CloudError.authorizationFailed("")
        }
        let request = OAuthEndpoints.tokenRequest(for: .googleDrive, parameters: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": credentials.clientID,
            "client_secret": credentials.clientSecret,
            "code_verifier": verifier
        ])
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(OAuthTokenResponse.self, from: data).tokens()
    }
}

/// Baidu's sign-in for devices without a browser of their own: PaneSpace shows a short code,
/// the user approves it on Baidu's page, and PaneSpace polls until the approval arrives. It needs
/// no redirect address registered with the app.
struct BaiduDeviceAuthorizer: Sendable {
    struct DeviceCode: Equatable, Sendable {
        let deviceCode: String
        let userCode: String
        let verificationURL: URL
        let qrCodeURL: URL?
        let expiresAt: Date
        let interval: Duration
    }

    let session: URLSession

    func requestCode(with credentials: CloudAppCredentials) async throws -> DeviceCode {
        let url = URL(string: "https://openapi.baidu.com/oauth/2.0/device/code")!.appendingQuery([
            "response_type": "device_code",
            "client_id": credentials.clientID,
            "scope": "basic,netdisk"
        ])
        let (data, _) = try await session.data(for: URLRequest(url: url))
        let reply = try JSONDecoder().decode(DeviceCodeReply.self, from: data)
        guard let deviceCode = reply.deviceCode, let userCode = reply.userCode,
              let verification = reply.verificationURL.flatMap(URL.init(string:)) else {
            throw CloudError.authorizationFailed(reply.errorDescription ?? reply.error ?? "")
        }
        return DeviceCode(
            deviceCode: deviceCode,
            userCode: userCode,
            verificationURL: verification,
            qrCodeURL: reply.qrcodeURL.flatMap(URL.init(string:)),
            expiresAt: .now.addingTimeInterval(reply.expiresIn ?? 300),
            interval: .seconds(max(reply.interval ?? 5, 2))
        )
    }

    /// Polls at the interval Baidu asked for until the user approves, refuses, or the code expires.
    func tokens(for code: DeviceCode, with credentials: CloudAppCredentials) async throws -> CloudTokens {
        var interval = code.interval
        while Date.now < code.expiresAt {
            try await Task.sleep(for: interval)
            let request = OAuthEndpoints.tokenRequest(for: .baiduNetdisk, parameters: [
                "grant_type": "device_token",
                "code": code.deviceCode,
                "client_id": credentials.clientID,
                "client_secret": credentials.clientSecret
            ])
            let (data, _) = try await session.data(for: request)
            let reply = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
            switch reply.error {
            case nil:
                return try reply.tokens()
            case "authorization_pending":
                continue
            case "slow_down":
                interval += .seconds(5)
            case "authorization_declined", "access_denied":
                throw CloudError.authorizationCancelled
            case "expired_token":
                throw CloudError.authorizationTimedOut
            default:
                throw CloudError.authorizationFailed(reply.errorDescription ?? reply.error ?? "")
            }
        }
        throw CloudError.authorizationTimedOut
    }

    private struct DeviceCodeReply: Decodable {
        let deviceCode: String?
        let userCode: String?
        let verificationURL: String?
        let qrcodeURL: String?
        let expiresIn: Double?
        let interval: Double?
        let error: String?
        let errorDescription: String?

        enum CodingKeys: String, CodingKey {
            case deviceCode = "device_code"
            case userCode = "user_code"
            case verificationURL = "verification_url"
            case qrcodeURL = "qrcode_url"
            case expiresIn = "expires_in"
            case interval
            case error
            case errorDescription = "error_description"
        }
    }
}

enum PKCE {
    static func makeVerifier() -> String {
        let characters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var generator = SystemRandomNumberGenerator()
        return String((0 ..< 64).map { _ in characters.randomElement(using: &generator) ?? "a" })
    }

    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Answers the single browser request that carries the authorization result, on 127.0.0.1 only.
final class LoopbackRedirectServer: Sendable {
    private struct State {
        var readyContinuation: CheckedContinuation<URL, Error>?
        var redirectContinuation: CheckedContinuation<[String: String], Error>?
        var pendingResult: Result<[String: String], Error>?
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "org.panespace.oauth-redirect")
    private let state = Mutex(State())

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    /// Starts listening and returns the redirect address to register in the request.
    func start() async throws -> String {
        let url = try await withCheckedThrowingContinuation { continuation in
            state.withLock { $0.readyContinuation = continuation }
            listener.stateUpdateHandler = { [weak self] newState in
                guard let self else { return }
                switch newState {
                case .ready:
                    let port = self.listener.port?.rawValue ?? 0
                    let continuation = self.state.withLock { state in
                        defer { state.readyContinuation = nil }
                        return state.readyContinuation
                    }
                    continuation?.resume(returning: URL(string: "http://127.0.0.1:\(port)")!)
                case let .failed(error):
                    self.fail(with: error)
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
        }
        return url.absoluteString
    }

    func redirectParameters() async throws -> [String: String] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let pending = state.withLock { state -> Result<[String: String], Error>? in
                    if let result = state.pendingResult { return result }
                    state.redirectContinuation = continuation
                    return nil
                }
                if let pending { continuation.resume(with: pending) }
            }
        } onCancel: {
            self.deliver(.failure(CancellationError()))
        }
    }

    func stop() {
        listener.cancel()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self else { return }
            let parameters = data.flatMap(Self.queryParameters(inRequest:)) ?? [:]
            let isResult = parameters["code"] != nil || parameters["error"] != nil
            let body = isResult ? Self.completionPage : ""
            let status = isResult ? "200 OK" : "404 Not Found"
            let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            if isResult {
                self.deliver(.success(parameters))
            }
        }
    }

    private func fail(with error: Error) {
        let ready = state.withLock { state in
            defer { state.readyContinuation = nil }
            return state.readyContinuation
        }
        ready?.resume(throwing: error)
        deliver(.failure(error))
    }

    private func deliver(_ result: Result<[String: String], Error>) {
        let continuation = state.withLock { state -> CheckedContinuation<[String: String], Error>? in
            guard state.pendingResult == nil else { return nil }
            state.pendingResult = result
            defer { state.redirectContinuation = nil }
            return state.redirectContinuation
        }
        continuation?.resume(with: result)
    }

    /// Reads the query of the request line, such as `GET /?code=…&state=… HTTP/1.1`.
    static func queryParameters(inRequest data: Data) -> [String: String]? {
        guard let text = String(data: data, encoding: .utf8),
              let requestLine = text.split(separator: "\r\n", maxSplits: 1).first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET",
              let components = URLComponents(string: "http://127.0.0.1\(parts[1])") else { return nil }
        var parameters: [String: String] = [:]
        for item in components.queryItems ?? [] {
            parameters[item.name] = item.value ?? ""
        }
        return parameters
    }

    private static let completionPage = """
    <!doctype html><html><head><meta charset="utf-8"><title>PaneSpace</title></head>\
    <body style="font: 15px -apple-system; text-align: center; padding-top: 80px">\
    <h2>PaneSpace</h2><p>You can close this page and return to PaneSpace.</p>\
    <p>可以关闭此页面并返回 PaneSpace。</p></body></html>
    """
}

/// Runs `operation`, failing with `CloudError.authorizationTimedOut` if it takes longer than `limit`.
func withTimeout<Value: Sendable>(
    _ limit: Duration,
    operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    try await withThrowingTaskGroup(of: Value.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: limit)
            throw CloudError.authorizationTimedOut
        }
        defer { group.cancelAll() }
        guard let first = try await group.next() else { throw CloudError.authorizationTimedOut }
        return first
    }
}
