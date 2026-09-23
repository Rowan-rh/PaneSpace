import AppKit
import SwiftUI

struct PaneKeyboardMonitor: NSViewRepresentable {
    let cycle: (Bool) -> Void

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.cycle = cycle
        return view
    }

    func updateNSView(_ view: KeyCaptureView, context: Context) {
        view.cycle = cycle
    }
}

final class KeyCaptureView: NSView {
    var cycle: ((Bool) -> Void)?
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
                  event.keyCode == 48,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  !(window.firstResponder is NSTextView),
                  !(window.firstResponder is NSTextField) else { return event }
            self.cycle?(event.modifierFlags.contains(.shift))
            return nil
        }
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
