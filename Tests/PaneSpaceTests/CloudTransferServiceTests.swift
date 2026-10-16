import Foundation
import Synchronization
import XCTest
@testable import PaneSpaceApp

final class CloudTransferServiceTests: XCTestCase {
    private var root: URL!
    private var drive: InMemoryCloudDrive!
    private var registry: CloudProviderRegistry!
    private var trashedLocalItems: TrashRecorder!
    private var service: CloudTransferService!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        drive = InMemoryCloudDrive()
        registry = CloudProviderRegistry()
        registry.register(drive, for: drive.accountID)
        let trashed = TrashRecorder()
        trashedLocalItems = trashed
        service = CloudTransferService(registry: registry) { url in
            trashed.urls.withLock { $0.append(url) }
            try FileManager.default.removeItem(at: url)
            return nil
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeLocalFolder() throws -> URL {
        let folder = root.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("src", isDirectory: true), withIntermediateDirectories: true)
        try Data("readme".utf8).write(to: folder.appendingPathComponent("README.md"))
        try Data("main".utf8).write(to: folder.appendingPathComponent("src/main.swift"))
        try Data("view".utf8).write(to: folder.appendingPathComponent(".DS_Store"))
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("loop"), withDestinationURL: folder)
        return folder
    }

    func testUploadsAFolderUnderAStagingNameAndPublishesItWhenComplete() async throws {
        let folder = try makeLocalFolder()
        let destination = await drive.url("/", isDirectory: true)
        let counter = TransferByteCounter()

        let outcome = try await service.transfer(source: folder, to: destination, kind: .copy, conflictDecision: nil, progress: counter)

        let expected = await drive.url("/Project", isDirectory: true)
        XCTAssertEqual(outcome?.destination, expected)
        let paths = await drive.paths
        XCTAssertEqual(paths, ["/", "/Project", "/Project/README.md", "/Project/src", "/Project/src/main.swift"])
        let readme = await drive.contents(at: "/Project/README.md")
        XCTAssertEqual(readme, "readme")
        XCTAssertEqual(counter.value, Int64("readme".count + "main".count))
    }

    func testKeepBothAndReplaceSettleConflictsInADrive() async throws {
        let source = root.appendingPathComponent("a.txt")
        try Data("new".utf8).write(to: source)
        await drive.addFile("/a.txt", contents: "old")
        let destination = await drive.url("/", isDirectory: true)

        let proposed = await service.destination(for: source, in: destination)
        let conflict = await service.exists(at: proposed)
        XCTAssertTrue(conflict)

        let kept = try await service.transfer(source: source, to: destination, kind: .copy, conflictDecision: .keepBoth, progress: nil)
        let keptURL = await drive.url("/a copy 2.txt")
        XCTAssertEqual(kept?.destination, keptURL)

        _ = try await service.transfer(source: source, to: destination, kind: .copy, conflictDecision: .replace, progress: nil)
        let replaced = await drive.contents(at: "/a.txt")
        XCTAssertEqual(replaced, "new")
        let trashed = await drive.trashed
        XCTAssertEqual(trashed, ["/a.txt"])

        do {
            _ = try await service.transfer(source: source, to: destination, kind: .copy, conflictDecision: nil, progress: nil)
            XCTFail("An undecided conflict must not overwrite anything")
        } catch let error as LocalTransferError {
            guard case .destinationExists = error else { return XCTFail("Unexpected \(error)") }
        }
    }

    func testDownloadsAFolderToTheMac() async throws {
        await drive.addFolder("/Photos")
        await drive.addFolder("/Photos/2026")
        await drive.addFile("/Photos/2026/beach.jpg", contents: "jpg")
        let source = await drive.url("/Photos", isDirectory: true)

        let outcome = try await service.transfer(source: source, to: root, kind: .copy, conflictDecision: nil, progress: nil)

        let destination = try XCTUnwrap(outcome?.destination)
        XCTAssertEqual(destination.lastPathComponent, "Photos")
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("2026/beach.jpg"), encoding: .utf8), "jpg")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertEqual(leftovers, ["Photos"])
    }

    func testMovingInsideOneDriveLetsTheServiceMoveIt() async throws {
        await drive.addFolder("/Inbox")
        await drive.addFolder("/Archive")
        await drive.addFile("/Inbox/report.pdf", contents: "pdf")
        let source = await drive.url("/Inbox/report.pdf")
        let destination = await drive.url("/Archive", isDirectory: true)

        let outcome = try await service.transfer(source: source, to: destination, kind: .move, conflictDecision: nil, progress: nil)

        let moved = await drive.url("/Archive/report.pdf")
        XCTAssertEqual(outcome?.destination, moved)
        let downloads = await drive.downloadCount
        XCTAssertEqual(downloads, 0)
        let paths = await drive.paths
        XCTAssertFalse(paths.contains("/Inbox/report.pdf"))
    }

    func testMovingFromTheMacRemovesTheSourceOnlyAfterTheUpload() async throws {
        let source = root.appendingPathComponent("notes.txt")
        try Data("notes".utf8).write(to: source)
        let destination = await drive.url("/", isDirectory: true)

        _ = try await service.transfer(source: source, to: destination, kind: .move, conflictDecision: nil, progress: nil)

        let uploaded = await drive.contents(at: "/notes.txt")
        XCTAssertEqual(uploaded, "notes")
        XCTAssertEqual(trashedLocalItems.urls.withLock { $0 }, [source])
    }

    func testRefusesToMoveAFolderIntoItself() async throws {
        await drive.addFolder("/A")
        await drive.addFolder("/A/B")
        let source = await drive.url("/A", isDirectory: true)
        let destination = await drive.url("/A/B", isDirectory: true)

        do {
            try await service.validate(source: source, destinationDirectory: destination, kind: .move)
            XCTFail("Expected an invalid destination")
        } catch let error as LocalTransferError {
            guard case .invalidDestination = error else { return XCTFail("Unexpected \(error)") }
        }
    }

    func testDisconnectedDrivesFailClearly() async throws {
        let stranger = CloudLocation(service: .googleDrive, accountID: UUID(), path: "/x.txt").url(isDirectory: false)

        do {
            try await service.validate(source: stranger, destinationDirectory: root, kind: .copy)
            XCTFail("Expected an error")
        } catch let error as CloudError {
            XCTAssertEqual(error, .accountNotConnected)
        }
    }

    func testRoutingProviderSendsCloudLocationsToTheirDrive() async throws {
        await drive.addFile("/a.txt", contents: "hello")
        let routing = RoutingFileProvider(cloud: registry)
        let file = await drive.url("/a.txt")

        let capacity = await routing.availableCapacity(for: await drive.url("/", isDirectory: true))
        XCTAssertEqual(capacity, 1_000)
        let copy = try await routing.materialize(file)
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        XCTAssertTrue(copy.isFileURL)
        XCTAssertEqual(copy.lastPathComponent, "a.txt")
        XCTAssertEqual(try String(contentsOf: copy, encoding: .utf8), "hello")
        let local = root.appendingPathComponent("b.txt")
        let unchanged = try await routing.materialize(local)
        XCTAssertEqual(unchanged, local)
    }

    @MainActor
    func testQueueRoutesCloudTransfersAndRefreshesBothFolders() async throws {
        let source = root.appendingPathComponent("a.txt")
        try Data("a".utf8).write(to: source)
        let destination = await drive.url("/", isDirectory: true)
        var refreshed: [(URL, URL)] = []
        let queue = FileTransferQueueModel(service: RoutingTransferService(cloud: service)) { refreshed.append(($0, $1)) }

        queue.enqueue(kind: .copy, sources: [source], destinationDirectory: destination)
        try await waitForPane { queue.jobs.first?.state == .completed }

        XCTAssertEqual(queue.jobs.first?.totalBytes, 1)
        XCTAssertEqual(refreshed.first?.1, destination)
        let uploaded = await drive.contents(at: "/a.txt")
        XCTAssertEqual(uploaded, "a")
    }
}

