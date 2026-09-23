import CoreGraphics
import Foundation

enum PaneSlot: String, CaseIterable, Identifiable, Codable, Sendable {
    case primary
    case secondary
    case tertiary
    case quaternary

    var id: String { rawValue }
}

enum PaneLayout: String, CaseIterable, Identifiable, Codable, Sendable {
    case single
    case twoColumns
    case twoRows
    case primaryLeft
    case primaryRight
    case primaryTop
    case primaryBottom
    case threeColumns
    case threeRows
    case fourGrid
    case fourColumns
    case fourRows

    var id: String { rawValue }

    var title: String {
        switch self {
        case .single: "Single Pane"
        case .twoColumns: "Two Columns"
        case .twoRows: "Two Rows"
        case .primaryLeft: "Large Left"
        case .primaryRight: "Large Right"
        case .primaryTop: "Large Top"
        case .primaryBottom: "Large Bottom"
        case .threeColumns: "Three Columns"
        case .threeRows: "Three Rows"
        case .fourGrid: "Four Grid"
        case .fourColumns: "Four Columns"
        case .fourRows: "Four Rows"
        }
    }

    var visibleSlots: [PaneSlot] {
        Array(PaneSlot.allCases.prefix(normalizedFrames.count))
    }

    var visiblePaneCount: Int { normalizedFrames.count }
    var prefersCompactRows: Bool { visiblePaneCount > 1 }

    var normalizedFrames: [CGRect] {
        switch self {
        case .single:
            [CGRect(x: 0, y: 0, width: 1, height: 1)]
        case .twoColumns:
            [
                CGRect(x: 0, y: 0, width: 0.5, height: 1),
                CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
            ]
        case .twoRows:
            [
                CGRect(x: 0, y: 0, width: 1, height: 0.5),
                CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
            ]
        case .primaryLeft:
            [
                CGRect(x: 0, y: 0, width: 0.62, height: 1),
                CGRect(x: 0.62, y: 0, width: 0.38, height: 0.5),
                CGRect(x: 0.62, y: 0.5, width: 0.38, height: 0.5)
            ]
        case .primaryRight:
            [
                CGRect(x: 0.38, y: 0, width: 0.62, height: 1),
                CGRect(x: 0, y: 0, width: 0.38, height: 0.5),
                CGRect(x: 0, y: 0.5, width: 0.38, height: 0.5)
            ]
        case .primaryTop:
            [
                CGRect(x: 0, y: 0, width: 1, height: 0.62),
                CGRect(x: 0, y: 0.62, width: 0.5, height: 0.38),
                CGRect(x: 0.5, y: 0.62, width: 0.5, height: 0.38)
            ]
        case .primaryBottom:
            [
                CGRect(x: 0, y: 0.38, width: 1, height: 0.62),
                CGRect(x: 0, y: 0, width: 0.5, height: 0.38),
                CGRect(x: 0.5, y: 0, width: 0.5, height: 0.38)
            ]
        case .threeColumns:
            [
                CGRect(x: 0, y: 0, width: 1.0 / 3.0, height: 1),
                CGRect(x: 1.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 1),
                CGRect(x: 2.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 1)
            ]
        case .threeRows:
            [
                CGRect(x: 0, y: 0, width: 1, height: 1.0 / 3.0),
                CGRect(x: 0, y: 1.0 / 3.0, width: 1, height: 1.0 / 3.0),
                CGRect(x: 0, y: 2.0 / 3.0, width: 1, height: 1.0 / 3.0)
            ]
        case .fourGrid:
            [
                CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
                CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
                CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5),
                CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
            ]
        case .fourColumns:
            (0 ..< 4).map { CGRect(x: CGFloat($0) / 4, y: 0, width: 0.25, height: 1) }
        case .fourRows:
            (0 ..< 4).map { CGRect(x: 0, y: CGFloat($0) / 4, width: 1, height: 0.25) }
        }
    }
}
