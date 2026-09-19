# Contributing

Thank you for helping improve PaneSpace.

Read [`AGENTS.md`](AGENTS.md) first. It defines the repository-wide architecture, quality, privacy, and verification rules.

## Development workflow

1. Create a focused branch.
2. Keep platform and storage work behind a service protocol.
3. Add or update tests for file-system behavior.
4. Run `swift test` before opening a pull request.
5. Describe user-visible changes and any data-migration impact.

Architectural decisions that constrain future development should be added to `docs/adr/` using the existing records as examples.

Avoid committing build products, credentials, personal paths, or copied proprietary assets.
