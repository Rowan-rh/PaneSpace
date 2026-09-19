import SwiftUI

@main
struct PaneSpaceApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .frame(minWidth: 940, minHeight: 580)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    appModel.activePaneModel.addTab()
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("New Folder") {
                    appModel.requestNewFolder()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()

                Button(appModel.isDualPane ? "Close Second Pane" : "Open Second Pane") {
                    appModel.isDualPane.toggle()
                }
                .keyboardShortcut("d", modifiers: [.command, .option])
            }

            CommandMenu("Navigate") {
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
        }
    }
}
