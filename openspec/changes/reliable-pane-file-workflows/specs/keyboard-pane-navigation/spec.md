## Purpose

Provides direct path entry and predictable keyboard focus movement so multi-pane browsing can be completed without relying on the pointer.

## ADDED Requirements

### Requirement: Edit the active pane location
The system SHALL open an editable location field for the active pane with Command-L. It SHALL accept an absolute local path, a file URL, a home-relative path, or a path relative to the current directory, expand a leading tilde, and navigate only when the resolved directory exists and is accessible. It SHALL show an inline error for an invalid location and keep the current location unchanged. Escape SHALL dismiss editing without navigation.

#### Scenario: Valid path
- **WHEN** the user enters an existing directory path and presses Return
- **THEN** the active pane navigates to that directory and records it in history

#### Scenario: Invalid path
- **WHEN** the user enters a missing or inaccessible location
- **THEN** the pane stays at its current directory and displays an inline error

#### Scenario: Cancel editing
- **WHEN** the user presses Escape while editing
- **THEN** the field closes and the pane location remains unchanged

### Requirement: Cycle active panes
The system SHALL move active pane focus to the next visible pane with Tab and to the previous visible pane with Shift-Tab, wrapping at either end. Pane cycling SHALL not interfere with text entry in editable controls.

#### Scenario: Cycle in two-pane layout
- **WHEN** the right pane is active and the user presses Tab outside a text field
- **THEN** the left pane becomes active

#### Scenario: Reverse cycle
- **WHEN** the left pane is active and the user presses Shift-Tab outside a text field
- **THEN** the last visible pane becomes active
