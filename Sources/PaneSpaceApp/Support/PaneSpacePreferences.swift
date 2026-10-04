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

    /// The stage-2 update keys, kept out of `allKeys` because Sparkle now owns what they held.
    ///
    /// `automaticallyCheckForUpdates` is migrated into `SUEnableAutomaticChecks` once and then
    /// deleted (see `UpdatePreferences`). `skippedUpdateVersion` still exists on the fallback path
    /// for a build with no appcast, so it stays resettable; the Sparkle keys that replace it are
    /// added by `updateKeys`.
    static let legacyUpdateKeys = [
        UpdatePreferences.supersededAutomaticChecksKey,
        "skippedUpdateVersion"
    ]

    /// Everything reset should clear, including the Sparkle keys whose policy differs.
    ///
    /// Split in two because the two sets have different rules: these keys are cleared unconditionally,
    /// while the Sparkle set clears only what the user can see (see `UpdatePreferences.resettableKeys`).
    static var updateKeys: [String] {
        allKeys + legacyUpdateKeys + UpdatePreferences.resettableKeys
    }

    static func reset(in defaults: UserDefaults = .standard) {
        for key in updateKeys {
            defaults.removeObject(forKey: key)
        }
        // The one-time migration is itself a preference: leaving it set would mean a reset user who
        // had a stage-2 value would never get it carried across again, and the cleared Sparkle key
        // would silently default to "checks on" instead of the choice they made.
        defaults.removeObject(forKey: UpdatePreferences.migrationFlagKey)
    }
}
