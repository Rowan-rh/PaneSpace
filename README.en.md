# PaneSpace

[简体中文](README.md) · [English](README.en.md)

<img src="Assets/PaneSpace-AppIcon.png" alt="PaneSpace app icon" width="112" />

PaneSpace is a native, open-source file manager for macOS 26 and later, built for people who move frequently between projects, folders, and disks. It combines up to four cooperating panes, independent tabs in each pane, and list or multi-level column browsing. It is an independent clean-room project that uses public Apple APIs and contains no code or assets from commercial file managers.

[![Latest release](https://img.shields.io/github/v/release/Rowan-rh/PaneSpace?label=download)](https://github.com/Rowan-rh/PaneSpace/releases/latest)
[![CI](https://img.shields.io/github/actions/workflow/status/Rowan-rh/PaneSpace/ci.yml?branch=main&label=CI)](https://github.com/Rowan-rh/PaneSpace/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-black)
![License](https://img.shields.io/badge/license-MIT-blue)

## Download

**[Download PaneSpace 0.1.0 for Apple silicon](https://github.com/Rowan-rh/PaneSpace/releases/download/v0.1.0/PaneSpace-0.1.0-macos-arm64.zip)** · [All releases](https://github.com/Rowan-rh/PaneSpace/releases)

Download and extract the ZIP, move `PaneSpace.app` to Applications, and open it. The current download is for **Apple silicon Macs running macOS 26 or later**.

> The public build is ad-hoc signed and has not been notarized by Apple. If macOS blocks the first launch, Control-click `PaneSpace.app` in Finder, choose Open, and confirm the prompt. The app can access files only where macOS has granted permission to the process.

## Features

- **Multi-pane browsing:** Twelve pane arrangements, including single-pane, symmetric and asymmetric splits, and grid arrangements. Use up to four panes, each with independent tabs and navigation history; the window layout is restored on the next launch.
- **Two browsing modes:** List and multi-level column views, with back, forward, parent-folder, and left/right arrow-key folder navigation.
- **Local file operations:** Favorites and mounted volumes; search, sorting, hidden-file visibility, folder creation, rename, Trash, Quick Look, open with the default app, and Reveal in Finder.
- **Transfers between panes:** Copy, move, or drag local files between panes; inspect jobs, cancel or retry them, and choose whether name conflicts skip, keep both, or replace.
- **Personalization:** Manage sidebar workspace shortcuts, including their names, icons, and paths. Adjust appearance, content density, sidebar, and pane layout in Settings.
- **Keyboard controls:** `Command-L` enters a path, `Tab` / `Shift-Tab` switches the active pane, and `Command-W` closes the active tab or pane.
- **English and Simplified Chinese:** The interface follows the macOS language setting by default.

## Current limitations

PaneSpace currently supports local files only; SFTP, SMB, and WebDAV are planned. Security-scoped bookmark persistence for sandboxed distribution is not implemented, so file access depends on the permissions macOS grants to the running process. See the [roadmap](docs/ROADMAP.md) for planned work.

## Run from source

Requires macOS 26 or later and Xcode 26 or later, or a compatible Swift 6.2 toolchain.

```bash
swift run PaneSpace
```

Build and open a standalone app bundle:

```bash
make app
open dist/PaneSpace.app
```

Run the test suite:

```bash
swift test
```

## Contributing

Issues and pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) and [AGENTS.md](AGENTS.md) before making a change. More information: [product definition](docs/PRODUCT.md) · [architecture](ARCHITECTURE.md) · [development guide](docs/DEVELOPMENT.md) · [security policy](docs/SECURITY.md) · [roadmap](docs/ROADMAP.md).

## License

PaneSpace is open source under the [MIT License](LICENSE).