private final class TrashRecorder: Sendable {
    let urls = Mutex<[URL]>([])
}

final class CloudAccountsModelTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "CloudAccountsModelTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    @MainActor
    func testRestoresAccountsAndForgetsThemOnDisconnect() throws {
        let account = CloudAccount(service: .baiduNetdisk, name: "网盘用户", homePath: "/apps/PaneSpace")
        defaults.set(try JSONEncoder().encode([account]), forKey: CloudAccountsModel.defaultsKey)
        let store = try CloudCredentialStore.testing(accountID: account.id, service: .baiduNetdisk)
        let model = CloudAccountsModel(defaults: defaults, store: store, session: StubURLProtocol.session { _ in .json([:]) })

        XCTAssertEqual(model.accounts, [account])
        XCTAssertNotNil(model.registry.provider(for: account.id))
        XCTAssertEqual(model.title(for: account.rootURL), "网盘用户")
        XCTAssertEqual(model.displayPath(for: account.homeURL), "网盘用户:/apps/PaneSpace")
        XCTAssertNil(model.title(for: URL(fileURLWithPath: "/tmp")))

        model.disconnect(account)

        XCTAssertTrue(model.accounts.isEmpty)
        XCTAssertNil(model.registry.provider(for: account.id))
        XCTAssertNil(store.tokens(for: account.id))
        let reloaded = CloudAccountsModel(defaults: defaults, store: store)
        XCTAssertTrue(reloaded.accounts.isEmpty)
    }

    @MainActor
    func testConnectingBaiduShowsTheCodeAndAddsTheAccount() async throws {
        let store = CloudCredentialStore(secrets: InMemorySecretStore())
        let session = StubURLProtocol.session { request in
            switch request.url?.path {
            case "/oauth/2.0/device/code":
                XCTAssertEqual(request.queryValue("scope"), "basic,netdisk")
                return .json([
                    "device_code": "D", "user_code": "U8", "verification_url": "https://openapi.baidu.com/device",
                    "qrcode_url": "https://openapi.baidu.com/device/qrcode/x/U8", "expires_in": 300, "interval": 0
                ])
            case "/oauth/2.0/token":
                XCTAssertEqual(request.queryValue("grant_type"), "device_token")
                XCTAssertEqual(request.queryValue("client_secret"), "S")
                return .json(["access_token": "A", "refresh_token": "R", "expires_in": 2_592_000])
            default:
                return .json(["errno": 0, "netdisk_name": "网盘用户", "baidu_name": "百度用户"])
            }
        }
        let model = CloudAccountsModel(defaults: defaults, store: store, session: session) { _ in }
        var connected: CloudAccount?

        model.connect(.baiduNetdisk, credentials: CloudAppCredentials(clientID: " K ", clientSecret: "S", appFolder: "/PaneSpace/")) {
            connected = $0
        }
        try await waitForPane(timeoutIterations: 500) { connected != nil || { if case .failed = model.connectionState { true } else { false } }() }

        let account = try XCTUnwrap(connected)
        XCTAssertEqual(account.name, "网盘用户")
        XCTAssertEqual(account.homePath, "/apps/PaneSpace")
        XCTAssertEqual(model.accounts, [account])
        XCTAssertEqual(store.tokens(for: account.id)?.refreshToken, "R")
        XCTAssertEqual(store.appCredentials(for: .baiduNetdisk)?.clientID, "K")
        XCTAssertEqual(model.connectionState, .idle)
    }

    @MainActor
    func testConnectingWithoutCredentialsExplainsWhatIsMissing() {
        let model = CloudAccountsModel(
            defaults: defaults,
            store: CloudCredentialStore(secrets: InMemorySecretStore()),
            bundledCredentials: { _ in nil }
        )

        model.connect(.googleDrive, credentials: CloudAppCredentials(clientID: "", clientSecret: "")) { _ in
            XCTFail("Nothing should connect")
        }

        XCTAssertEqual(model.connectionState, .failed(CloudError.missingAppCredentials.localizedDescription))
    }

    @MainActor
    func testBuildCredentialsLetUsersSignInWithoutEnteringAny() async throws {
        let store = CloudCredentialStore(secrets: InMemorySecretStore())
        let session = StubURLProtocol.session { request in
            switch request.url?.path {
            case "/oauth/2.0/device/code":
                XCTAssertEqual(request.queryValue("client_id"), "built-in")
                return .json(["error": "invalid_client", "error_description": "stop here"])
            default:
                return .json([:])
            }
        }
        let builtIn = CloudAppCredentials(clientID: "built-in", clientSecret: "secret")
        let model = CloudAccountsModel(defaults: defaults, store: store, session: session) { _ in } bundledCredentials: {
            $0 == .baiduNetdisk ? builtIn : nil
        }
        XCTAssertTrue(model.hasBundledCredentials(for: .baiduNetdisk))
        XCTAssertFalse(model.hasBundledCredentials(for: .googleDrive))

        model.connect(.baiduNetdisk, credentials: CloudAppCredentials(clientID: "", clientSecret: "")) { _ in }
        try await waitForPane { if case .failed = model.connectionState { true } else { false } }

        XCTAssertEqual(model.connectionState, .failed(CloudError.authorizationFailed("stop here").localizedDescription))
        // Kept so tokens issued with them can still be refreshed.
        XCTAssertEqual(store.appCredentials(for: .baiduNetdisk), builtIn)
    }

    func testBuildCredentialsAreReadFromTheInfoDictionary() throws {
        let bundleURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bundleURL) }
        let info: [String: Any] = [
            "CFBundleIdentifier": "org.panespace.tests",
            "PaneSpaceGoogleDriveClientID": " id ",
            "PaneSpaceGoogleDriveClientSecret": "secret",
            "PaneSpaceBaiduNetdiskClientID": "only-a-key"
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: bundleURL.appendingPathComponent("Info.plist"))
        let bundle = try XCTUnwrap(Bundle(url: bundleURL))

        XCTAssertEqual(CloudAppCredentials.bundled(for: .googleDrive, in: bundle), CloudAppCredentials(clientID: "id", clientSecret: "secret"))
        XCTAssertNil(CloudAppCredentials.bundled(for: .baiduNetdisk, in: bundle))
    }
}
