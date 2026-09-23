import AppKit
import SwiftUI

final class PaneSpaceApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct PaneSpaceApp: App {
    @NSApplicationDelegateAdaptor(PaneSpaceApplicationDelegate.self) private var applicationDelegate
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .frame(minWidth: 1_000, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1_180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    appModel.activePaneModel.addTab()
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("New Folder") {
                    appModel.requestNewFolder()
                }
                .disabled(appModel.activePaneModel.isPerformingOperation)
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .saveItem) {
                Button {
                    if appModel.canCloseActiveTabOrPane {
                        appModel.closeActiveTabOrPane()
                    } else {
                        NSApp.keyWindow?.performClose(nil)
                    }
                } label: {
                    Text(L10n.text(appModel.canCloseActiveTabOrPane ? "Close Tab or Pane" : "Close Window"))
                }
                .keyboardShortcut("w", modifiers: .command)

                if appModel.canCloseActiveTabOrPane {
                    Button("Close Window") {
                        NSApp.keyWindow?.performClose(nil)
                    }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
                }

                Divider()

                Button {
                    appModel.toggleSecondPane()
                } label: {
                    Text(L10n.text(appModel.paneLayout == .single ? "Open Second Pane" : "Close Extra Panes"))
                }
                .keyboardShortcut("d", modifiers: [.command, .option])
            }

            CommandMenu("Navigate") {
                Button("Go to Folder") { appModel.requestLocationEditing() }
                    .keyboardShortcut("l", modifiers: .command)
                Button("Back") { appModel.activePaneModel.goBack() }
                    .keyboardShortcut("[", modifiers: .command)
                Button("Forward") { appModel.activePaneModel.goForward() }
                    .keyboardShortcut("]", modifiers: .command)
                Button("Up") { appModel.activePaneModel.goUp() }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                Button("Refresh") { appModel.activePaneModel.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Quick Look") { appModel.activePaneModel.previewSelection() }
                    .keyboardShortcut(.space, modifiers: [])
            }

            CommandMenu("Transfer") {
                Button("Copy to Next Pane") {
                    if let destination = appModel.nextVisiblePane(after: appModel.activePane) {
                        appModel.transferSelection(from: appModel.activePane, to: destination, kind: .copy)
                    }
                }
                .disabled(!appModel.canTransferSelection)
                .keyboardShortcut("c", modifiers: [.command, .control])

                Button("Move to Next Pane") {
                    if let destination = appModel.nextVisiblePane(after: appModel.activePane) {
                        appModel.transferSelection(from: appModel.activePane, to: destination, kind: .move)
                    }
                }
                .disabled(!appModel.canTransferSelection)
                .keyboardShortcut("m", modifiers: [.command, .control])
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    appModel.isShowingSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
