import Foundation
import XCTest
@testable import PaneSpaceApp

final class AppSessionTests: XCTestCase {
    @MainActor
    func testRestoresPaneTabsHistoryAndPresentationState() throws {
        let firstID = UUID()
        let secondID = UUID()
        let root = URL(fileURLWithPath: "/session-root", isDirectory: true)
        let child = root.appendingPathComponent("Child", isDirectory: true)
        let session = AppSession(
            paneLayout: .threeColumns,
            activePane: .tertiary,
            panes: [
                .primary: BrowserPaneSession(
                    tabs: [
                        BrowserTab(id: firstID, url: root),
                        BrowserTab(
                            id: secondID,
                            url: child,
                            backHistory: [root],
                            forwardHistory: [child.appendingPathComponent("Next")]
                        )
                    ],
                    activeTabID: secondID,
                    viewMode: .columns,
                    showsHiddenFiles: true,
                    sort: .date,
                    sortAscending: false
                )
            ]
        )
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(try JSONEncoder().encode(session), forKey: "appSession")
        defaults.set(true, forKey: "restoreLastSession")

        let model = AppModel(defaults: defaults)

        XCTAssertEqual(model.paneLayout, .threeColumns)
        XCTAssertEqual(model.activePane, .tertiary)
        XCTAssertEqual(model.primaryPane.tabs.count, 2)
        XCTAssertEqual(model.primaryPane.activeTabID, secondID)
        XCTAssertEqual(model.primaryPane.activeTab.backHistory, [root])
        XCTAssertEqual(model.primaryPane.activeTab.forwardHistory, [child.appendingPathComponent("Next")])
        XCTAssertEqual(model.primaryPane.viewMode, .columns)
        XCTAssertTrue(model.primaryPane.showsHiddenFiles)
        XCTAssertEqual(model.primaryPane.sort, .date)
        XCTAssertFalse(model.primaryPane.sortAscending)
    }

    @MainActor
    func testSaveSessionRoundTripsCurrentPaneState() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(defaults: defaults)
        model.paneLayout = .fourGrid
        model.activePane = .quaternary
        model.primaryPane.addTab(url: URL(fileURLWithPath: "/tmp", isDirectory: true))
        model.primaryPane.setSort(.size)

        model.saveSession()

        let data = try XCTUnwrap(defaults.data(forKey: "appSession"))
        let session = try JSONDecoder().decode(AppSession.self, from: data)
        XCTAssertEqual(session.version, AppSession.currentVersion)
        XCTAssertEqual(session.paneLayout, .fourGrid)
        XCTAssertEqual(session.activePane, .quaternary)
        XCTAssertEqual(session.panes[.primary]?.tabs.count, 2)
        XCTAssertEqual(session.panes[.primary]?.sort, .size)
    }

    @MainActor
    func testRestoreDisabledUsesDefaultLayout() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let storedSession = AppSession(
            paneLayout: .fourRows,
            activePane: .quaternary,
            panes: [:]
        )
        defaults.set(try JSONEncoder().encode(storedSession), forKey: "appSession")
        defaults.set(false, forKey: "restoreLastSession")
        defaults.set(PaneLayout.primaryLeft.rawValue, forKey: "defaultPaneLayout")
        defaults.set(PaneLayout.fourColumns.rawValue, forKey: "currentPaneLayout")

        let model = AppModel(defaults: defaults)

        XCTAssertEqual(model.paneLayout, .primaryLeft)
        XCTAssertEqual(model.activePane, .primary)
    }

    @MainActor
    func testUnsupportedSessionVersionFallsBackToStartupPreferences() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let unsupportedSession = AppSession(
            version: AppSession.currentVersion + 1,
            paneLayout: .fourRows,
            activePane: .quaternary,
            panes: [:]
        )
        defaults.set(try JSONEncoder().encode(unsupportedSession), forKey: "appSession")
        defaults.set(true, forKey: "restoreLastSession")
        defaults.set(PaneLayout.twoRows.rawValue, forKey: "defaultPaneLayout")

        let model = AppModel(defaults: defaults)

        XCTAssertEqual(model.paneLayout, .twoRows)
        XCTAssertEqual(model.activePane, .primary)
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "PaneSpaceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
