import AppKit
import Foundation
import XCTest
@testable import PaneSpaceApp

final class CloudLocationTests: XCTestCase {
    private let accountID = UUID()

    func testRoundTripsPathsWithSpacesAndReservedCharacters() throws {
        let location = CloudLocation(service: .googleDrive, accountID: accountID, path: "/项目 资料/a?b#c%d")
        let url = location.url(isDirectory: false)

        let parsed = try XCTUnwrap(CloudLocation(url))
        XCTAssertEqual(parsed, location)
        XCTAssertEqual(url.lastPathComponent, "a?b#c%d")
        XCTAssertEqual(parsed.parent.path, "/项目 资料")
        XCTAssertFalse(url.isFileURL)
        XCTAssertTrue(CloudLocation.isCloud(url))
    }

    func testFoldersCarryATrailingSlashAndTheRootIsItsOwnParent() throws {
        let root = CloudLocation(service: .baiduNetdisk, accountID: accountID, path: "/")
        XCTAssertTrue(root.isRoot)
        XCTAssertEqual(root.url.deletingLastPathComponent(), root.url)
        XCTAssertTrue(root.appending("Docs").url.absoluteString.hasSuffix("/Docs/"))
        XCTAssertEqual(CloudLocation(service: .baiduNetdisk, accountID: accountID, path: "//apps//x/").path, "/apps/x")
    }

    @MainActor
    func testGoingUpStopsAtTheDriveRoot() async throws {
        let root = CloudLocation(service: .googleDrive, accountID: accountID, path: "/").url
        let folder = CloudLocation(service: .googleDrive, accountID: accountID, path: "/Docs").url
        let provider = StaticDirectoryProvider([root: [], folder: []])
        let pane = BrowserPaneModel(url: folder, provider: provider)

        XCTAssertTrue(pane.goUp())
        XCTAssertEqual(pane.currentURL, root)
        XCTAssertFalse(pane.goUp())
    }

    func testComparablePathsKeepDrivesApartFromEachOtherAndFromTheMac() {
        let first = CloudLocation(service: .googleDrive, accountID: accountID, path: "/Docs").url
        let second = CloudLocation(service: .googleDrive, accountID: UUID(), path: "/Docs").url
        let local = URL(fileURLWithPath: "/Docs", isDirectory: true)

        let paths = Set([first, second, local].map(BrowserPaneModel.comparablePath))
        XCTAssertEqual(paths.count, 3)
        XCTAssertEqual(
            BrowserPaneModel.comparablePath(first),
            BrowserPaneModel.comparablePath(CloudLocation(first)!.url(isDirectory: false))
        )
    }

    @MainActor
    func testTypedPathsInADriveStayInThatDrive() async throws {
        let docs = CloudLocation(service: .googleDrive, accountID: accountID, path: "/Docs").url
        let pane = BrowserPaneModel(url: docs, provider: StaticDirectoryProvider([docs: []]))

        let enteredRelative = await pane.navigateToEnteredLocation("Reports/../2026")
        XCTAssertTrue(enteredRelative)
        XCTAssertEqual(CloudLocation(pane.currentURL)?.path, "/Docs/2026")
        let enteredAbsolute = await pane.navigateToEnteredLocation("/Photos")
        XCTAssertTrue(enteredAbsolute)
        XCTAssertEqual(CloudLocation(pane.currentURL)?.path, "/Photos")
        XCTAssertEqual(CloudLocation(pane.currentURL)?.accountID, accountID)
    }

    func testOperationsOnCloudDrivesAreRecordedButNotUndoable() {
        let item = CloudLocation(service: .googleDrive, accountID: accountID, path: "/a.txt").url(isDirectory: false)
        let record = OperationRecord(
            kind: .rename,
            outcome: .completed,
            directory: CloudLocation(service: .googleDrive, accountID: accountID, path: "/").url,
            items: [OperationRecordItem(original: item, result: item)],
            requestedCount: 1
        )
        XCTAssertTrue(record.touchesCloudDrive)
        XCTAssertFalse(OperationUndoService.canUndo(record))
    }

    @MainActor
    func testPasteboardCarriesCloudItemsAlongsideFiles() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let filePasteboard = FilePasteboard(pasteboard: pasteboard)
        let local = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: local)
        defer { try? FileManager.default.removeItem(at: local) }
        let cloud = CloudLocation(service: .baiduNetdisk, accountID: accountID, path: "/apps/x/b.txt").url(isDirectory: false)

        filePasteboard.write([local, cloud])

        XCTAssertEqual(filePasteboard.fileURLs().map(\.standardizedFileURL), [local.standardizedFileURL])
        XCTAssertEqual(filePasteboard.cloudURLs(), [cloud])
    }
}

final class CloudAuthorizationTests: XCTestCase {
    func testPKCEChallengeMatchesTheRFCExample() {
        XCTAssertEqual(
            PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        )
        XCTAssertEqual(PKCE.makeVerifier().count, 64)
    }

    func testLoopbackServerReturnsTheRedirectQuery() async throws {
        let server = try LoopbackRedirectServer()
        defer { server.stop() }
        let redirectURI = try await server.start()
        XCTAssertTrue(redirectURI.hasPrefix("http://127.0.0.1:"))

        async let parameters = server.redirectParameters()
        // The browser's request for the favicon must not end the wait.
        _ = try? await URLSession.shared.data(from: try XCTUnwrap(URL(string: "\(redirectURI)/favicon.ico")))
        let (_, response) = try await URLSession.shared.data(from: try XCTUnwrap(URL(string: "\(redirectURI)/?code=abc%2F1&state=s")))

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let received = try await parameters
        XCTAssertEqual(received["code"], "abc/1")
        XCTAssertEqual(received["state"], "s")
    }

    func testExpiredTokenIsRefreshedOnceAndBaiduRotationIsStored() async throws {
        let accountID = UUID()
        let store = try CloudCredentialStore.testing(accountID: accountID, service: .baiduNetdisk, expiresAt: .distantPast)
        let session = StubURLProtocol.session { request in
            XCTAssertEqual(request.queryValue("grant_type"), "refresh_token")
            XCTAssertEqual(request.queryValue("refresh_token"), "refresh-1")
            return .json(["access_token": "access-2", "refresh_token": "refresh-2", "expires_in": 2_592_000])
        }
        let source = CloudAccessTokenSource(accountID: accountID, service: .baiduNetdisk, store: store, session: session)

        async let first = source.accessToken()
        async let second = source.accessToken()
        let tokens = try await [first, second]

        XCTAssertEqual(tokens, ["access-2", "access-2"])
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
        XCTAssertEqual(store.tokens(for: accountID)?.refreshToken, "refresh-2")
    }

    func testRefusedRefreshAsksTheUserToConnectAgain() async throws {
        let accountID = UUID()
        let store = try CloudCredentialStore.testing(accountID: accountID, service: .googleDrive, expiresAt: .distantPast)
        let session = StubURLProtocol.session { _ in
            .json(["error": "invalid_grant"], status: 400)
        }
        let source = CloudAccessTokenSource(accountID: accountID, service: .googleDrive, store: store, session: session)

        do {
            _ = try await source.accessToken()
            XCTFail("Expected the refresh to fail")
        } catch let error as CloudError {
            XCTAssertEqual(error, .sessionExpired)
        }
    }
}
