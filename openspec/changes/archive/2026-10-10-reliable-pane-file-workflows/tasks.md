## 1. Reliable local transfers

- [x] 1.1 Add local transfer types and a staging-based copy/move service; verify tests cover metadata, symlinks, invalid destinations, replacement recovery, and staging cleanup.
- [x] 1.2 Add serial queue state, explicit conflict decisions, cancellation, and retry; verify tests cover state transitions, apply-to-all, and no duplicate destinations on retry.
- [x] 1.3 Wire copy/move commands, file URL drag and drop, conflict choices, and a visible task list into the panes; verify the app can copy and move between both panes by mouse and keyboard.

## 2. Current directory awareness

- [x] 2.1 Add local directory observation with coalescing and lifecycle cancellation; verify an external create or rename refreshes a visible pane and old-directory events do not change a new location.
- [x] 2.2 Refresh affected panes at transfer completion and preserve surviving selection; verify tests and a live app workflow.

## 3. Keyboard navigation

- [x] 3.1 Add path resolution and asynchronous validation with inline error handling; verify tests for absolute, relative, home, file URL, invalid, and inaccessible paths.
- [x] 3.2 Add Command-L location editing plus Tab/Shift-Tab pane cycling that respects text entry; verify both keyboard flows in the launched app.

## 4. Integration and documentation

- [x] 4.1 Update architecture, roadmap, README, and ADR for the operation queue; verify documentation matches the implemented behavior.
- [x] 4.2 Run `openspec validate --strict`, `swift test`, `make app`, and strict codesign verification; inspect single- and dual-pane layouts and exercise copy, move, conflict, cancellation, and refresh in the app.
