# ADR 0009: Undo file operations with recoverable steps only

- Status: Accepted
- Date: 2026-09-25

## Context

Users expect Command-Z to reverse the last file operation, as in Finder. Undo itself touches files, so it must follow the same safety rules as the operations it reverses: no silent overwrite and no permanent deletion. It also must not take Command-Z away from text fields.

## Decision

Undo works from the records of [ADR 0008](0008-persistent-operation-history.md). `OperationUndoService` reverses each kind as follows:

- **Rename:** rename back through `BatchRenamer`, so swapped and case-only names work.
- **Move to Trash:** move the recorded Trash item back to its original path.
- **New folder:** move the folder to the Trash, but only while it is still empty.
- **Copy:** move the copy to the Trash, then put back any item that Replace had moved to the Trash.
- **Move:** put the trashed original back and move the copy to the Trash. If the Trash was emptied, the copy is moved back instead. Any item that Replace had moved to the Trash is also put back.

Before moving anything back, undo checks that the original location is free and that its folder still exists. Otherwise it stops and says which item is in the way. Items are reversed independently, and a partial result reports how many were restored. A record is marked undone once any item was restored, so it cannot be applied twice.

Edit > Undo replaces the standard undo group. When a text view is the first responder, the command sends `undo:` through the responder chain. Otherwise it undoes the newest record that has not been undone. The history window offers Undo for every eligible record. Panes whose location lies inside a changed folder reload, and tabs follow folders renamed by undo.

## Consequences

- Undo never deletes data. It can leave extra items in the Trash, such as the retired copy of an undone move.
- Undo is available after relaunch, for as long as the record stays in history.
- Redo of file operations is not provided. Redo stays available for text editing.
- Changes made outside PaneSpace after the operation can block undo. In that case the user sees why instead of losing data.
