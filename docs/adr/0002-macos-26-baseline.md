# ADR 0002: Adopt macOS 26 as the deployment baseline

- Status: Accepted
- Date: 2026-09-19

## Context

The project prioritizes a modern native implementation and future development for macOS 26 and 27. Supporting older systems would add compatibility branches before the core product model is stable.

## Decision

PaneSpace requires macOS 26.0 or newer, Xcode 26 or newer, and Swift 6.2 or newer. The package uses Swift 6 language mode with strict concurrency checking.

## Consequences

- The codebase can use current SwiftUI and AppKit APIs directly.
- UI state and platform integrations must satisfy Swift 6 isolation rules.
- Users on macOS 25 or earlier cannot run PaneSpace.
- Lowering the deployment target requires a new ADR and a deliberate compatibility plan.
