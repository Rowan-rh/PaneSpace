# ADR 0010: List folders incrementally and sort off the main actor

- Status: Accepted
- Date: 2026-09-25
- Amends: [ADR 0004](0004-async-provider-primitives.md)

## Context

A folder with 50,000 files took about three seconds to read in a release build and 2.5 seconds to sort. The sort ran on the main actor, so the window froze. Profiling found three causes:

- Looking up the localized kind for every file took 2.3 of the three seconds.
- Each comparison re-derived the file name from its URL.
- The sort closure read published properties and copied large structs.

## Decision

- `FileProviding` gains `contentBatches(of:showsHiddenFiles:)`, an `AsyncThrowingStream` of item batches. The default implementation yields `contents(of:)` as one batch. The local provider enumerates without descending into folders or packages, yields 1,000 items per batch, stops when the stream is cancelled, and reports errors normalized as before.
- The local provider caches the localized kind for items that must share it: plain folders, and files, packages, or symbolic links with the same extension. Volumes and files without an extension are still looked up one by one.
- `FileItem` stores its name. `FileItemSorter` is a pure function that sorts indices over prepared keys and still uses `localizedStandardCompare`.
- When a pane opens a folder that is not already on screen, it shows the first batch immediately and then merges further batches at most every 250 ms. Reloading the folder already on screen waits for the complete listing so rows do not disappear and return.
- Every listing is filtered and sorted in a detached task. The result seeds the display cache for the new item revision, so views do not sort on the main actor.

## Consequences

- Measured on 50,000 files in a release build, reading dropped from about 2.9 s to 0.8 s and sorting from 2.5 s to 0.17 s. Neither blocks the main actor any longer.
- While later batches are still arriving, the status bar shows a loading label and keyboard navigation waits.
- Remote providers can override `contentBatches` to show slow listings progressively.
- Column refreshes still read each column in one call. They can adopt batches later if needed.
