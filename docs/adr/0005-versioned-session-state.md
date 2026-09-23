# ADR 0005: Persist workspace sessions as a versioned model

- Status: Accepted
- Date: 2026-09-21

## Context

PaneSpace has four persistent pane models, and each pane can hold several tabs with independent navigation history and presentation settings. Saving these values as unrelated preferences would make partial restores and future migrations difficult to reason about.

## Decision

Store workspace state as one Codable `AppSession` value in `UserDefaults`. The session contains a schema version, pane layout, active pane, and a `BrowserPaneSession` for every pane. Each pane session records its tabs, active tab, view mode, hidden-file visibility, and sort settings.

Save the session when the app becomes inactive or its content view disappears. Restore it only when the user enables session restoration and its schema version is supported. Fall back to startup preferences when restoration is disabled or stored data cannot be decoded.

Fresh sessions start in locations that do not require protected-folder consent. Access to Desktop, Documents, Downloads, and external volumes begins from an explicit user navigation action, allowing macOS to present the corresponding usage description at a meaningful time.

Window placement and dimensions use AppKit's native frame autosave mechanism. They remain outside the workspace model because they are presentation state managed by the window system.

## Consequences

- A saved workspace is decoded atomically instead of mixing values from several independent keys.
- Unsupported versions fail safely to startup defaults.
- Adding fields requires either compatible decoding defaults or a schema migration.
- Stored file URLs may become unavailable; providers continue to surface those failures through normal inline error state.
