# Architecture

This document describes the current system shape. Durable decisions and their tradeoffs are recorded separately in [`docs/adr`](docs/adr).

## Goals

PaneSpace separates navigation state, presentation, and storage access so local and remote locations can share the same interface.

```text
SwiftUI views
    │
    ▼
BrowserPaneModel ─── AppModel
    │
    ▼
FileProviding protocol
    │
    ├── LocalFileProvider
    ├── SFTPProvider       planned
    ├── SMBProvider        planned
    └── WebDAVProvider     planned

AppModel ─── FileTransferQueueModel ─── LocalTransferService
AppModel ─── OperationHistoryModel ─── OperationHistoryStore / OperationUndoService
AppModel ─── WorkspaceShortcutsModel ─── UserDefaults / LocalPathResolver
AppModel ─── UpdateModel ─── SPUStandardUpdaterController / UpdateFeed
BrowserPaneModel ─── LocalDirectoryObserver / LocalPathResolver
```

## Modules

- `Models`: immutable file metadata, tabs, and sidebar locations.
- `State`: observable navigation and application state.
- `Services`: file-system access and platform integrations such as Quick Look.
- `Views`: SwiftUI presentation with no direct file mutation.

## Workspace layout

`PaneLayout` defines twelve arrangements using one to four persistent `BrowserPaneModel` instances. Changing a layout changes presentation only; each pane keeps its independent tabs, navigation history, selection, sorting, and search state. The primary pane receives extra space in asymmetric layouts using a 62/38 proportion.

`BrowserViewMode` selects list or column presentation independently for each pane. Column navigation state is owned by `BrowserPaneModel`: each `BrowserColumn` is an immutable directory snapshot, while asynchronous child loading, selection, history, and cancellation remain in the state layer. Views render columns and forward user intent without accessing the file provider directly.

Window chrome follows fixed density targets so layouts remain predictable: a 196-point default sidebar, 36-point tab strip, 36-point address bar, and 24-point status bar. These values are user-adjustable only where a setting has a clear accessibility or density benefit.

The main window uses AppKit frame autosave for placement and dimensions. Workspace content is persisted separately in `AppSession`, so window-system state does not become part of the workspace schema.

## Preferences

The Settings scene uses `AppStorage` for lightweight user preferences. Options that are already connected update open windows immediately. Planned capabilities are visibly marked rather than silently pretending to work. Pane layout, active pane, tabs, navigation history, view mode, hidden-file visibility, and sorting are stored together in the versioned `AppSession` model. Other preferences that grow into structured data, such as workspaces, hotkeys, providers, or contextual-menu definitions, must also move to versioned models instead of accumulating independent keys.

## Provider contract

Provider primitives are asynchronous. The local provider is actor-isolated so directory reads and file mutations do not block the main actor. Folders are listed as a stream of batches, so a pane can show the first items of a large folder before the listing ends. Panes sort and filter every listing in a detached task before showing it ([ADR 0010](docs/adr/0010-incremental-directory-listing.md)). Providers normalize common failures such as permission denial, missing items, invalid names, and name conflicts before errors reach pane state. Future remote providers should add cancellation and expose capabilities such as rename, trash, server-side copy, and thumbnails.

Each provider should eventually report:

- stable item identifiers
- supported operations
- progress for transfers
- authentication requirements
- connection state
- normalized errors

## File-operation engine

Local create-folder, rename, and Trash primitives run asynchronously and expose busy and inline-error state. `FileTransferQueueModel` runs local copy and move jobs serially, publishes item and byte progress, cancellation, retry, and conflict decisions, and reports each finished run to `OperationHistoryModel`, which also records renames, Trash, and new folders and persists them as versioned JSON ([ADR 0008](docs/adr/0008-persistent-operation-history.md)). `OperationUndoService` reverses those records with recoverable steps only ([ADR 0009](docs/adr/0009-undo-with-recoverable-steps.md)). `LocalTransferService` stages a complete copy in the destination directory before publishing it, copying with `copyfile(3)` so bytes are reported and cancellation stops a file mid-copy ([ADR 0007](docs/adr/0007-copyfile-progress-and-cancellation.md)). Replace moves the old destination to Trash, and Move trashes the source only after the destination is complete. A failed source removal can be retried without copying again. Remote transfers remain future work. The safety tradeoffs are recorded in [ADR 0006](docs/adr/0006-staged-local-transfers.md).

Visible local panes observe their current directory and coalesce file-system events before reloading. Completion of a transfer explicitly refreshes affected panes. `LocalPathResolver` validates typed paths outside the main actor; `BrowserPaneModel` changes history only after validation succeeds.

## Sidebar

`SidebarModel` loads favorites and mounted volumes from `SidebarLocationProviding`. User-defined workspaces live in `WorkspaceShortcutsModel`, which `AppModel` shares between the sidebar and Settings. It stores name, SF Symbol, and folder path as JSON in preferences, validates paths through `LocalPathResolver`, and checks folder availability off the main actor. Selecting a sidebar row opens it in the active pane, and the sidebar highlight follows the active pane's location. Workspaces whose folder is missing stay listed but cannot be selected.

## Update checks

