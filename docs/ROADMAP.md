# Roadmap

The roadmap records intended sequencing, not a promise of delivery dates. Each milestone should leave the app usable and the file model internally coherent.

For a detailed inventory of unfinished and partially implemented features, including planned settings, see [Missing Features](MISSING_FEATURES.md).

Status marks: `[x]` done, `[ ]` not started, `[~]` implemented but not finished — verification, edge cases or cleanup still open.

## 0.1 — Local browsing foundation

- [x] Native macOS application shell
- [x] Twelve layouts for one to four panes
- [x] Independent tabs and navigation history
- [x] Favorites and mounted volumes
- [x] Search, sort, and hidden files
- [x] Create folder, rename, Trash, Quick Look, Open in Terminal, and Finder reveal
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
- [x] Persistent operation history
- [x] Undo support where platform behavior permits
- [x] Large-directory loading without blocking the UI
- [x] File-system observation and live refresh

## 0.3 — Views and workflows

- [ ] Grid and gallery modes
- [x] Breadcrumb path editor and pane cycling shortcuts
- [x] Saved workspaces (sidebar workspace management: custom name, icon, and path)
- [ ] Command palette and configurable keyboard shortcuts
- [~] Folder left/right arrow navigation (wired in both list and column views; focus retention across a pane switch is still unverified)
- [x] Collapsible pane search (a magnifier button that expands on click or Command-F)
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
- [~] Automated releases and update metadata — implemented (tag-triggered release workflow; the signed appcast is committed only after the Release is public) but not yet exercised on GitHub Actions — no real release has run, and `scripts/update-public-ed25519.txt` is still a placeholder that must hold the real public key before the first tag
- [ ] Migration policy for persisted workspaces
- [ ] Performance and data-integrity test suites
- [ ] Contributor governance and security response process
- [ ] User documentation
