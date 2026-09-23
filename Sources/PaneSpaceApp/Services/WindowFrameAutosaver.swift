import AppKit
import SwiftUI

struct WindowFrameAutosaver: NSViewRepresentable {
    static let autosaveName = "PaneSpace.MainWindow"

    func makeNSView(context: Context) -> NSView {
        WindowTrackingView(autosaveName: Self.autosaveName)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowTrackingView: NSView {
    private let autosaveName: String
    private weak var configuredWindow: NSWindow?

    init(autosaveName: String) {
        self.autosaveName = autosaveName
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, window !== configuredWindow else { return }
        window.setFrameAutosaveName(autosaveName)
        configuredWindow = window
    }
}
