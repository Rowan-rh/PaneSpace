# ADR 0003: Model file mutations as queued operations

- Status: Accepted
- Date: 2026-09-19

## Context

Copying and moving files can take minutes, span providers, encounter conflicts, lose connectivity, or require cancellation. Performing these mutations directly from button handlers cannot provide reliable state management.

## Decision

Introduce a serial local transfer queue whose jobs have stable identifiers and explicit states: queued, running, waiting for user decision, cancelling, completed, cancelled, and failed.

Jobs report item progress, accept cancellation, and record conflicts. Views submit commands and observe job state. An actor-isolated local transfer service executes mutations. The queue owns retry and conflict policy, including an apply-to-all decision for the current job. Byte progress, pausing, persistent history, and provider-neutral execution remain future work.

## Consequences

- Cross-pane drag and drop can use the same engine as menus and shortcuts.
- Operation history and progress UI become natural projections of job state.
- Tests can validate state transitions independently of SwiftUI.
- Local transfers have one mutation path shared by drag and drop, menus, and shortcuts.
