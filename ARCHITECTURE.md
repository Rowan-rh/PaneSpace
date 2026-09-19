# Architecture

This document describes the current system shape. Durable decisions and their tradeoffs are recorded separately in [`docs/adr`](docs/adr).

## Goals

PaneSpace separates navigation state, presentation, and storage access so local and remote locations can share the same interface.

```text
SwiftUI views
    │
    ▼
BrowserPaneModel ─── AppModel
    │
    ▼
FileProviding protocol
    │
    ├── LocalFileProvider
    ├── SFTPProvider       planned
    ├── SMBProvider        planned
    └── WebDAVProvider     planned
```

## Modules

- `Models`: immutable file metadata, tabs, and sidebar locations.
- `State`: observable navigation and application state.
- `Services`: file-system access and platform integrations such as Quick Look.
- `Views`: SwiftUI presentation with no direct file mutation.

## Provider contract

The first implementation uses synchronous local operations to keep the MVP small. Remote providers should evolve the contract toward asynchronous, cancellable operations and expose capabilities such as rename, trash, server-side copy, and thumbnails.

Each provider should eventually report:

- stable item identifiers
- supported operations
- progress for transfers
- authentication requirements
- connection state
- normalized errors

## File-operation engine

Copying and moving should be implemented as queued jobs rather than direct view actions. Jobs should support progress, cancellation, retry, conflict decisions, and an operation journal. Local jobs can use `FileManager`; remote jobs delegate to providers.

## Security model

For a distributable sandboxed build, user-selected folders should be persisted as security-scoped bookmarks. Remote credentials belong in Keychain. Providers must never write credentials to preferences, logs, or workspace files.

## Clean-room policy

PaneSpace is implemented from public platform behavior and Apple documentation. Do not copy commercial binaries, private assets, proprietary strings, or decompiled source code into this repository.

## Planned evolution

The next architectural step is an operation engine described in [ADR 0003](docs/adr/0003-operation-queue.md). After that boundary is stable, `FileProviding` will evolve into an asynchronous capability-oriented provider API before remote backends are added.
