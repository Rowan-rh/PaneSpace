# Roadmap

The roadmap records intended sequencing, not a promise of delivery dates. Each milestone should leave the app usable and the file model internally coherent.

For a detailed inventory of unfinished and partially implemented features, including planned settings, see [Missing Features](MISSING_FEATURES.md).

## 0.1 — Local browsing foundation

- [x] Native macOS application shell
- [x] Twelve layouts for one to four panes
- [x] Independent tabs and navigation history
- [x] Favorites and mounted volumes
- [x] Search, sort, and hidden files
- [x] Create folder, rename, Trash, Quick Look, and Finder reveal
- [x] Local provider boundary and initial tests
- [x] Native settings center and live appearance controls
- [x] List and multi-level column browsing modes
- [x] Persist pane layout, active pane, tabs, and navigation history
- [x] Persist window placement and dimensions
- [x] Add CI for build and tests

## 0.2 — Reliable file operations

- [x] Local copy and move job queue
- [x] Item progress, cancellation, retry, and session task list
- [x] Name-conflict decisions: keep both, replace, skip, and apply to all
- [x] Local file URL drag and drop into panes
- [x] Byte progress and cancellation of large items
- [ ] Persistent operation history
- [ ] Undo support where platform behavior permits
- [ ] Large-directory loading without blocking the UI
- [x] File-system observation and live refresh

## 0.3 — Views and workflows

- [ ] Grid and gallery modes
- [x] Breadcrumb path editor and pane cycling shortcuts
- [ ] Saved workspaces
- [ ] Command palette and configurable keyboard shortcuts
- [ ] Archive creation and extraction
- [ ] Git status decorations
- [x] Batch rename

## 0.4 — Remote providers

On hold until 0.2 and 0.3 are complete.

- [ ] Async capability-oriented provider API
- [ ] SFTP
- [ ] SMB
- [ ] WebDAV
- [ ] Keychain credential storage
- [ ] Reconnect, timeout, and offline state handling

## 0.5 — Platform integration

- [ ] Finder extension
- [ ] Share extension and temporary shelf
- [ ] Services menu actions
- [ ] Spotlight and Quick Look integration where appropriate
- [ ] Accessibility and localization audit

## 1.0 — Stable release

- [ ] Signed and notarized distribution
- [ ] Automated releases and update metadata
- [ ] Migration policy for persisted workspaces
- [ ] Performance and data-integrity test suites
- [ ] Contributor governance and security response process
- [ ] User documentation
