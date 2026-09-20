# Development guide

## Requirements

- macOS 26.0 or newer
- Xcode 26 or newer
- Swift 6.2 or newer
- Git and GitHub CLI for repository workflows

## Common commands

```bash
swift build
swift test
swift run PaneSpace
make app
open dist/PaneSpace.app
```

`make app` produces an ad-hoc signed development bundle. Public releases will use Developer ID signing, notarization, and release automation added in a later milestone.

## Repository layout

```text
Sources/PaneSpaceApp/
  Models/       File metadata and navigation values
  Resources/    Localized strings and bundled assets
  Services/     Providers and macOS integrations
  State/        Observable application and pane state
  Support/      Shared application helpers
  Views/        SwiftUI presentation
Tests/          Unit and integration tests
docs/           Product, roadmap, and architecture decisions
scripts/        Repeatable local build tooling
```

## Localization

English source strings are the development language. Simplified Chinese translations live in `Sources/PaneSpaceApp/Resources/zh-Hans.lproj/Localizable.strings`. Static SwiftUI labels use the standard localization lookup; strings passed through reusable views or model values use `L10n` so they remain localizable.

The Swift package processes localization resources for source builds. `scripts/build-app.sh` also copies supported `.lproj` directories into the standalone application bundle. When adding a language, update both `CFBundleLocalizations` and the copied resource directories in that script, then launch the built app with that language during UI verification.

## Application icon

The editable raster master is `Assets/PaneSpace-AppIcon.png`; the generated macOS icon family is `Assets/PaneSpace.icns`. Keep both files in sync when the icon changes. The standalone bundle build copies the `.icns` file into `Contents/Resources` and records it in `CFBundleIconFile` before signing.

## Adding a provider

1. Define the provider's capabilities before implementing UI.
2. Keep credentials in Keychain and authentication outside view code.
3. Normalize provider errors into user-actionable categories.
4. Make listing and transfer operations cancellable.
5. Write provider contract tests using a deterministic fixture or local test server.
6. Update `ARCHITECTURE.md` and add an ADR when the provider changes shared contracts.

The current `FileProviding` protocol is deliberately small and synchronous for the local MVP. Do not force remote I/O into this shape. The protocol should evolve to an asynchronous capability-oriented interface before the first remote provider lands.

## UI verification checklist

- launch the generated application bundle;
- check single-pane and dual-pane layouts;
- resize the window to its minimum dimensions;
- test keyboard navigation and VoiceOver labels for changed controls;
- verify long file names and non-Latin names;
- verify the English and Simplified Chinese interfaces, including the settings close controls;
- test empty folders, permission failures, disconnected volumes, and large directories.

## Release outline

1. Run the full test suite and UI smoke checks.
2. Build the Release configuration.
3. Sign with a Developer ID Application certificate.
4. Submit for Apple notarization and staple the ticket.
5. Create a versioned Git tag and GitHub release.
6. Publish checksums and release notes.

The signing and notarization steps are intentionally not automated until repository secrets and a release policy are approved.

## Repository policy

The desired lightweight `main` branch ruleset is stored in `.github/rulesets/main.json`. It prevents branch deletion and force pushes without requiring pull requests for the current single-maintainer phase. If collaboration expands, add required pull requests and CI checks through a new reviewed policy change.
