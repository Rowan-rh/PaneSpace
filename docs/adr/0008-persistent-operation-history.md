# ADR 0008: Persist finished operations as reversible records

- Status: Accepted
- Date: 2026-09-25

## Context

Transfer jobs lived only in memory, so after relaunching the user could not see what was copied, moved, renamed, or trashed. Undo, a later 0.2 item, needs the same information and must survive the process that performed the operation.

## Decision

Every finished file operation produces an `OperationRecord`. This covers copy and move runs, single and batch renames, moving to the Trash, and new folders. A record stores the kind, outcome, date, containing or destination folder, requested count, error message, and one `OperationRecordItem` per changed item. Each item holds its original URL, its resulting URL, where the operation put something in the Trash, and any existing item that a Replace decision moved to the Trash. Providers and the transfer service report the Trash location returned by `FileManager.trashItem`, so these locations are exact rather than guessed.

The transfer queue reports each run of a job once. Items finished by an earlier run are left out, so a retry does not repeat them. Cancelled runs that changed nothing are not recorded.

`OperationHistoryModel` keeps the newest 200 records. `OperationHistoryStore` is an actor that writes them as versioned JSON to `Application Support/<bundle identifier>/OperationHistory.json`. Writes are atomic and chained so an older snapshot never replaces a newer one. A missing, unreadable, or newer-format file starts an empty history instead of failing.

## Consequences

- History survives relaunches and can be cleared by the user without touching files.
- The history file contains full paths of items the user operated on. It stays in the user's Application Support folder, is never logged, and is not part of preferences reset.
- Undo can be built from records without re-deriving file-system state.
- A format change needs a version bump and a migration or reset rule.
