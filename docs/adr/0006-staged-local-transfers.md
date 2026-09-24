# ADR 0006: Stage local transfers before publishing destinations

- Status: Accepted; copy mechanism amended by [ADR 0007](0007-copyfile-progress-and-cancellation.md)
- Date: 2026-09-23

## Context

A direct copy to the final name can leave a partial item visible after failure. A direct move can remove the source before the destination is known to be complete. Replacing an existing item must preserve a recovery path.

## Decision

The local transfer service copies each item to a unique temporary sibling in the destination directory and moves the completed copy to its final name. It removes staging data on error or cancellation. Replace first moves the old destination to Trash. Move sends the source to Trash only after the destination is published. If source removal fails, retry resumes that phase without copying a second destination.

The service compares canonical source and destination directory paths before copying, so symbolic-link aliases cannot turn a transfer into a copy to its own directory or subtree. The queue processes one job at a time and checks cancellation between top-level items and immediately after staging. A single `FileManager.copyItem` call is not interrupted in the middle of an item. `FileManager.copyItem` retains supported metadata and copies symbolic links as links.

## Consequences

- Users do not see partial destinations from a failed copy.
- Existing destinations remain recoverable from Trash after replacement.
- Copying within one volume can take longer and use more temporary space than a rename-based move.
- Byte progress and prompt cancellation of a very large single item require a future streaming implementation.