Updates have two sources, and which one answers is decided at build time rather than at runtime. A bundle that carries Sparkle and an `SUPublicEDKey` — that is, a build made by `scripts/build-app.sh` with `PANESPACE_ED_PUBLIC_KEY` and `PANESPACE_APPCAST_URL` set — asks Sparkle's appcast, and that is the normal path. Everything else (a plain `make app`, `swift run`, a test runner) has no appcast to ask and uses `UpdateFeed` / `GitHubReleaseFeed`, which reads this repository's unauthenticated GitHub Releases API: with beta updates off it asks `/releases/latest`, and with them on it asks `/releases?per_page=20` and takes the highest version, because that list is ordered by publication date rather than version. Drafts and tags that are not versions are never offered. The request layer is behind an injectable loader and normalizes every non-2xx, decoding, transport, and cancellation failure into `UpdateFeedError`, so rate limiting is distinguishable from an outage. ADR 0011 decision 2 records the rule; both paths are described here because both are still live and both are tested.

`UpdateModel` is a state adapter on the Sparkle path, not an update engine. Sparkle fetches the appcast, compares versions, filters channels, downloads, verifies and installs; the model translates the callbacks into state a banner can render and passes the user's intent back. It deliberately keeps no second copy of the answer — a version compared here and a version installed by Sparkle could disagree, and the user would be shown one and given another. `usesSparkle` is therefore a property of the build, not of the current network state: an updater that fails to `start()` leaves `usesSparkle` true and leaves the fallback path unused, which is why `startSparkle()` logs the reason and nothing else.

`SparkleUpdateDelegate` is the only place Sparkle's two delegate protocols are implemented. It owns no state — it forwards to `UpdateModel`, whose published properties are what the banner observes. Gentle reminders (`supportsGentleScheduledUpdateReminders`) are what move presentation into PaneSpace's own banner; a check the user asked for is still Sparkle's to present, which is why "Check for Updates…" behaves the way a user expects.

The current version comes from `CFBundleShortVersionString`. A build without one — `swift run`, a test runner — is not checked at all, because there is no honest way to compare it against a release. The environment variable `PANESPACE_UPDATE_FAKE_VERSION` overrides the current version for on-device banner verification.

On the Sparkle path the daily schedule belongs to the updater (`updateCheckInterval` together with `automaticallyChecksForUpdates`), and the model only applies the stored switch and interval before calling `start()`. On the fallback path a scheduled check runs at launch and then every 24 hours; its failures are silent apart from one log line that names a reason and no host, path, or query. A manual check reports `upToDate`, `available`, or `failed` so the UI can answer the user who asked; a manual check that is cancelled reports `failed(.cancelled)` rather than the previous result, because a cancellation is not an answer. Sparkle reports the ordinary end of a cycle — nothing newer, or the user cancelling at the authorization prompt — through the same error channel as a broken feed, and `isOrdinarySparkleOutcome` is what keeps those from being reported as failures. The two endings are not the same kind of answer, so they are separated: `SUNoUpdateError` is the answer to the question, while `SUInstallationCanceledError` and `SUInstallationAuthorizeLaterError` mean an update exists and was not installed. A manual check ending that way writes no `lastManualResult` at all and leaves the previous one in place — `.upToDate` would deny there is anything to install, `.failed` would blame the user for declining — so Settings falls back to "Last checked <time>", which claims nothing. Skipping hides one version, not the channel: a higher release is still offered.

Preferences are Sparkle's own keys (`SUEnableAutomaticChecks`, `betaUpdates`, and `SUSkippedVersion` / `SUSkippedMajorVersion` / `SUSkippedMajorSubreleaseVersion`); PaneSpace keeps `skippedUpdateVersion` only for the fallback path. Turning either switch off cancels the check in flight rather than leaving it to finish against stale settings. What Sparkle stores as skipped is the update's `CFBundleVersion`, so what Settings renders is the display version captured at skip time; a skip restored from Sparkle's key can only show the build number, because the display string is not written anywhere.

`UpdateModel` observes the `UserDefaults` it was given rather than relying on its own setters, because a view may write those keys directly — `SettingsView` binds `betaUpdates` with `@AppStorage`, which never reaches a computed setter. The response is identical however the value changed, and `automaticallyChecks` and `includesPrereleases` are `@Published` so a view binding them is notified.

Each check on the fallback path carries a generation. A check that has been superseded by a newer one — a second "Check Now", a channel switch, automatic checks being turned off — still runs to completion before its caller resumes, and may not clear `isChecking` or publish a result on the way out; only the check that still owns the model may. That is what keeps a replaced check from overwriting the answer that replaced it, and what keeps a stop from failing to cancel a check it never held a handle to.

## Security model

For a distributable sandboxed build, user-selected folders should be persisted as security-scoped bookmarks. Remote credentials belong in Keychain. Providers must never write credentials to preferences, logs, or workspace files.

## Clean-room policy

PaneSpace is implemented from public platform behavior and Apple documentation. Do not copy commercial binaries, private assets, proprietary strings, or decompiled source code into this repository.

## Planned evolution

The operation queue is described in [ADR 0003](docs/adr/0003-operation-queue.md), the asynchronous primitive boundary in [ADR 0004](docs/adr/0004-async-provider-primitives.md), and session persistence in [ADR 0005](docs/adr/0005-versioned-session-state.md). Capability reporting and remote-specific cancellation remain to be added before remote backends.
