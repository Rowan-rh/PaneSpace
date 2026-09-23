import Foundation
import XCTest
@testable import PaneSpaceApp

final class PaneSpacePreferencesTests: XCTestCase {
    func testResetRemovesEveryPaneSpacePreference() throws {
        let suiteName = "PaneSpacePreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        for key in PaneSpacePreferences.allKeys {
            defaults.set("test", forKey: key)
        }
        defaults.set("keep", forKey: "unrelatedPreference")

        PaneSpacePreferences.reset(in: defaults)

        for key in PaneSpacePreferences.allKeys {
            XCTAssertNil(defaults.object(forKey: key), key)
        }
        XCTAssertEqual(defaults.string(forKey: "unrelatedPreference"), "keep")
    }
}
