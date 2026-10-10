## Why

贡献指南、仓库级规则、开发说明、CI 和合入请求模板分别描述了开发流程的不同部分，步骤和检查门槛分散，容易出现理解不一致。需要明确文档职责、OpenSpec 使用范围，以及从开发分支到 main 的合入记录方式。

## What Changes

- 规定默认流程：从 `develop` 创建功能分支；完成并验证后以合并提交合回 `develop`；推送 `develop`，再创建目标为 `main` 的合入请求。
- 记录项目负责人已允许助手在需要时直接操作 `main`；无论走 PR 还是直接合并，都保留提交/合并历史，并用中文说明变更。
- 明确新功能、用户可见行为变化、架构或 Provider 契约变化必须先走 OpenSpec；纯文档和不改变行为的小修复可以使用轻量流程。
- 明确 `AGENTS.md`、`CONTRIBUTING.md`、`docs/DEVELOPMENT.md`、CI 和 PR 模板各自负责的内容，避免重复清单互相漂移。
- 统一测试、应用打包、签名检查和 macOS 界面检查的完成要求，并将相关开发说明改为中文。

## Capabilities

### New Capabilities

无。本变更只调整贡献者文档和流程，不改变 PaneSpace 的用户可见行为。

### Modified Capabilities

无。

本变更在 `.openspec.yaml` 中设置 `skip_specs: true`，因为它只涉及文档和流程规范。

## Impact

影响 `AGENTS.md`、`CONTRIBUTING.md`、`docs/DEVELOPMENT.md` 和 `.github/pull_request_template.md`。不改应用代码、CI 执行逻辑、依赖或用户数据。
