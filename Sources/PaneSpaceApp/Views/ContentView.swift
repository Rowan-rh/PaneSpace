import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var newFolderName = "New Folder"

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 170, ideal: 205, max: 260)
        } detail: {
            Group {
                if appModel.isDualPane {
                    HSplitView {
                        BrowserPaneView(model: appModel.primaryPane, slot: .primary)
                        BrowserPaneView(model: appModel.secondaryPane, slot: .secondary)
                    }
                } else {
                    BrowserPaneView(model: appModel.primaryPane, slot: .primary)
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    appModel.activePaneModel.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!appModel.activePaneModel.canGoBack)
                .help("Back")

                Button {
                    appModel.activePaneModel.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!appModel.activePaneModel.canGoForward)
                .help("Forward")

                Button {
                    appModel.activePaneModel.goUp()
                } label: {
                    Image(systemName: "arrow.up")
                }
                .help("Parent Folder")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    appModel.requestNewFolder()
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .help("New Folder")

                Button {
                    appModel.activePaneModel.addTab()
                } label: {
                    Image(systemName: "plus.square.on.square")
                }
                .help("New Tab")

                Button {
                    appModel.isDualPane.toggle()
                    if !appModel.isDualPane {
                        appModel.activePane = .primary
                    }
                } label: {
                    Image(systemName: appModel.isDualPane ? "rectangle.split.2x1.fill" : "rectangle")
                }
                .help("Toggle Dual Pane")
            }
        }
        .sheet(isPresented: $appModel.isCreatingFolder) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Create a folder")
                    .font(.headline)
                TextField("Folder name", text: $newFolderName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Cancel") {
                        appModel.isCreatingFolder = false
                    }
                    Button("Create") {
                        appModel.activePaneModel.createFolder(named: newFolderName)
                        appModel.isCreatingFolder = false
                        newFolderName = "New Folder"
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 360)
        }
    }
}
