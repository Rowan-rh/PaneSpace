## Context

See `proposal.md` for motivation. `BrowserPaneModel` currently owns local navigation and small file mutations through an asynchronous `FileProviding` protocol. `AppModel` owns all pane slots and their active state. There is no transfer queue, file-system watcher, or path editor. Swift 6 strict concurrency and the macOS 26 deployment target apply.

## Goals / Non-Goals

**Goals:**
- Make local cross-pane transfers recoverable, observable, and deterministic under conflicts and cancellation.
- Keep all file mutations in services and job state outside SwiftUI views.
- Reuse pane state and provider isolation for refresh and typed navigation.

**Non-Goals:**
- Remote transfers, permanent deletion, persistent job history across app launches, byte-accurate progress, and Finder-style undo are outside this change.

## Decisions

### Transfer queue and file safety

A `@MainActor` transfer queue owns immutable job descriptions and published job snapshots. It starts one local job at a time and calls an actor-isolated local transfer service. A job records per-source completion and phase so retry resumes only unfinished work. Conflict handling suspends the job via a one-shot continuation until the UI supplies a decision. Cancellation also resumes any waiting continuation and prevents the next item from starting.

The local service copies each top-level item into a uniquely named staging location in the destination directory. A complete staging item is moved into place. For Replace, the existing destination is moved to Trash first. For Move, the source is moved to Trash only after the destination is complete; a failure at that last step is tracked as a separate phase for retry. `FileManager.copyItem` preserves supported metadata and copies symbolic links as links. Cancellation during a single underlying copy is observed at the next safe boundary; any incomplete staging item is removed before the job ends. This favors recoverability over same-volume rename speed. A transfer into its own directory or subtree is rejected before any mutation.

Alternatives considered: direct `moveItem` is faster but can remove the source before the destination is verified; direct copy to the final name can expose partial files and complicate retry. Parallel jobs would complicate conflict prompts and destination races, so jobs run serially.

### Pane targeting and drag and drop

Transfer commands target a visible pane slot; with more than two panes, the UI presents explicit destinations. A row drag carries file URLs. Dropping onto a pane opens a native choice for Copy or Move so neither operation is inferred from modifier timing. Source selection and destination URL are frozen when the job is queued. Views submit intent to `AppModel`; they never mutate the file system.

### Live local observation

Each visible pane owns one directory vnode observation tied to its current URL. Navigation or disappearance cancels the old observation. Events are coalesced before `refresh()`, which already cancels stale loads and checks the current URL before publishing. Transfer completion also triggers explicit refresh of affected open panes, since vnode notifications can arrive later than the job result. A watcher reopen is attempted when the directory inode changes.

Alternative considered: polling every pane wastes work and delays updates. FSEvents offers tree-level coverage but is larger than needed for a visible-directory workflow.

### Keyboard navigation

Command-L asks the active pane's path bar to enter edit mode. `LocalPathResolver` resolves file URLs, `~/`, absolute paths, and relative paths against the pane's current directory and checks accessibility off the main actor before navigation. The pane-local field owns text focus and inline errors. A workspace key handler cycles only visible pane slots on Tab or Shift-Tab and ignores events while an editable text control has focus.

Alternative considered: menu shortcuts for bare Tab can steal ordinary text-field navigation; focus-aware key handling keeps text editing intact.

## Risks / Trade-offs

- **Large single-file cancellation latency** → The current `FileManager.copyItem` call cannot be interrupted mid-item; the UI shows Cancelling until that safe boundary, then removes staging. A future streaming copy implementation can improve latency without changing job behavior.
- **Trash unavailable on a destination volume** → Replace fails safely before publishing a new destination and reports the error; it never deletes the existing item permanently.
- **Directory watcher event bursts** → Coalescing and URL guards avoid redundant and stale refreshes.
- **Drag payloads from other apps** → Only local file URLs are accepted; unsupported payloads leave the pane unchanged.

## Migration Plan

No stored session format changes are required. The queue is session-only. The new controls are additive, and reverting the change leaves existing navigation and local create/rename/Trash behavior intact.
