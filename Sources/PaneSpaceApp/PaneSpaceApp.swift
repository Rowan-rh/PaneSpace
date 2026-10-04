import AppKit
import SwiftUI

@MainActor
final class PaneSpaceApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The stage-2 -> Sparkle preference migration is NOT done here. It has to
        // run before `UpdateModel` reads `SUEnableAutomaticChecks`, and this
        // callback is too late for that: `@StateObject` builds the model during
        // `PaneSpaceApp`'s initialisation, which happens before the application
        // finishes launching. It therefore runs at the top of `UpdateModel.init`,
        // which is the only place guaranteed to be first.
        //
        // The updater controller itself is deliberately not created here either.
        // `UpdateModel` owns it (see its initialiser), because a second
        // `SPUStandardUpdaterController` would be a second `SPUUpdater` running
        // its own update cycle against the same feed: two schedulers writing
        // `SULastCheckTime`, two download attempts, and a delegate with no model
        // attached competing over presentation. What ADR 0011 §4 actually
        // requires is satisfied where it is created — on the main actor, with
        // both delegates passed at init because the controller has no setter for
        // them, and held in a stored property so Sparkle's weak references stay
        // valid.
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
                .task {
                    // The update schedule starts with the first window. It checks immediately and
                    // then once a day, and does nothing when automatic checks are off or the build
                    // carries no version to compare.
                    appModel.updates.start()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1_180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Pane") {
                    appModel.addPane()
                }
                .disabled(!appModel.canAddPane)
                .keyboardShortcut("n", modifiers: .command)

                Button("New Tab") {
                    appModel.activePaneModel.addTab()
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("New Folder") {
                    appModel.requestNewFolder()
                }
                .disabled(appModel.activePaneModel.isPerformingOperation)
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("Rename…") {
                    appModel.activePaneModel.requestRename(appModel.activePaneModel.selectedItems)
                }
                .disabled(
                    appModel.activePaneModel.selectedItems.isEmpty ||
                        appModel.activePaneModel.isPerformingOperation
                )
            }

            CommandGroup(replacing: .undoRedo) {
                Button {
                    // Text fields keep their own undo; file operations are undone elsewhere.
                    if NSApp.keyWindow?.firstResponder is NSText {
                        NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                    } else {
                        appModel.undoLatestOperation()
                    }
                } label: {
                    if let record = appModel.latestUndoableOperation {
                        Text(L10n.format("Undo %@", record.title))
                    } else {
                        Text("Undo")
                    }
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(appModel.isUndoing)

                Button("Redo") {
                    NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
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
                Button("Search in Pane") { appModel.requestSearchFocus() }
                    .keyboardShortcut("f", modifiers: .command)
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

                Divider()

                Button("Operation History…") {
                    appModel.isShowingOperationHistory = true
                }
                .keyboardShortcut("h", modifiers: [.command, .control])
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    appModel.isShowingSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)

                // Placed after "About PaneSpace", which the app-information group owns. A build with
                // no version to compare against has no honest answer to a check, so the command is
                // disabled rather than failing silently.
                Divider()

                Button(L10n.text("Check for Updates…")) {
                    Task { await UpdateCheckAction.runAndAlert(appModel.updates) }
                }
                .disabled(!appModel.updates.isSupported || appModel.updates.isChecking)
            }
        }
    }
}
