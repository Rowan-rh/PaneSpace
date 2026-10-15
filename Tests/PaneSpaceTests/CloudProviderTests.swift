import Foundation
import XCTest
@testable import PaneSpaceApp

final class GoogleDriveProviderTests: XCTestCase {
    private let accountID = UUID()

    private func makeProvider(
        expiresAt: Date = .now.addingTimeInterval(3_600),
        handler: @escaping StubURLProtocol.Handler
    ) throws -> (GoogleDriveProvider, CloudCredentialStore) {
        let store = try CloudCredentialStore.testing(accountID: accountID, service: .googleDrive, expiresAt: expiresAt)
        let session = StubURLProtocol.session(handler: handler)
        let client = GoogleDriveProvider.makeClient(accountID: accountID, store: store, session: session)
        return (GoogleDriveProvider(accountID: accountID, client: client), store)
    }

    private func url(_ path: String, isDirectory: Bool = true) -> URL {
        CloudLocation(service: .googleDrive, accountID: accountID, path: path).url(isDirectory: isDirectory)
    }

    private static func file(_ id: String, _ name: String, folder: Bool = false, mimeType: String? = nil, size: String? = nil) -> [String: Any] {
        var file: [String: Any] = [
            "id": id,
            "name": name,
            "mimeType": folder ? GoogleDriveProvider.folderMimeType : mimeType ?? "text/plain",
            "modifiedTime": "2026-10-01T08:30:00.123Z"
        ]
        file["size"] = size
        return file
    }

    func testListsPagesAsBatchesAndTellsDuplicateNamesApart() async throws {
        let (provider, _) = try makeProvider { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-1")
            XCTAssertEqual(request.queryValue("q"), "'root' in parents and trashed = false")
            if request.queryValue("pageToken") == nil {
                return .json(["files": [Self.file("f1", "Docs", folder: true), Self.file("a1", "a.txt", size: "12")], "nextPageToken": "next"])
            }
            return .json(["files": [
                Self.file("a2abcdefg", "a.txt", size: "3"),
                Self.file("h1", ".hidden"),
                Self.file("g1", "Budget", mimeType: "application/vnd.google-apps.spreadsheet")
            ]])
        }

        var batches: [[FileItem]] = []
        for try await batch in provider.contentBatches(of: url("/"), showsHiddenFiles: false) {
            batches.append(batch)
        }

        XCTAssertEqual(batches.count, 2)
        let items = batches.flatMap(\.self)
        XCTAssertEqual(items.map(\.name), ["Docs", "a.txt", "a [a2abcd].txt", "Budget"])
        XCTAssertEqual(items[0].url, url("/Docs"))
        XCTAssertTrue(items[0].isFolder)
        XCTAssertEqual(items[1].fileSize, 12)
        XCTAssertNotNil(items[1].modificationDate)
        XCTAssertNil(items[3].fileSize)
    }

    func testResolvesUnseenPathsFolderByFolder() async throws {
        let (provider, _) = try makeProvider { request in
            let query = request.queryValue("q") ?? ""
            if query == "name = 'Work' and 'root' in parents and trashed = false" {
                return .json(["files": [Self.file("w1", "Work", folder: true)]])
            }
            if query == "name = 'Bob\\'s' and 'w1' in parents and trashed = false" {
                return .json(["files": [Self.file("b1", "Bob's", folder: true)]])
            }
            if query == "'b1' in parents and trashed = false" {
                return .json(["files": [Self.file("x1", "x.txt")]])
            }
            XCTFail("Unexpected query \(query)")
            return .json(["files": []])
        }

        let items = try await provider.contents(of: url("/Work/Bob's"), showsHiddenFiles: false)

        XCTAssertEqual(items.map(\.url), [url("/Work/Bob's/x.txt", isDirectory: false)])
    }

    func testCreatingAFolderRefusesANameAlreadyInUse() async throws {
        let (provider, _) = try makeProvider { request in
            if request.httpMethod == "POST" {
                XCTFail("A duplicate folder must not be created")
            }
            return .json(["files": [Self.file("d1", "Docs", folder: true)]])
        }

        do {
            _ = try await provider.createFolder(named: "Docs", in: url("/"))
            XCTFail("Expected a conflict")
        } catch let error as FileProviderError {
            XCTAssertEqual(error, .itemAlreadyExists)
        }
    }

    func testRenameAndTrashUpdateTheItem() async throws {
        let (provider, _) = try makeProvider { request in
            switch request.httpMethod {
            case "PATCH" where request.url?.path.hasSuffix("/files/a1") == true:
                if request.jsonBody["trashed"] as? Bool == true {
                    return .json(["id": "a1"])
                }
                XCTAssertEqual(request.jsonBody["name"] as? String, "b.txt")
                return .json(Self.file("a1", "b.txt"))
            default:
                // Only the original name exists; the new name is free.
                let query = request.queryValue("q") ?? ""
                return .json(["files": query.contains("name = 'a.txt'") ? [Self.file("a1", "a.txt")] : []])
            }
        }

        let renamed = try await provider.rename(url("/a.txt", isDirectory: false), to: " b.txt ")
        XCTAssertEqual(renamed, url("/b.txt", isDirectory: false))

        let trashed = try await provider.moveToTrash(renamed)
        XCTAssertNil(trashed)
        XCTAssertEqual(StubURLProtocol.requests.last?.jsonBody["trashed"] as? Bool, true)
    }

