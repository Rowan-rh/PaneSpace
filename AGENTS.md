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

改动可见界面时必须在 macOS 启动并检查；涉及共享面板内容时，按[开发指南](docs/DEVELOPMENT.md)分别验证单面板和双面板布局。

## Documentation

- Keep `README.md` focused on users and first-time contributors.
- Update `ARCHITECTURE.md` when module boundaries or data flow changes.
- Update `docs/ROADMAP.md` when scope or release sequencing changes.
- Add an ADR for durable technical decisions and mark superseded ADRs instead of deleting them.
- Update `docs/DEVELOPMENT.md` when build, test, signing, or release steps change.

## Git 工作流

- 默认从仓库开发集成分支 `develop` 创建聚焦的功能分支；本仓库当前没有名为 `developers` 的分支。
- 开发并完成验证后，以保留合并记录的方式将功能分支合回 `develop`，推送 `develop`，并创建以 `main` 为目标的合入请求。
- 项目维护者可以授权直接操作 `main`。即使走直接路径，也要保留清晰的提交或合并历史，不得强制推送，并用中文记录变更和验证结果。
- 提交说明、合入请求标题和描述优先使用中文，简明写出改动和验证结果。
- 不提交 `.build/`、`dist/` 等构建产物、凭证或个人路径；不要把大范围格式化与功能改动混在一起。
- 合入请求需要说明用户可见行为、验证结果、界面变更截图和已知后续工作。

## Definition of done

A change is complete only when it builds, relevant tests pass, the app has been exercised for the changed workflow, documentation is current, and no known data-loss path was introduced.
