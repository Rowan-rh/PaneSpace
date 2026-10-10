import AppKit
import SwiftUI

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general = "General"
    case appearance = "Appearance"
    case behaviors = "Behaviors"
    case addressBar = "Address Bar"
    case sidebar = "Sidebar"
    case tabs = "Tabs"
    case fileList = "File List"
    case search = "Search"
    case contextMenu = "Context Menu"
    case hotkeys = "Hotkeys"
    case quickLaunch = "Quick Launch"
    case permissions = "Permissions"
    case extensions = "Extensions"
    case advanced = "Advanced"
    case updates = "Updates"
    case about = "About"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .behaviors: "cursorarrow.click.2"
        case .addressBar: "location"
        case .sidebar: "sidebar.left"
        case .tabs: "rectangle.stack"
        case .fileList: "list.bullet.rectangle"
        case .search: "magnifyingglass"
        case .contextMenu: "contextualmenu.and.cursorarrow"
        case .hotkeys: "keyboard"
        case .quickLaunch: "bolt"
        case .permissions: "lock.shield"
        case .extensions: "puzzlepiece.extension"
        case .advanced: "slider.horizontal.3"
        case .updates: "arrow.down.circle"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selection: SettingsCategory = .general

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Label("Back to PaneSpace", systemImage: "chevron.backward")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)

                Spacer()

                Text("Settings")
                    .font(.headline)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close Settings")
                .accessibilityLabel("Close Settings")
            }
            .padding(.horizontal, 16)
            .frame(height: 46)

            Divider()

            HStack(spacing: 0) {
                List(SettingsCategory.allCases, selection: $selection) { category in
                    Label(L10n.text(category.rawValue), systemImage: category.systemImage)
                        .tag(category)
                }
                .listStyle(.sidebar)
                .frame(width: 188)

                Divider()

                ScrollView {
                    detail
                        .frame(maxWidth: 620, alignment: .topLeading)
                        .padding(28)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .general: GeneralSettingsPage()
        case .appearance: AppearanceSettingsPage()
        case .behaviors: BehaviorSettingsPage()
        case .addressBar: AddressBarSettingsPage()
        case .sidebar: SidebarSettingsPage()
        case .tabs: TabSettingsPage()
        case .fileList: FileListSettingsPage()
        case .search: SearchSettingsPage()
        case .contextMenu: ContextMenuSettingsPage()
        case .hotkeys: HotkeySettingsPage()
        case .quickLaunch: QuickLaunchSettingsPage()
        case .permissions: PermissionSettingsPage()
        case .extensions: ExtensionSettingsPage()
        case .advanced: AdvancedSettingsPage()
        case .updates: UpdatesSettingsPage()
        case .about: AboutSettingsPage()
        }
    }
}

private struct GeneralSettingsPage: View {
    @AppStorage("startupLocation") private var startupLocation = "home"
    @AppStorage("restoreLastSession") private var restoreLastSession = true
    @AppStorage("openWorkspaceInTab") private var openWorkspaceInTab = true
    @AppStorage("keepRecentLocations") private var keepRecentLocations = true
    @AppStorage("confirmQuit") private var confirmQuit = false
    @AppStorage("showStatusBar") private var showStatusBar = true
    @AppStorage("defaultPaneLayout") private var defaultPaneLayout = PaneLayout.twoColumns.rawValue

