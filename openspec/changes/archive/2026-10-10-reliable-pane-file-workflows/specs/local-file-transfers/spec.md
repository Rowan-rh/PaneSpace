## Purpose

Enables reliable copy and move workflows between local panes while making every conflict, transfer state, and failure visible to the user.

## ADDED Requirements

### Requirement: Start a transfer to another pane
The system SHALL allow selected local files and folders to be copied or moved to another visible pane through a keyboard-accessible action and drag and drop. The destination SHALL be that pane's current directory when the job starts.

#### Scenario: Copy selected items
- **WHEN** the user selects items in one pane and chooses Copy to another visible pane
- **THEN** the system queues a copy job to the destination pane without changing the originals

#### Scenario: Move selected items
- **WHEN** the user selects items in one pane and chooses Move to another visible pane
- **THEN** the system queues a move job and removes each source only after its destination copy succeeds

#### Scenario: Invalid destination
- **WHEN** the destination is the source directory, the source item itself, or a descendant of a source folder
- **THEN** the system rejects the job with a visible error and does not mutate files

### Requirement: Resolve destination conflicts
The system MUST NOT overwrite an existing destination silently. It SHALL pause at a conflict and offer Keep Both, Replace, and Skip; the user SHALL be able to apply a choice to all remaining conflicts in the job. Replace SHALL keep the displaced destination recoverable through the platform Trash when supported.

#### Scenario: Unresolved name conflict
- **WHEN** a destination item already has the source item's name and no batch decision applies
- **THEN** the job waits for an explicit decision before mutating that destination

#### Scenario: Keep both
- **WHEN** the user chooses Keep Both
- **THEN** the system creates a unique destination name and retains the existing item

#### Scenario: Skip
- **WHEN** the user chooses Skip
- **THEN** that source and destination remain unchanged and the job continues

### Requirement: Report and control transfer jobs
The system SHALL process transfer jobs in order, show queued/running/waiting/completed/failed/cancelled states, show item-level progress, allow cancellation and retry of failed or cancelled jobs, and retain a history for the current application session. Cancellation SHALL prevent further items from starting and clean up any incomplete destination staging item.

#### Scenario: Cancel a running job
- **WHEN** the user cancels a running job
- **THEN** no further source items start and the job ends as cancelled after in-flight work stops or reaches a safe boundary

#### Scenario: Retry a failed job
- **WHEN** the user retries a failed job
- **THEN** the system queues only items that did not complete successfully and does not duplicate completed destinations

#### Scenario: Operation failure
- **WHEN** an item cannot be transferred
- **THEN** the job reports the error, keeps the source recoverable, and leaves no incomplete final destination item

### Requirement: Preserve local file identity and metadata
The system SHALL preserve supported local metadata, including extended attributes and resource forks, when copying items, and SHALL not recursively follow symbolic links.

#### Scenario: Copy a symbolic link
- **WHEN** a selected directory contains a symbolic link
- **THEN** the link is copied as a link without recursively traversing its target
