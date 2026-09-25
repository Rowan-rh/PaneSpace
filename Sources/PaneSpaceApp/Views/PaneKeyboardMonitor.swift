import AppKit
import SwiftUI

enum PaneKeyCommand {
    case cycle(backward: Bool)
    case copy
    case paste
}

/// Handles pane shortcuts at the window level so they work whichever pane control has focus,
/// including none after navigation or in an empty folder. Text fields keep these keys.
struct PaneKeyboardMonitor: NSViewRepresentable {
    /// Returns false when the command did nothing, so the key continues to the menu bar.
    let handle: (PaneKeyCommand) -> Bool

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.handle = handle
        return view
    }

    func updateNSView(_ view: KeyCaptureView, context: Context) {
        view.handle = handle
    }
}

final class KeyCaptureView: NSView {
    var handle: ((PaneKeyCommand) -> Bool)?
    nonisolated(unsafe) private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window,
                  event.window === window,
                  window.attachedSheet == nil,
                  !(window.firstResponder is NSTextView),
                  !(window.firstResponder is NSTextField),
                  let command = Self.command(for: event),
                  self.handle?(command) == true else { return event }
            return nil
        }
    }

    private static func command(for event: NSEvent) -> PaneKeyCommand? {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.keyCode == 48, modifiers.subtracting(.shift).isEmpty {
            return .cycle(backward: modifiers.contains(.shift))
        }
        guard modifiers == .command else { return nil }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "c": return .copy
        case "v": return .paste
        default: return nil
        }
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
