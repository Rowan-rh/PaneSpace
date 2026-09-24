import Foundation
import XCTest
@testable import PaneSpaceApp

final class SidebarNavigationTests: XCTestCase {
    private let temporaryRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    @MainActor
    private func makeModel() throws -> (AppModel, [SidebarLocation], String) {
        let suiteName = "PaneSpaceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(false, forKey: "restoreLastSession")
        defaults.set(PaneLayout.single.rawValue, forKey: "defaultPaneLayout")
        let documents = temporaryRoot.appendingPathComponent("Documents", isDirectory: true)
        let downloads = temporaryRoot.appendingPathComponent("Downloads", isDirectory: true)
        for directory in [documents, downloads] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let locations = [
            SidebarLocation(id: "documents", title: "Documents", systemImage: "doc", url: documents),
            SidebarLocation(id: "downloads", title: "Downloads", systemImage: "arrow.down.circle", url: downloads),
            SidebarLocation(id: "workspace:documents", title: "Docs", systemImage: "doc", url: documents)
        ]
        return (AppModel(defaults: defaults), locations, suiteName)
    }

    @MainActor
    func testOpeningALocationNavigatesTheActivePane() throws {
        let (model, locations, suiteName) = try makeModel()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        model.openSidebarLocation(locations[1])

        XCTAssertEqual(model.activePaneModel.currentURL.standardizedFileURL, locations[1].url.standardizedFileURL)
        let historyCount = model.activePaneModel.activeTab.backHistory.count
        model.openSidebarLocation(locations[1])
        XCTAssertEqual(model.activePaneModel.activeTab.backHistory.count, historyCount)
    }

    @MainActor
    func testSelectionFollowsTheActivePaneSoTheSameLocationCanBeOpenedAgain() throws {
        let (model, locations, suiteName) = try makeModel()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        model.sidebarSelection = "documents"
        model.openSidebarLocation(locations[0])
        model.syncSidebarSelection(with: locations)
        XCTAssertEqual(model.sidebarSelection, "documents")

        model.activePaneModel.navigate(to: temporaryRoot)
        model.syncSidebarSelection(with: locations)
        XCTAssertNil(model.sidebarSelection)

        model.activePaneModel.navigate(to: locations[1].url)
        model.syncSidebarSelection(with: locations)
        XCTAssertEqual(model.sidebarSelection, "downloads")
    }

    @MainActor
    func testSyncKeepsAnEquivalentLocationTheUserChose() throws {
        let (model, locations, suiteName) = try makeModel()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        model.sidebarSelection = "workspace:documents"
        model.openSidebarLocation(locations[2])
        model.syncSidebarSelection(with: locations)

        XCTAssertEqual(model.sidebarSelection, "workspace:documents")
    }
}
