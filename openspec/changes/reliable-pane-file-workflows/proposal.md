## Why

PaneSpace can browse two folders side by side but cannot yet transfer files between them. A reliable local transfer workflow, live folder updates, and direct keyboard navigation are needed before the multi-pane interface can serve as a practical file manager.

## What Changes

- Add local copy and move jobs between panes, including drag and drop, visible progress, cancellation, retry, and an operation history for the current app session.
- Resolve destination-name conflicts explicitly with Keep Both, Replace, or Skip, including an Apply to All choice for a batch. Never overwrite silently.
- Refresh open local folders when their contents change, including changes made outside PaneSpace.
- Make the address bar editable with Command-L and support Tab and Shift-Tab for switching the active pane.
- Keep the existing asynchronous provider boundary and add tests for transfer state, conflicts, navigation, and refresh behavior.

## Capabilities

### New Capabilities

- `local-file-transfers`: Queued local copy and move jobs, conflicts, drag and drop, progress, cancellation, retry, and history.
- `live-folder-refresh`: Observing visible local directories and refreshing panes after file-system changes.
- `keyboard-pane-navigation`: Editing a pane location directly and cycling pane focus with the keyboard.

### Modified Capabilities

None. This repository has no existing OpenSpec capability specs.

## Impact

The change affects `AppModel`, `BrowserPaneModel`, `BrowserPaneView`, `ContentView`, `FileProviding`, local file services, keyboard commands, tests, and user/developer documentation. It adds no remote provider or third-party dependency. File mutations remain outside SwiftUI views, and transfer jobs stay local-only until provider capabilities are defined for remote storage.
