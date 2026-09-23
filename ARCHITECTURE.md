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

Provider primitives are asynchronous. The local provider is actor-isolated so directory reads and file mutations do not block the main actor. Providers normalize common failures such as permission denial, missing items, invalid names, and name conflicts before errors reach pane state. Future remote providers should add cancellation and expose capabilities such as rename, trash, server-side copy, and thumbnails.

Each provider should eventually report:

- stable item identifiers
- supported operations
- progress for transfers
- authentication requirements
- connection state
- normalized errors

## File-operation engine

Local create-folder, rename, and Trash primitives run asynchronously and expose busy and inline-error state. `FileTransferQueueModel` runs local copy and move jobs serially, publishes item progress, cancellation, retry, and conflict decisions, and retains a session-only task list. `LocalTransferService` stages a complete copy in the destination directory before publishing it. Replace moves the old destination to Trash, and Move trashes the source only after the destination is complete. A failed source removal can be retried without copying again. Byte progress, persistent history, and remote transfers remain future work. The safety tradeoffs are recorded in [ADR 0006](docs/adr/0006-staged-local-transfers.md).

Visible local panes observe their current directory and coalesce file-system events before reloading. Completion of a transfer explicitly refreshes affected panes. `LocalPathResolver` validates typed paths outside the main actor; `BrowserPaneModel` changes history only after validation succeeds.

## Security model

For a distributable sandboxed build, user-selected folders should be persisted as security-scoped bookmarks. Remote credentials belong in Keychain. Providers must never write credentials to preferences, logs, or workspace files.

## Clean-room policy

PaneSpace is implemented from public platform behavior and Apple documentation. Do not copy commercial binaries, private assets, proprietary strings, or decompiled source code into this repository.

## Planned evolution

The operation queue is described in [ADR 0003](docs/adr/0003-operation-queue.md), the asynchronous primitive boundary in [ADR 0004](docs/adr/0004-async-provider-primitives.md), and session persistence in [ADR 0005](docs/adr/0005-versioned-session-state.md). Capability reporting and remote-specific cancellation remain to be added before remote backends.