    var body: some View {
        SettingsPage(title: "General", subtitle: "Startup, workspace, and window behavior.") {
            SettingsGroup(title: "Startup") {
                SettingRow(
                    "Startup location",
                    detail: "Used when no restorable workspace is available."
                ) {
                    Picker("", selection: $startupLocation) {
                        Text("Home").tag("home")
                        Text("Downloads").tag("downloads")
                        Text("Last Location").tag("last")
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }

                SettingRow("Default pane layout") {
                    Picker("", selection: $defaultPaneLayout) {
                        ForEach(PaneLayout.allCases) { layout in
                            Text(L10n.text(layout.title)).tag(layout.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }

                SettingsToggle("Restore the previous session", isOn: $restoreLastSession)
                SettingsToggle("Keep recent locations and files", isOn: $keepRecentLocations, planned: true)
            }

            SettingsGroup(title: "Windows and Workspaces") {
                SettingsToggle("Open workspaces in tabs", isOn: $openWorkspaceInTab, planned: true)
                SettingsToggle("Show the bottom status bar", isOn: $showStatusBar)
                SettingsToggle("Ask before quitting", isOn: $confirmQuit, planned: true)
            }
        }
    }
}

private struct AppearanceSettingsPage: View {
    @AppStorage("accentColor") private var accentColor = "indigo"
    @AppStorage("themeIntensity") private var themeIntensity = 0.12
    @AppStorage("sidebarWidth") private var sidebarWidth = 196.0
    @AppStorage("rowDensity") private var rowDensity = "comfortable"
    @AppStorage("pinnedTabStyle") private var pinnedTabStyle = "iconAndTitle"
    @AppStorage("paneCloseButton") private var paneCloseButton = "right"

    var body: some View {
        SettingsPage(title: "Appearance", subtitle: "Tune the density and color of the workspace.") {
            SettingsGroup(title: "Theme") {
                SettingRow("Accent color") {
                    Picker("", selection: $accentColor) {
                        Text("Indigo").tag("indigo")
                        Text("Blue").tag("blue")
                        Text("Teal").tag("teal")
                        Text("Green").tag("green")
                        Text("Orange").tag("orange")
                        Text("Pink").tag("pink")
                        Text("Purple").tag("purple")
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }

                SettingRow("Theme intensity", detail: "Controls the active-pane tint.") {
                    Slider(value: $themeIntensity, in: 0 ... 1)
                        .frame(width: 180)
                }
            }

            SettingsGroup(title: "Sizing") {
                SettingRow("Sidebar width", detail: "The default is 196 points.") {
                    HStack {
                        Slider(value: $sidebarWidth, in: 164 ... 286, step: 2)
                        Text("\(Int(sidebarWidth))")
                            .monospacedDigit()
                            .frame(width: 34, alignment: .trailing)
                    }
                    .frame(width: 210)
                }

                SettingRow("File row density") {
                    Picker("", selection: $rowDensity) {
                        Text("Compact").tag("compact")
                        Text("Comfortable").tag("comfortable")
                        Text("Spacious").tag("spacious")
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
            }

            SettingsGroup(title: "Tabs and Panes") {
                SettingRow("Pinned tab style") {
                    Picker("", selection: $pinnedTabStyle) {
                        Text("Icon Only").tag("iconOnly")
                        Text("Icon and Title").tag("iconAndTitle")
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }

                SettingRow("Pane close button") {
                    Picker("", selection: $paneCloseButton) {
                        Text("Left").tag("left")
                        Text("Right").tag("right")
                        Text("Hidden").tag("hidden")
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
            }
        }
    }
}

private struct BehaviorSettingsPage: View {
    @AppStorage("keyResponse") private var keyResponse = "select"
    @AppStorage("blankDoubleClickAction") private var blankDoubleClickAction = "up"
    @AppStorage("openFoldersInNewTab") private var openFoldersInNewTab = false
    @AppStorage("confirmDragAndDrop") private var confirmDragAndDrop = false
    @AppStorage("showParentFolderEntry") private var showParentFolderEntry = false
    @AppStorage("expandPackages") private var expandPackages = false

    var body: some View {
        SettingsPage(title: "Behaviors", subtitle: "Choose how browsing and file interactions respond.") {
            SettingsGroup(title: "Keyboard and Mouse") {
                SettingRow("Typing in a file list", planned: true) {
                    Picker("", selection: $keyResponse) {
                        Text("Select").tag("select")
                        Text("Filter").tag("filter")
                        Text("Highlight").tag("highlight")
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }

                SettingRow("Double-click empty space", planned: true) {
                    Picker("", selection: $blankDoubleClickAction) {
                        Text("Go Up").tag("up")
                        Text("Go Back").tag("back")
                        Text("Do Nothing").tag("none")
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }

                SettingsToggle("Open folders in a new tab", isOn: $openFoldersInNewTab, planned: true)
                SettingsToggle("Confirm drag and drop operations", isOn: $confirmDragAndDrop, planned: true)
            }

            SettingsGroup(title: "Folder Browsing") {
                SettingsToggle("Show parent folder entry", isOn: $showParentFolderEntry, planned: true)
                SettingsToggle("Expand package contents", isOn: $expandPackages, planned: true)
            }
        }
    }
}

private struct AddressBarSettingsPage: View {
    @AppStorage("addressBarPosition") private var addressBarPosition = "top"
    @AppStorage("showPaneNavigation") private var showPaneNavigation = true
    @AppStorage("showAddressReload") private var showAddressReload = true
    @AppStorage("showAddressActions") private var showAddressActions = true
    @AppStorage("showToolbarNavigation") private var showToolbarNavigation = true
    @AppStorage("expandFolderMenus") private var expandFolderMenus = true

    var body: some View {
        SettingsPage(title: "Address Bar", subtitle: "Control per-pane navigation and path presentation.") {
            SettingsGroup(title: "Placement") {
                SettingRow("Address bar position") {
                    Picker("", selection: $addressBarPosition) {
                        Text("Top").tag("top")
                        Text("Bottom").tag("bottom")
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
            }

            SettingsGroup(title: "Visible Controls") {
                SettingsToggle("Back and forward in each pane", isOn: $showPaneNavigation)
                SettingsToggle("Back and forward in the toolbar", isOn: $showToolbarNavigation)
                SettingsToggle("Reload button", isOn: $showAddressReload)
                SettingsToggle("Action menu", isOn: $showAddressActions)
                SettingsToggle("Expand folder contents from path segments", isOn: $expandFolderMenus, planned: true)
            }
        }
    }
}

private struct SidebarSettingsPage: View {
    @AppStorage("showWorkspaceGroup") private var showWorkspaceGroup = true
    @AppStorage("showVolumesGroup") private var showVolumesGroup = true
    @AppStorage("showTagsGroup") private var showTagsGroup = true
    @AppStorage("showVolumeFreeSpace") private var showVolumeFreeSpace = false
    @AppStorage("sidebarPosition") private var sidebarPosition = "left"

    var body: some View {
        SettingsPage(title: "Sidebar", subtitle: "Choose the groups shown next to the workspace.") {
            SettingsGroup(title: "Placement") {
                SettingRow(
                    "Default position",
                    detail: "Right placement is reserved for a later window model.",
                    planned: true
                ) {
                    Picker("", selection: $sidebarPosition) {
                        Text("Left").tag("left")
                        Text("Right — Planned").tag("right")
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
            }

            SettingsGroup(title: "Groups") {
                SettingsToggle("Workspaces", isOn: $showWorkspaceGroup)
                SettingsToggle("Mounted volumes", isOn: $showVolumesGroup)
                SettingsToggle("Tags", isOn: $showTagsGroup)
                SettingsToggle("Show volume free space", isOn: $showVolumeFreeSpace, planned: true)
            }

            WorkspaceSettingsGroup()
        }
    }
}

private struct TabSettingsPage: View {
    @AppStorage("newTabPosition") private var newTabPosition = "afterCurrent"
    @AppStorage("reuseEmptyTabs") private var reuseEmptyTabs = true
    @AppStorage("doubleClickClosesTab") private var doubleClickClosesTab = false
    @AppStorage("restoreTabs") private var restoreTabs = true

    var body: some View {
        SettingsPage(title: "Tabs", subtitle: "Configure tab creation and restoration.") {
            SettingsGroup(title: "New Tabs") {
                SettingRow("Insert new tabs", planned: true) {
                    Picker("", selection: $newTabPosition) {
                        Text("After Current").tag("afterCurrent")
                        Text("At End").tag("end")
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                SettingsToggle("Reuse empty tabs", isOn: $reuseEmptyTabs, planned: true)
            }

            SettingsGroup(title: "Closing and Restore") {
                SettingsToggle("Double-click a tab to close it", isOn: $doubleClickClosesTab, planned: true)
                SettingsToggle("Restore tabs when reopening", isOn: $restoreTabs, planned: true)
            }
        }
    }
}

private struct FileListSettingsPage: View {
    @AppStorage("defaultViewMode") private var defaultViewMode = "list"
    @AppStorage("rowDensity") private var rowDensity = "comfortable"
    @AppStorage("alternateRowBackgrounds") private var alternateRowBackgrounds = false
    @AppStorage("showFileExtensions") private var showFileExtensions = true
    @AppStorage("calculateFolderSizes") private var calculateFolderSizes = false
    @AppStorage("iconSize") private var iconSize = 32.0

    var body: some View {
        SettingsPage(title: "File List", subtitle: "Defaults shared by new folders and workspaces.") {
            SettingsGroup(title: "Presentation") {
                SettingRow("Default view") {
                    Picker("", selection: $defaultViewMode) {
                        Text("List").tag("list")
                        Text("Icons — Planned").tag("icons").disabled(true)
                        Text("Columns").tag("columns")
                        Text("Gallery — Planned").tag("gallery").disabled(true)
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }

                SettingRow(
                    "Icon size",
                    detail: "Used by the planned icon and gallery views.",
                    planned: true
                ) {
                    Slider(value: $iconSize, in: 16 ... 96, step: 4)
                        .frame(width: 180)
                }

                SettingRow("Row density") {
                    Picker("", selection: $rowDensity) {
                        Text("Compact").tag("compact")
                        Text("Comfortable").tag("comfortable")
                        Text("Spacious").tag("spacious")
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
            }

            SettingsGroup(title: "Metadata") {
                SettingsToggle("Alternate row backgrounds", isOn: $alternateRowBackgrounds)
                SettingsToggle("Show file extensions", isOn: $showFileExtensions, planned: true)
                SettingsToggle("Calculate folder sizes", isOn: $calculateFolderSizes, planned: true)
            }
        }
    }
}

private struct SearchSettingsPage: View {
    @AppStorage("searchScope") private var searchScope = "current"
    @AppStorage("searchContents") private var searchContents = false
    @AppStorage("searchHiddenItems") private var searchHiddenItems = false
    @AppStorage("searchWhileTyping") private var searchWhileTyping = true

    var body: some View {
        SettingsPage(title: "Search", subtitle: "Set defaults for pane filtering and indexed search.") {
            SettingsGroup(title: "Scope") {
                SettingRow("Default scope", planned: true) {
                    Picker("", selection: $searchScope) {
                        Text("Current Folder").tag("current")
                        Text("Subfolders — Planned").tag("recursive")
                        Text("This Mac — Planned").tag("mac")
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }
                SettingsToggle("Filter while typing", isOn: $searchWhileTyping, planned: true)
                SettingsToggle("Search file contents", isOn: $searchContents, planned: true)
                SettingsToggle("Include hidden items", isOn: $searchHiddenItems, planned: true)
            }
        }
    }
}

private struct ContextMenuSettingsPage: View {
    @AppStorage("contextQuickLook") private var contextQuickLook = true
    @AppStorage("contextShowFinder") private var contextShowFinder = true
    @AppStorage("contextRename") private var contextRename = true
    @AppStorage("contextTrash") private var contextTrash = true
    @AppStorage("contextCopyPath") private var contextCopyPath = false
    @AppStorage("contextServices") private var contextServices = false

    var body: some View {
        SettingsPage(title: "Context Menu", subtitle: "Choose the commands shown for files and folders.") {
            SettingsGroup(title: "Built-in Items") {
                SettingsToggle("Quick Look", isOn: $contextQuickLook, planned: true)
                SettingsToggle("Show in Finder", isOn: $contextShowFinder, planned: true)
                SettingsToggle("Rename", isOn: $contextRename, planned: true)
                SettingsToggle("Move to Trash", isOn: $contextTrash, planned: true)
                SettingsToggle("Copy Path", isOn: $contextCopyPath, planned: true)
                SettingsToggle("macOS Services", isOn: $contextServices, planned: true)
            }
        }
    }
}

private struct HotkeySettingsPage: View {
    var body: some View {
        SettingsPage(title: "Hotkeys", subtitle: "Current shortcuts are fixed; editing is planned.") {
            SettingsGroup(title: "Navigation") {
                HotkeyRow(title: "Back", shortcut: "⌘[")
                HotkeyRow(title: "Forward", shortcut: "⌘]")
                HotkeyRow(title: "Parent Folder", shortcut: "⌘↑")
                HotkeyRow(title: "Refresh", shortcut: "⌘R")
            }

            SettingsGroup(title: "Tabs and Panes") {
                HotkeyRow(title: "Search in Pane", shortcut: "⌘F")
                HotkeyRow(title: "New Tab", shortcut: "⌘T")
                HotkeyRow(title: "New Pane", shortcut: "⌘N")
                HotkeyRow(title: "Toggle Second Pane", shortcut: "⌥⌘D")
                HotkeyRow(title: "Quick Look", shortcut: "Space")
                HotkeyRow(title: "New Folder", shortcut: "⇧⌘N")
            }

            PlannedCallout(text: "Custom shortcut recording and conflict detection are planned.")
        }
    }
}

private struct QuickLaunchSettingsPage: View {
    @AppStorage("preferredTerminal") private var preferredTerminal = "Terminal"
    @AppStorage("preferredEditor") private var preferredEditor = "Visual Studio Code"

    var body: some View {
        SettingsPage(title: "Quick Launch", subtitle: "Prepare external tools for the active folder.") {
            SettingsGroup(title: "Default Applications") {
                SettingRow("Terminal", planned: true) {
                    Picker("", selection: $preferredTerminal) {
                        Text("Terminal").tag("Terminal")
                        Text("iTerm").tag("iTerm")
                        Text("Warp").tag("Warp")
                        Text("Other…").tag("Other")
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }

                SettingRow("Code editor", planned: true) {
                    Picker("", selection: $preferredEditor) {
                        Text("Visual Studio Code").tag("Visual Studio Code")
                        Text("Xcode").tag("Xcode")
                        Text("Other…").tag("Other")
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }
            }

            PlannedCallout(text: "Application discovery, custom arguments, and variable expansion are planned.")
        }
    }
}

private struct PermissionSettingsPage: View {
    var body: some View {
        SettingsPage(title: "Permissions", subtitle: "Review macOS access required by file-management features.") {
            SettingsGroup(title: "System Access") {
                PermissionRow(
                    title: "Full Disk Access",
                    detail: "Required to browse protected folders selected by the user.",
                    systemImage: "externaldrive.badge.checkmark",
                    action: openFullDiskAccess
                )
                PermissionRow(
                    title: "Files and Folders",
                    detail: "Managed by macOS when PaneSpace first opens protected locations.",
                    systemImage: "folder.badge.gearshape",
                    action: openPrivacySettings
                )
                PermissionRow(
                    title: "Automation",
                    detail: "Reserved for terminal, editor, and workflow integrations.",
                    systemImage: "applescript",
                    action: openAutomationSettings
                )
            }
        }
    }

    private func openFullDiskAccess() {
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    }

    private func openPrivacySettings() {
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")
    }

    private func openAutomationSettings() {
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
    }

    private func openSettings(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct ExtensionSettingsPage: View {
    var body: some View {
        SettingsPage(title: "Extensions", subtitle: "Optional modules planned after the local file-operation engine.") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ExtensionCard(title: "Server Connections", detail: "SFTP, SMB, and WebDAV providers.", systemImage: "network")
                ExtensionCard(title: "Stash Shelf", detail: "A temporary shelf for cross-pane workflows.", systemImage: "tray.full")
                ExtensionCard(title: "Batch Rename", detail: "Rename several selected items with a live preview.", systemImage: "character.cursor.ibeam", planned: false)
                ExtensionCard(title: "Archive Browser", detail: "Browse and extract archives as folders.", systemImage: "archivebox")
                ExtensionCard(title: "Finder Extension", detail: "Quick launch and reveal actions.", systemImage: "finder")
                ExtensionCard(title: "Folder Sync", detail: "Compare and synchronize two locations.", systemImage: "arrow.triangle.2.circlepath")
            }
        }
    }
}

private struct AdvancedSettingsPage: View {
    @EnvironmentObject private var appModel: AppModel
    @AppStorage("diagnosticLogging") private var diagnosticLogging = false
    @State private var confirmsReset = false

    var body: some View {
        SettingsPage(title: "Advanced", subtitle: "Development, diagnostics, and reset controls.") {
            // The beta switch used to live here as a planned item. It works now and is on the
            // Updates page, next to the other two switches that decide which updates arrive.
            SettingsGroup(title: "Diagnostics") {
                SettingsToggle("Diagnostic logging", isOn: $diagnosticLogging, planned: true)
            }

            SettingsGroup(title: "Defaults") {
                SettingRow("Restore all settings", detail: "Returns PaneSpace preferences to their initial values.") {
                    Button("Restore Defaults…", role: .destructive) {
                        confirmsReset = true
                    }
                }
            }
        }
        .confirmationDialog("Restore all PaneSpace settings?", isPresented: $confirmsReset) {
            Button("Restore Defaults", role: .destructive) {
                resetDefaults()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Open windows keep their current folders, but visual and behavior preferences return to defaults.")
        }
    }

    private func resetDefaults() {
        PaneSpacePreferences.reset()
        appModel.workspaceShortcuts.reload()
    }
}

private struct UpdatesSettingsPage: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var feedback: UpdateCheckFeedback?

    private var updates: UpdateModel { appModel.updates }

    var body: some View {
        SettingsPage(
            title: "Updates",
            subtitle: "Choose when PaneSpace looks for a new version, and check right now."
        ) {
            SettingsGroup(title: "Automatic Checks") {
                SettingsToggle("Automatically check for updates", isOn: automaticChecks)
                SettingsToggle(
                    "Include beta updates",
                    isOn: betaUpdates,
                    accessibilityLabel: "Include beta updates"
                )
            }

            SettingsGroup(title: "Check Now") {
                SettingRow("Check for Updates", detail: lastCheckDescription) {
                    Button(L10n.text("Check Now")) {
                        Task { feedback = await UpdateCheckAction.run(updates) }
                    }
                    .disabled(!updates.isSupported || updates.isChecking)
                    .frame(width: 130)
                }

                if updates.isChecking {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Checking for updates…")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }

            SettingsGroup(title: "Version") {
                SettingRow("PaneSpace version") {
                    Text(updates.currentVersionDescription)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                if !updates.isSupported {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text("This build has no version number, so it cannot be compared with releases.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }

                if let skippedVersion = updates.skippedVersion {
                    HStack(spacing: 8) {
                        Image(systemName: "forward.end.alt")
                            .foregroundStyle(.secondary)
                        Text(L10n.format("Skipped version: %@", skippedVersion))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        .alert(item: $feedback) { result in
            Alert(
                title: Text(result.title),
                message: Text(result.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // The two switches are bindings onto the model rather than onto `@AppStorage`: the model is
    // the single answer to both questions (ADR 0011 decision 3 — the automatic-checks switch is
    // stored once, in Sparkle's own key), and binding the key directly would give the window and the
    // updater two ways to write it.
    private var automaticChecks: Binding<Bool> {
        Binding(get: { updates.automaticallyChecks }, set: { updates.automaticallyChecks = $0 })
    }

    private var betaUpdates: Binding<Bool> {
        Binding(get: { updates.includesPrereleases }, set: { updates.includesPrereleases = $0 })
    }

    /// The last check's time and outcome, as one sentence.
    ///
    /// Each branch is a complete localized sentence rather than a sentence with a part dropped in:
    /// the wording of a relative time, and the words around it, belong to the same translator.
    private var lastCheckDescription: String? {
        if updates.isChecking {
            return L10n.text("Checking for updates…")
        }
        guard let lastCheckDate = updates.lastCheckDate else {
            return L10n.text("Never checked for updates.")
        }
        let when = UpdateCheckTiming.relativeText(for: lastCheckDate, now: Date())
        guard let result = updates.lastManualResult else {
            return L10n.format("Last checked %@", when)
        }
        return L10n.format("Last checked %@ — %@", when, UpdateSettingsSummary.text(for: result))
    }
}

private enum UpdateSettingsSummary {
    /// The outcome of the last manual check, in the words the user sees.
    static func text(for result: UpdateCheckResult) -> String {
        switch result {
        case .upToDate:
            return L10n.text("PaneSpace is up to date.")
        case .available(let release):
            return L10n.format("PaneSpace %@ is available.", release.displayVersion)
        case .failed(let error):
            return error.errorDescription ?? L10n.text("The update service could not be reached.")
        }
    }
}

private struct AboutSettingsPage: View {
    var body: some View {
        SettingsPage(title: "About PaneSpace", subtitle: "An independent open-source file manager for macOS.") {
            VStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 82, height: 82)
                Text("PaneSpace")
                    .font(.title.bold())
                Text("Version 0.1.0")
                    .foregroundStyle(.secondary)
                Text("Designed for macOS 26 and later. Built with SwiftUI and AppKit under the MIT License.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 420)
                if let repositoryURL = URL(string: "https://github.com/Rowan-rh/PaneSpace") {
                    Link("View on GitHub", destination: repositoryURL)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 34)
        }
    }
}

private struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text(title))
                    .font(.title2.bold())
                Text(L10n.text(subtitle))
                    .foregroundStyle(.secondary)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        GroupBox {
            VStack(spacing: 0) {
                content
            }
            .padding(.vertical, 2)
        } label: {
            Text(L10n.text(title))
                .font(.headline)
        }
    }
}

private struct SettingRow<Control: View>: View {
    let title: String
    let detail: String?
    let planned: Bool
    @ViewBuilder let control: Control

    init(
        _ title: String,
        detail: String? = nil,
        planned: Bool = false,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.detail = detail
        self.planned = planned
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text(title))
                if planned {
                    PlannedBadge()
                }
                if let detail {
                    Text(L10n.text(detail))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 20)
            control
                .disabled(planned)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

private struct SettingsToggle: View {
    let title: String
    @Binding var isOn: Bool
    var planned = false
    /// The name VoiceOver gives the switch itself.
    ///
    /// The switch is rendered with `labelsHidden()`, so the visible title is a sibling of it rather
    /// than its label and VoiceOver would otherwise announce an unnamed "switch". A page that needs
    /// the switch to name itself passes the title here; the rest keep the existing behaviour.
    var accessibilityLabel: String?

    init(
        _ title: String,
        isOn: Binding<Bool>,
        planned: Bool = false,
        accessibilityLabel: String? = nil
    ) {
        self.title = title
        self._isOn = isOn
        self.planned = planned
        self.accessibilityLabel = accessibilityLabel
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(L10n.text(title))
            if planned { PlannedBadge() }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(planned)
                .accessibilityLabel(L10n.text(accessibilityLabel ?? title))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct PlannedBadge: View {
    var body: some View {
        Text("PLANNED")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.secondary.opacity(0.12)))
    }
}

private struct PlannedCallout: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hammer")
                .foregroundStyle(Color.accentColor)
            Text(L10n.text(text))
                .foregroundStyle(.secondary)
            Spacer()
            PlannedBadge()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.08)))
    }
}

private struct HotkeyRow: View {
    let title: String
    let shortcut: String

    var body: some View {
        HStack {
            Text(L10n.text(title))
            Spacer()
            Text(shortcut)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.1)))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text(title))
                Text(L10n.text(detail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings", action: action)
        }
        .padding(12)
    }
}

private struct ExtensionCard: View {
    let title: String
    let detail: String
    let systemImage: String
    var planned = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                Spacer()
                if planned {
                    PlannedBadge()
                }
            }
            Text(L10n.text(title))
                .font(.headline)
            Text(L10n.text(detail))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(minHeight: 122, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        }
    }
}