    func testRejectedTokenIsRefreshedAndTheRequestRetried() async throws {
        let (provider, store) = try makeProvider { request in
            if request.url?.host() == "oauth2.googleapis.com" {
                XCTAssertEqual(request.formValues["grant_type"], "refresh_token")
                return .json(["access_token": "access-2", "expires_in": 3_600])
            }
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer access-1" {
                return .json(["error": ["code": 401, "message": "Invalid Credentials"]], status: 401)
            }
            return .json(["files": [Self.file("a1", "a.txt")]])
        }

        let items = try await provider.contents(of: url("/"), showsHiddenFiles: false)

        XCTAssertEqual(items.map(\.name), ["a.txt"])
        XCTAssertEqual(store.tokens(for: accountID)?.accessToken, "access-2")
        // Google keeps its refresh token, so the old one is still stored.
        XCTAssertEqual(store.tokens(for: accountID)?.refreshToken, "refresh-1")
    }

    func testGoogleDocumentsDownloadAsExportedFiles() async throws {
        let (provider, _) = try makeProvider { request in
            if request.url?.path.hasSuffix("/export") == true {
                XCTAssertEqual(request.queryValue("mimeType"), "application/vnd.openxmlformats-officedocument.wordprocessingml.document")
                return StubURLProtocol.Reply(body: Data("docx".utf8))
            }
            return .json(["files": [Self.file("d1", "Plan", mimeType: "application/vnd.google-apps.document")]])
        }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: destination) }

        let savedName = try await provider.download(url("/Plan", isDirectory: false), to: destination) { _ in }

        XCTAssertEqual(savedName, "Plan.docx")
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "docx")
    }

    func testUploadsInResumableChunks() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("hello".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let (provider, _) = try makeProvider { request in
            if request.url?.host() == "upload.example" {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Range"), "bytes 0-4/5")
                XCTAssertEqual(request.httpBody, Data("hello".utf8))
                return .json(Self.file("u1", "hello.txt"))
            }
            if request.url?.path == "/upload/drive/v3/files" {
                XCTAssertEqual(request.queryValue("uploadType"), "resumable")
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Upload-Content-Length"), "5")
                XCTAssertEqual(request.jsonBody["name"] as? String, "hello.txt")
                return StubURLProtocol.Reply(headers: ["Location": "https://upload.example/session"])
            }
            return .json(["files": []])
        }

        let uploaded = try await provider.upload(source, named: "hello.txt", into: url("/")) { _ in }

        XCTAssertEqual(uploaded, url("/hello.txt", isDirectory: false))
    }

    func testQuotaErrorsAreNormalized() {
        let reply = Data(#"{"error":{"code":403,"message":"full","errors":[{"reason":"storageQuotaExceeded"}]}}"#.utf8)
        XCTAssertEqual(GoogleDriveProvider.error(from: reply, statusCode: 403) as? CloudError, .quotaExceeded)
        XCTAssertEqual(GoogleDriveProvider.error(from: Data(), statusCode: 404) as? FileProviderError, .itemUnavailable)
    }
}

final class BaiduNetdiskProviderTests: XCTestCase {
    private let accountID = UUID()

    private func makeProvider(handler: @escaping StubURLProtocol.Handler) throws -> (BaiduNetdiskProvider, CloudCredentialStore) {
        let store = try CloudCredentialStore.testing(accountID: accountID, service: .baiduNetdisk)
        let session = StubURLProtocol.session(handler: handler)
        let client = BaiduNetdiskProvider.makeClient(accountID: accountID, store: store, session: session)
        return (BaiduNetdiskProvider(accountID: accountID, client: client), store)
    }

    private func url(_ path: String, isDirectory: Bool = true) -> URL {
        CloudLocation(service: .baiduNetdisk, accountID: accountID, path: path).url(isDirectory: isDirectory)
    }

    private static func entry(_ id: UInt64, _ path: String, folder: Bool = false, size: Int = 0) -> [String: Any] {
        [
            "fs_id": id,
            "path": path,
            "server_filename": (path as NSString).lastPathComponent,
            "isdir": folder ? 1 : 0,
            "size": size,
            "server_mtime": 1_700_000_000
        ]
    }

