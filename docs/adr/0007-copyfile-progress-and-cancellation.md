# ADR 0007: Copy local items with copyfile progress callbacks

- Status: Accepted
- Date: 2026-09-25
- Amends: [ADR 0006](0006-staged-local-transfers.md)

## Context

ADR 0006 staged each item with a single `FileManager.copyItem` call. That call reports no progress and cannot stop until the whole item is copied, so a multi-gigabyte file kept running after the user cancelled and the transfer bar could only count items.

## Decision

The local transfer service copies each item into its staging location with `copyfile(3)` using `COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_NOFOLLOW | COPYFILE_CLONE`. These flags keep the metadata `FileManager.copyItem` preserved: data, extended attributes, ACLs, and timestamps, with symbolic links copied as links. On APFS the copy is a clone when possible.

A status callback accumulates copied bytes into a lock-protected counter. The callback runs synchronously on the task that started the copy. It returns `COPYFILE_QUIT` as soon as that task is cancelled, and the service then removes the partial staging item as before. A cloned file produces no data callbacks, so every finished file counts its full size.

Before a job copies anything, the queue measures the logical size of every item without following symbolic links. While an item runs, the queue samples the counter a few times per second instead of publishing every callback to the main actor.

The staging, replacement, and move-to-Trash rules of ADR 0006 are unchanged.

## Consequences

- The transfer bar shows bytes copied against the job total, and cancelling stops a large file mid-copy.
- Measuring adds a directory walk before large folder transfers start.
- Progress for a cloned file jumps from zero to its full size when the file finishes.
- Pausing and provider-neutral transfers remain future work.
