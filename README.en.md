# PaneSpace

[简体中文](README.md) · [English](README.en.md)

<img src="Assets/PaneSpace-AppIcon.png" alt="PaneSpace app icon" width="112" />

PaneSpace is a clean-room, open-source macOS file manager focused on tabs and side-by-side workflows. It uses only public Apple APIs and does not contain code or assets from any commercial file manager.

![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-black)
![Swift](https://img.shields.io/badge/Swift-6.2%2B-orange)
![License](https://img.shields.io/badge/license-MIT-blue)

## Current features

- Native SwiftUI and AppKit interface
- Twelve one-pane, split, asymmetric, row, column, and grid layouts
- Multiple tabs in each pane
- List and multi-level column browsing modes
- Back, forward, and parent-folder navigation
- Favorites and mounted-volume sidebar
- Search and sorting
- Hidden-file toggle
- Create folders and rename items
- Move items to Trash
- Quick Look with the Space key
- Open files with their default application
- Reveal files in Finder
- Local file-provider abstraction for future remote backends
- Native settings center with live appearance, density, sidebar, address-bar, and pane controls
- English and Simplified Chinese interface localization; the app follows the macOS language setting by default
- Clearly marked configuration shells for planned search, extensions, hotkeys, and remote providers

## Requirements

- macOS 26 or newer
- Xcode 26 or newer, or a compatible Swift 6.2 toolchain

## Run from source

```bash
swift run PaneSpace
```

Run tests:

```bash
swift test
```

Build a standalone application bundle:

```bash
make app
open dist/PaneSpace.app
```

The generated app is ad-hoc signed for local development. macOS may ask for permission when a folder is accessed for the first time; PaneSpace uses system-provided security-scoped bookmarks to retain access to folders selected by the user.

## Roadmap

1. Drag and drop, copy and move queues, conflict handling
2. Grid and gallery views
3. Saved workspaces and session restoration
4. SFTP, SMB, and WebDAV providers
5. Archive browsing and compression
6. Git status decorations and Finder extension
7. Plug-in API and command palette

## Project documentation

- [Product definition](docs/PRODUCT.md)
- [Architecture](ARCHITECTURE.md)
- [Development guide](docs/DEVELOPMENT.md)
- [Roadmap](docs/ROADMAP.md)
- [Architecture decisions](docs/adr)
- [Security policy](docs/SECURITY.md)
- [Agent and contributor rules](AGENTS.md)

## Contributing

Issues and pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) and [AGENTS.md](AGENTS.md) before making a change. Please keep provider-specific logic out of views and add tests for file operations.

## License

PaneSpace is available under the MIT License.
