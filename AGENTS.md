# AGENTS.md

This file defines the development contract for every contributor and coding agent working in this repository. It applies to the entire repository unless a deeper directory contains a more specific `AGENTS.md`.

## Product identity

- Product name: **PaneSpace**.
- PaneSpace is an independent, clean-room, open-source macOS file manager.
- Never copy code, assets, localized strings, icons, private APIs, or reverse-engineered implementation details from commercial products.
- Similar workflows are acceptable; visual identity and implementation must remain original.

## Supported platform

- Minimum deployment target: macOS 26.0.
- Design and test against the current macOS 26 SDK while keeping source compatibility in mind for macOS 27.
- Toolchain: Xcode 26 or newer and Swift 6.2 or newer.
- Swift language mode: Swift 6 with strict concurrency checking.
- Do not add compatibility branches for macOS 25 or earlier unless the deployment policy is changed in an ADR.

## Architecture rules

- Keep the dependency direction `Views -> State -> Services/Providers -> System APIs`.
- SwiftUI views present state and send user intent. They must not perform direct file-system mutations.
- `BrowserPaneModel` owns navigation and pane state. Cross-pane state belongs in `AppModel`.
- Storage-specific behavior belongs behind a provider protocol. Do not add SFTP, SMB, WebDAV, or cloud-specific conditions to views.
- UI-facing mutable reference types must be isolated to `@MainActor`.
- Long-running file and network operations must be asynchronous, cancellable, and must not block the main actor.
- Prefer value types for file metadata, navigation history, job descriptions, and provider capabilities.
- New architectural decisions that constrain future work require an ADR in `docs/adr/`.

## File operations

- Destructive operations must require an explicit user action and use recoverable platform behavior when available.
- Copy and move operations belong in the planned operation queue, not directly in a view callback.
- Never overwrite an existing item silently. Conflict handling must be explicit and testable.
- Preserve extended attributes and resource forks where the underlying provider supports them.
- Do not follow symbolic links recursively without cycle detection.

## Credentials and privacy

- Store remote credentials and tokens only in Keychain.
- Never write credentials, tokens, complete home paths, or file contents to logs.
- Do not commit secrets, signing certificates, provisioning profiles, personal bookmarks, or generated application state.
- Network providers must use encrypted transport by default and surface certificate failures to the user.

## UI conventions

- Use native SwiftUI and AppKit controls before introducing custom controls.
- Keep keyboard navigation and VoiceOver labels functional.
- Dual-pane layout must prioritize file names over secondary metadata.
- Every operation reachable with a mouse should have a keyboard path when practical.
- UI strings should be localization-ready; do not assemble user-facing sentences from fragments.
- Avoid generic modal alerts for recoverable background errors. Prefer inline status and retry actions.

## Code style

- Use descriptive names; avoid abbreviations except established protocol names.
- Avoid force unwraps and force casts in production code.
- Keep files focused on one primary type or responsibility.
- Prefer early returns over deeply nested conditionals.
- Document why a non-obvious decision exists, not what each line does.
- Treat warnings as defects. New code must compile without warnings.

## Tests and verification

Before finishing a change, run:

```bash
swift test
make app
codesign --verify --deep --strict dist/PaneSpace.app
```

Add tests for:

- provider behavior and normalized errors;
- navigation history and tab state;
- name validation and conflict decisions;
- operation queue state transitions;
- regressions fixed by the change.

Changes to visible UI must also be launched and inspected on macOS. Verify both single-pane and dual-pane layouts when the change affects shared content.

## Documentation

- Keep `README.md` focused on users and first-time contributors.
- Update `ARCHITECTURE.md` when module boundaries or data flow changes.
- Update `docs/ROADMAP.md` when scope or release sequencing changes.
- Add an ADR for durable technical decisions and mark superseded ADRs instead of deleting them.
- Update `docs/DEVELOPMENT.md` when build, test, signing, or release steps change.

## Git workflow

- Work from `main` using focused branches.
- Use imperative commit subjects, such as `Add cancellable copy jobs`.
- Keep generated `.build/` and `dist/` output out of Git.
- Do not mix broad formatting changes with functional changes.
- Pull requests must describe behavior, verification, screenshots for UI changes, and known follow-up work.

## Definition of done

A change is complete only when it builds, relevant tests pass, the app has been exercised for the changed workflow, documentation is current, and no known data-loss path was introduced.
