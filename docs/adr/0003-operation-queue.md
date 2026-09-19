# ADR 0003: Model file mutations as queued operations

- Status: Proposed
- Date: 2026-09-19

## Context

Copying and moving files can take minutes, span providers, encounter conflicts, lose connectivity, or require cancellation. Performing these mutations directly from button handlers cannot provide reliable state management.

## Proposed decision

Introduce an operation engine whose jobs have stable identifiers and explicit states: queued, preparing, running, waiting for user decision, paused, completed, cancelled, and failed.

Jobs report byte and item progress, accept cancellation, and record normalized conflicts. Views submit commands and observe job state. Providers execute primitives and report capabilities. The engine owns retry and conflict policy.

## Expected consequences

- Cross-pane drag and drop can use the same engine as menus and shortcuts.
- Operation history and progress UI become natural projections of job state.
- Tests can validate state transitions independently of SwiftUI.
- Initial implementation cost is higher than direct `FileManager` calls but avoids duplicated and unsafe mutation paths.
