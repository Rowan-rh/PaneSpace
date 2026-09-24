import Foundation

enum PaneSpacePreferences {
    static let allKeys = [
        "startupLocation",
        "restoreLastSession",
        "openWorkspaceInTab",
        "keepRecentLocations",
        "confirmQuit",
        "showStatusBar",
        "defaultPaneLayout",
        "currentPaneLayout",
        "accentColor",
        "themeIntensity",
        "sidebarWidth",
        "rowDensity",
        "pinnedTabStyle",
        "paneCloseButton",
        "keyResponse",
        "blankDoubleClickAction",
        "openFoldersInNewTab",
        "confirmDragAndDrop",
        "showParentFolderEntry",
        "expandPackages",
        "addressBarPosition",
        "showPaneNavigation",
        "showAddressReload",
        "showAddressActions",
        "showToolbarNavigation",
        "expandFolderMenus",
        "showWorkspaceGroup",
        "showVolumesGroup",
        "showTagsGroup",
        "showVolumeFreeSpace",
        "sidebarPosition",
        "newTabPosition",
        "reuseEmptyTabs",
        "doubleClickClosesTab",
        "restoreTabs",
        "defaultViewMode",
        "alternateRowBackgrounds",
        "showFileExtensions",
        "calculateFolderSizes",
        "iconSize",
        "searchScope",
        "searchContents",
        "searchHiddenItems",
        "searchWhileTyping",
        "contextQuickLook",
        "contextShowFinder",
        "contextRename",
        "contextTrash",
        "contextCopyPath",
        "contextServices",
        "preferredTerminal",
        "preferredEditor",
        "betaUpdates",
        "diagnosticLogging",
        "appSession",
        "workspaceShortcuts",
        "NSWindow Frame PaneSpace.MainWindow"
    ]

    static func reset(in defaults: UserDefaults = .standard) {
        for key in allKeys {
            defaults.removeObject(forKey: key)
        }
    }
}
