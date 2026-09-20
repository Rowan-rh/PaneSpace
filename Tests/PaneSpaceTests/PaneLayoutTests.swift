import XCTest
@testable import PaneSpaceApp

final class PaneLayoutTests: XCTestCase {
    func testEveryLayoutUsesOneToFourPanes() {
        for layout in PaneLayout.allCases {
            XCTAssertFalse(layout.normalizedFrames.isEmpty, layout.title)
            XCTAssertLessThanOrEqual(layout.normalizedFrames.count, PaneSlot.allCases.count, layout.title)
            XCTAssertEqual(layout.visibleSlots.count, layout.normalizedFrames.count, layout.title)
        }
    }

    func testLayoutFramesRemainInsideTheWorkspace() {
        for layout in PaneLayout.allCases {
            for frame in layout.normalizedFrames {
                XCTAssertGreaterThanOrEqual(frame.minX, 0, layout.title)
                XCTAssertGreaterThanOrEqual(frame.minY, 0, layout.title)
                XCTAssertLessThanOrEqual(frame.maxX, 1.000_001, layout.title)
                XCTAssertLessThanOrEqual(frame.maxY, 1.000_001, layout.title)
                XCTAssertGreaterThan(frame.width, 0, layout.title)
                XCTAssertGreaterThan(frame.height, 0, layout.title)
            }
        }
    }

    func testCanonicalLayoutPaneCounts() {
        XCTAssertEqual(PaneLayout.single.visiblePaneCount, 1)
        XCTAssertEqual(PaneLayout.twoColumns.visiblePaneCount, 2)
        XCTAssertEqual(PaneLayout.primaryLeft.visiblePaneCount, 3)
        XCTAssertEqual(PaneLayout.fourGrid.visiblePaneCount, 4)
    }
}
