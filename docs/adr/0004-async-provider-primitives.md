# ADR 0004: Use asynchronous provider primitives

- Status: Accepted
- Date: 2026-09-21

## Context

The first local provider exposed synchronous listing and mutation methods. `BrowserPaneModel` is isolated to the main actor, so direct calls to those methods could block interface updates while the file system or a mounted volume responded.

ADR 0001 already required the provider boundary to become asynchronous before remote providers were added. ADR 0003 separately defines the larger queued operation engine needed for copy, move, progress, retry, and conflict decisions.

## Decision

Provider primitives are asynchronous. The local provider is an actor that isolates its `FileManager` instance and performs synchronous system calls away from the main actor. Provider errors are normalized into stable, user-facing categories before crossing the provider boundary.

Pane state keeps directory-loading errors separate from file-operation errors. Local create-folder, rename, and Trash requests expose busy state, refresh after partial completion, and show operation failures inline.

## Consequences

- Slow local or mounted-volume calls no longer block the main actor.
- Remote providers can implement the same contract without wrapping synchronous APIs.
- Views can disable conflicting mutations while one local mutation is in progress.
- The provider actor serializes create-folder, rename, and Trash primitives. The separate local transfer queue from ADR 0003 now handles copy and move.
- Remote-provider capability reporting and provider-neutral transfer execution remain future work.
