# Product definition

## Vision

PaneSpace is a fast, native, keyboard-friendly macOS file manager for people who frequently move between folders, disks, repositories, and remote servers. Its defining workflow is independent tabs inside two cooperating panes.

## Target users

- developers working across repositories and build artifacts;
- designers and media workers organizing large folder trees;
- server administrators using local and remote storage together;
- power users who want Finder-compatible behavior with denser workflows.

## Experience principles

1. **Files first.** Names and locations remain visible before decorative or secondary metadata.
2. **Native behavior.** Opening, previewing, dragging, selection, Trash, and permissions should feel consistent with macOS.
3. **Safe operations.** Long operations expose progress and conflicts; destructive operations remain recoverable when possible.
4. **Two panes, independent context.** Each pane owns its tabs, navigation history, selection, search, and sort.
5. **Providers are peers.** Local folders and remote locations use the same browsing model while accurately exposing different capabilities.
6. **No account required.** Local file management must remain fully usable without registration or a hosted service.

## Version 0.1 scope

- twelve single-pane, split, asymmetric, and grid layouts using up to four panes;
- independent tabs and history;
- favorites and mounted volumes;
- filtering, sorting, and hidden-file visibility;
- open, preview, reveal, create folder, rename, and Trash;
- a provider boundary for later remote backends.
- a settings center that distinguishes working preferences from planned capabilities.

## Explicit non-goals for 0.1

- replacing Finder as a system process;
- cloud synchronization or file hosting;
- privileged access outside normal macOS permissions;
- byte-for-byte compatibility with another file manager's workspaces;
- plug-in execution from untrusted sources.

## Success criteria for 1.0

- reliable copy and move queues with cancellation and conflict handling;
- session and workspace restoration;
- production-quality SFTP, SMB, and WebDAV providers;
- list, grid, and gallery presentation modes;
- accessible keyboard-first operation;
- signed and notarized release builds with automated update metadata;
- no unresolved known data-loss defects.
