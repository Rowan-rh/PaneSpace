import AppKit
import Foundation

/// Owns the connected cloud drives: the list in the sidebar, signing in and out, and the
/// providers panes and transfers use to reach them.
@MainActor
final class CloudAccountsModel: ObservableObject {
    static let defaultsKey = "cloudAccounts"

    enum ConnectionState: Equatable {
        case idle
        /// Google's consent page is open in the browser.
        case waitingForBrowser
        /// Baidu shows a code the user approves on Baidu's page or by scanning its QR code.
        case waitingForDeviceApproval(BaiduDeviceAuthorizer.DeviceCode)
        case finishing
        case failed(String)

        var isInProgress: Bool {
            switch self {
            case .waitingForBrowser, .waitingForDeviceApproval, .finishing: true
            case .idle, .failed: false
            }
        }
    }

    @Published private(set) var accounts: [CloudAccount]
    @Published private(set) var connectionState: ConnectionState = .idle

    let registry: CloudProviderRegistry
    private let store: CloudCredentialStore
    private let defaults: UserDefaults
    private let session: URLSession
    private let openURL: @MainActor (URL) -> Void
    private let bundledCredentials: (CloudService) -> CloudAppCredentials?
    private var connectionTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        store: CloudCredentialStore = CloudCredentialStore(),
        registry: CloudProviderRegistry = CloudProviderRegistry(),
        session: URLSession = .shared,
        openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) },
        bundledCredentials: @escaping (CloudService) -> CloudAppCredentials? = { CloudAppCredentials.bundled(for: $0) }
    ) {
        self.bundledCredentials = bundledCredentials
        self.defaults = defaults
        self.store = store
        self.registry = registry
        self.session = session
        self.openURL = openURL
        accounts = Self.storedAccounts(in: defaults)
        for account in accounts {
            registry.register(makeProvider(for: account), for: account.id)
        }
    }

    // MARK: Lookup

    func account(for url: URL) -> CloudAccount? {
        guard let location = CloudLocation(url) else { return nil }
        return accounts.first { $0.id == location.accountID }
    }

    /// The drive's title for a cloud location, or nil for local URLs.
    func title(for url: URL) -> String? {
        guard let location = CloudLocation(url) else { return nil }
        let name = accounts.first { $0.id == location.accountID }?.name ?? L10n.text(location.service.title)
        return location.isRoot ? name : location.name
    }

    /// How a location reads in the status bar and history: the drive's name, then the path inside it.
    func displayPath(for url: URL) -> String {
        guard let location = CloudLocation(url) else { return url.path }
        let name = accounts.first { $0.id == location.accountID }?.name ?? L10n.text(location.service.title)
        return location.isRoot ? name : "\(name):\(location.path)"
    }

    // MARK: App credentials

    /// The credentials the user saved, or nil when they have not entered any.
    func savedAppCredentials(for service: CloudService) -> CloudAppCredentials? {
        store.appCredentials(for: service)
    }

    /// Whether this build carries its own credentials, so the user only needs to sign in.
    func hasBundledCredentials(for service: CloudService) -> Bool {
        bundledCredentials(service) != nil
    }

    // MARK: Connecting

    /// Saves the app credentials and signs in. `didConnect` receives the new drive so it can be opened.
    /// Signs in with the credentials the user entered, or with the build's own when the user left
    /// them empty. `didConnect` receives the new drive so it can be opened.
    func connect(
        _ service: CloudService,
        credentials entered: CloudAppCredentials,
        didConnect: @escaping @MainActor (CloudAccount) -> Void
    ) {
        guard !connectionState.isInProgress else { return }
        let entered = entered.trimmed
        let credentials: CloudAppCredentials
        if entered.isComplete {
            do {
                try store.setAppCredentials(entered, for: service)
            } catch {
                connectionState = .failed(error.localizedDescription)
                return
            }
            credentials = entered
        } else if let bundled = bundledCredentials(service) {
            // Tokens are refreshed with the credentials that issued them, so the build's own are
            // stored too; a later build without them keeps working until the user signs out.
            try? store.setAppCredentials(bundled, for: service)
            credentials = bundled
        } else {
            connectionState = .failed(CloudError.missingAppCredentials.localizedDescription)
            return
        }

        connectionTask = Task {
            do {
                let tokens = try await authorize(service, credentials: credentials)
                connectionState = .finishing
                let account = try await finishConnecting(service, tokens: tokens, appFolder: credentials.appFolder)
                connectionState = .idle
                didConnect(account)
            } catch is CancellationError {
                connectionState = .idle
            } catch CloudError.authorizationCancelled where Task.isCancelled {
                connectionState = .idle
            } catch {
                connectionState = .failed(error.localizedDescription)
            }
            connectionTask = nil
        }
    }

    func cancelConnection() {
        connectionTask?.cancel()
        connectionTask = nil
        connectionState = .idle
    }

    func dismissConnectionError() {
        if case .failed = connectionState {
            connectionState = .idle
        }
    }

    private func authorize(_ service: CloudService, credentials: CloudAppCredentials) async throws -> CloudTokens {
        switch service {
        case .googleDrive:
            connectionState = .waitingForBrowser
            let openURL = openURL
            return try await GoogleAuthorizer(session: session).authorize(with: credentials) { url in
                await openURL(url)
            }
        case .baiduNetdisk:
            let authorizer = BaiduDeviceAuthorizer(session: session)
            let code = try await authorizer.requestCode(with: credentials)
            connectionState = .waitingForDeviceApproval(code)
            return try await authorizer.tokens(for: code, with: credentials)
        }
    }

    private func finishConnecting(_ service: CloudService, tokens: CloudTokens, appFolder: String?) async throws -> CloudAccount {
        var account = CloudAccount(
            service: service,
            name: service.title,
            homePath: service == .baiduNetdisk ? appFolder.map { "/apps/\($0)" } ?? "/" : "/"
        )
        try store.setTokens(tokens, for: account.id)
        do {
            let client = makeClient(for: account)
            account.name = switch service {
            case .googleDrive: try await GoogleDriveProvider.accountName(client: client)
            case .baiduNetdisk: try await BaiduNetdiskProvider.accountName(client: client)
            }
        } catch is CancellationError {
            store.removeTokens(for: account.id)
            throw CancellationError()
        } catch {
            // The sign-in worked; a drive without its owner's name is still usable.
        }
        registry.register(makeProvider(for: account), for: account.id)
        accounts.append(account)
        save()
        return account
    }

    // MARK: Disconnecting

    /// Forgets the drive and its tokens. Files in the drive are not touched.
    func disconnect(_ account: CloudAccount) {
        store.removeTokens(for: account.id)
        registry.remove(account.id)
        accounts.removeAll { $0.id == account.id }
        save()
    }

    // MARK: Providers

    private func makeClient(for account: CloudAccount) -> CloudHTTPClient {
        switch account.service {
        case .googleDrive:
            GoogleDriveProvider.makeClient(accountID: account.id, store: store, session: session)
        case .baiduNetdisk:
            BaiduNetdiskProvider.makeClient(accountID: account.id, store: store, session: session)
        }
    }

    private func makeProvider(for account: CloudAccount) -> any RemoteFileProviding {
        let client = makeClient(for: account)
        return switch account.service {
        case .googleDrive: GoogleDriveProvider(accountID: account.id, client: client)
        case .baiduNetdisk: BaiduNetdiskProvider(accountID: account.id, client: client)
        }
    }

    // MARK: Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private static func storedAccounts(in defaults: UserDefaults) -> [CloudAccount] {
        guard let data = defaults.data(forKey: defaultsKey),
              let accounts = try? JSONDecoder().decode([CloudAccount].self, from: data) else { return [] }
        return accounts
    }
}