    func testListsWithTheTokenAndUserAgentBaiduRequires() async throws {
        let (provider, _) = try makeProvider { request in
            XCTAssertEqual(request.queryValue("access_token"), "access-1")
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "pan.baidu.com")
            XCTAssertEqual(request.queryValue("method"), "list")
            XCTAssertEqual(request.queryValue("dir"), "/apps/PaneSpace")
            return .json(["errno": 0, "list": [
                Self.entry(1, "/apps/PaneSpace/照片", folder: true),
                Self.entry(2, "/apps/PaneSpace/a+b.txt", size: 9)
            ]])
        }

        let items = try await provider.contents(of: url("/apps/PaneSpace"), showsHiddenFiles: false)

        XCTAssertEqual(items.map(\.url), [url("/apps/PaneSpace/照片"), url("/apps/PaneSpace/a+b.txt", isDirectory: false)])
        XCTAssertEqual(items[1].fileSize, 9)
        XCTAssertEqual(items[1].modificationDate, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testErrorNumbersBecomeNormalizedErrors() async throws {
        let (provider, _) = try makeProvider { _ in .json(["errno": -9]) }

        do {
            _ = try await provider.contents(of: url("/missing"), showsHiddenFiles: false)
            XCTFail("Expected an error")
        } catch let error as FileProviderError {
            XCTAssertEqual(error, .itemUnavailable)
        }
        XCTAssertEqual(BaiduNetdiskProvider.error(forErrno: -7, message: nil) as? FileProviderError, .permissionDenied)
        XCTAssertEqual(BaiduNetdiskProvider.error(forErrno: 31034, message: nil) as? CloudError, .rateLimited)
    }

    func testRejectedTokenIsRefreshedAndTheRequestRetried() async throws {
        let (provider, store) = try makeProvider { request in
            if request.url?.host() == "openapi.baidu.com" {
                return .json(["access_token": "access-2", "refresh_token": "refresh-2", "expires_in": 2_592_000])
            }
            if request.queryValue("access_token") == "access-1" {
                return .json(["errno": -6])
            }
            return .json(["errno": 0, "list": [Self.entry(1, "/a.txt")]])
        }

        let items = try await provider.contents(of: url("/"), showsHiddenFiles: false)

        XCTAssertEqual(items.map(\.name), ["a.txt"])
        XCTAssertEqual(store.tokens(for: accountID)?.refreshToken, "refresh-2")
    }

    func testRenameFailsInsteadOfOverwriting() async throws {
        let (provider, _) = try makeProvider { request in
            XCTAssertEqual(request.queryValue("method"), "filemanager")
            XCTAssertEqual(request.queryValue("opera"), "rename")
            XCTAssertEqual(request.formValues["ondup"], "fail")
            XCTAssertEqual(request.formValues["async"], "0")
            let list = try XCTUnwrap(request.formValues["filelist"])
            let files = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(list.utf8)) as? [[String: String]])
            XCTAssertEqual(files, [["path": "/apps/x/a.txt", "newname": "b.txt"]])
            return .json(["errno": 0, "info": [["errno": 0, "path": "/apps/x/a.txt"]]])
        }

        let renamed = try await provider.rename(url("/apps/x/a.txt", isDirectory: false), to: "b.txt")

        XCTAssertEqual(renamed, url("/apps/x/b.txt", isDirectory: false))
    }

    func testUploadRunsPrecreateSlicesAndCreate() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let contents = Data(repeating: 7, count: BaiduNetdiskProvider.sliceSize + 10)
        try contents.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let digests = try BaiduNetdiskProvider.sliceDigests(of: source)
        XCTAssertEqual(digests.count, 2)

        let (provider, _) = try makeProvider { request in
            switch request.queryValue("method") {
            case "precreate":
                XCTAssertEqual(request.formValues["path"], "/apps/x/big.bin")
                XCTAssertEqual(request.formValues["rtype"], "0")
                return .json(["errno": 0, "uploadid": "U1", "block_list": [0, 1]])
            case "locateupload":
                return .json(["error_code": 0, "servers": [["server": "https://c3.pcs.example"]]])
            case "upload":
                XCTAssertEqual(request.url?.host(), "c3.pcs.example")
                XCTAssertEqual(request.queryValue("uploadid"), "U1")
                return .json(["md5": digests[Int(request.queryValue("partseq") ?? "0") ?? 0]])
            case "create":
                XCTAssertEqual(request.formValues["uploadid"], "U1")
                XCTAssertEqual(request.formValues["size"], String(contents.count))
                return .json(["errno": 0, "fs_id": 9, "path": "/apps/x/big.bin"])
            default:
                XCTFail("Unexpected request \(String(describing: request.url))")
                return .json(["errno": 2])
            }
        }

        let uploaded = try await provider.upload(source, named: "big.bin", into: url("/apps/x")) { _ in }

        XCTAssertEqual(uploaded, url("/apps/x/big.bin", isDirectory: false))
        XCTAssertEqual(StubURLProtocol.requests.filter { $0.queryValue("method") == "upload" }.count, 2)
    }
}
