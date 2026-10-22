import Foundation
import Synchronization

/// Sends authorized requests for one cloud account. An expired or revoked access token is
/// refreshed once and the request retried; anything else is left to the provider to interpret.
struct CloudHTTPClient: Sendable {
    let session: URLSession
    let tokens: CloudAccessTokenSource
    /// Google takes the token in a header, Baidu as a query parameter.
    let authorize: @Sendable (inout URLRequest, String) -> Void

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var forceRefresh = false
        while true {
            var authorized = request
            authorize(&authorized, try await tokens.accessToken(forceRefresh: forceRefresh))
            let (data, response) = try await session.data(for: authorized)
            guard let response = response as? HTTPURLResponse else { throw CloudError.server("") }
            if response.statusCode == 401, !forceRefresh {
                forceRefresh = true
                continue
            }
            return (data, response)
        }
    }

    /// Downloads to `localURL`, reporting received bytes as they arrive. The system writes the
    /// body to disk itself; progress is sampled from the task rather than read byte by byte.
    func download(
        _ request: URLRequest,
        to localURL: URL,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws -> HTTPURLResponse {
        var forceRefresh = false
        while true {
            var authorized = request
            authorize(&authorized, try await tokens.accessToken(forceRefresh: forceRefresh))
            let observer = DownloadProgressObserver()
            let sampler = Task {
                var reported: Int64 = 0
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(150))
                    let received = observer.receivedBytes
                    if received > reported {
                        progress(received - reported)
                        reported = received
                    }
                }
                return reported
            }
            let (temporaryURL, response): (URL, URLResponse)
            do {
                (temporaryURL, response) = try await session.download(for: authorized, delegate: observer)
            } catch {
                sampler.cancel()
                throw error
            }
            sampler.cancel()
            let reported = await sampler.value
            guard let response = response as? HTTPURLResponse else { throw CloudError.server("") }
            if response.statusCode == 401, !forceRefresh {
                try? FileManager.default.removeItem(at: temporaryURL)
                forceRefresh = true
                continue
            }
            guard (200 ..< 300).contains(response.statusCode) else {
                try? FileManager.default.removeItem(at: temporaryURL)
                throw CloudHTTPClient.statusError(response.statusCode)
            }
            let size = (try? FileManager.default.attributesOfItem(atPath: temporaryURL.path)[.size] as? Int64) ?? reported
            if size > reported { progress(size - reported) }
            if FileManager.default.fileExists(atPath: localURL.path) {
                try FileManager.default.removeItem(at: localURL)
            }
            try FileManager.default.moveItem(at: temporaryURL, to: localURL)
            return response
        }
    }

    static func statusError(_ statusCode: Int) -> CloudError {
        switch statusCode {
        case 401: .sessionExpired
        case 429: .rateLimited
        default: .server(HTTPURLResponse.localizedString(forStatusCode: statusCode))
        }
    }
}

/// Captures the download task so its received byte count can be sampled.
private final class DownloadProgressObserver: NSObject, URLSessionTaskDelegate, Sendable {
    private let task = Mutex<URLSessionTask?>(nil)

    var receivedBytes: Int64 {
        task.withLock { $0?.countOfBytesReceived ?? 0 }
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        self.task.withLock { $0 = task }
    }
}

extension URLRequest {
    init(url: URL, method: String, form: [String: String]? = nil, json: Any? = nil) {
        self.init(url: url)
        httpMethod = method
        if let form {
            setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            httpBody = Data(OAuthEndpoints.formEncoded(form).utf8)
        } else if let json, let body = try? JSONSerialization.data(withJSONObject: json) {
            setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            httpBody = body
        }
    }
}

extension URL {
    func appendingQuery(_ items: [String: String]) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        components.queryItems = (components.queryItems ?? []) + items.sorted { $0.key < $1.key }.map {
            URLQueryItem(name: $0.key, value: $0.value)
        }
        // URLComponents leaves "+" unescaped in queries, and servers read it as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url ?? self
    }
}
