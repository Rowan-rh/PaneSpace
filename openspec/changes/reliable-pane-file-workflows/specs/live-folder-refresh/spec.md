## Purpose

Keeps the contents of visible local panes aligned with file-system changes made both inside and outside PaneSpace without losing the user's browsing context.

## ADDED Requirements

### Requirement: Refresh visible folders after changes
The system SHALL observe each visible local pane directory and refresh it after an external or PaneSpace-initiated content change. Observation SHALL stop when the pane navigates away or is no longer visible.

#### Scenario: External file appears
- **WHEN** another application creates a file in a visible pane directory
- **THEN** the new file appears without manual refresh

#### Scenario: Pane changes location
- **WHEN** a pane navigates to another directory
- **THEN** changes in the old directory no longer trigger that pane's refresh

### Requirement: Preserve interaction state during refresh
The system SHALL retain selection for surviving items and SHALL not replace newer navigation results with stale observations.

#### Scenario: Selected item remains
- **WHEN** a folder refresh completes and a selected item still exists
- **THEN** the item remains selected

#### Scenario: Rapid navigation
- **WHEN** an observation arrives after the pane has navigated away
- **THEN** it does not change the new pane contents
