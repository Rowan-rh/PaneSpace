# 贡献指南

欢迎参与 PaneSpace 开发。开始前请阅读 [`AGENTS.md`](AGENTS.md)，了解仓库级架构、隐私、安全和完成要求；本地开发命令及界面检查见 [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md)。

## 开发流程

### 1. 确定改动范围并准备方案

新功能、用户可见行为变化、架构调整或 Provider 契约变化，先用 OpenSpec 创建 proposal、行为规格、必要的 design 和 tasks。先评审方案，再按任务实施。拼写修复、纯文档修改，以及不改变可观察行为或架构的小型缺陷修复可以走轻量流程；如果仍为它们建立 OpenSpec 变更，在 `.openspec.yaml` 中设置 `skip_specs: true`，不要虚构行为规格。

### 2. 从 develop 创建功能分支

仓库当前的开发集成分支名为 `develop`，并没有 `developers` 分支。先更新本地 `develop`，然后创建聚焦分支，例如 `codex/collapsible-pane-search`。不要直接在共享集成分支上开发。

### 3. 实施并持续验证

按 OpenSpec tasks 完成功能并及时勾选任务。SwiftUI 视图只负责呈现状态和提交用户意图；文件系统行为放在 State、Service 或 Provider 层。文件操作必须遵循 `AGENTS.md` 中的可恢复和冲突处理规则。

提交前运行 `swift test`、`make app` 和应用签名检查。改动可见界面时启动应用，在 macOS 上检查单面板和双面板，并覆盖相关窗口尺寸、键盘操作、无障碍名称和中英文界面。完整命令与检查表见开发文档。

### 4. 合回 develop 并创建面向 main 的合入请求

确认实现、验证和文档均无问题后，将功能分支以保留合并提交的方式合回 `develop`，然后推送 `develop`。再创建从 `develop` 合入 `main` 的合入请求。标题、变更摘要、验证结果和界面说明使用中文；按模板填写检查项，并附上可见界面变化的截图。

项目维护者可以授权助手直接操作 `main`。如获授权并选择直接路径，也要使用可追踪的提交或合并记录，不得强制推送，并用中文说明改动内容和验证结果。默认仍优先通过以 `main` 为目标的合入请求集中记录主线变更。

当前 GitHub 规则集没有强制要求 PR；PR 是本仓库约定的默认交付流程。规则集位置为 [`.github/rulesets/main.json`](.github/rulesets/main.json)。

### 5. 合入后归档

确认 OpenSpec tasks 全部完成、规格和文档与实现一致后，归档 OpenSpec 变更。若变更创建了行为规格，归档时同步主规格。不要把未实现的任务标为完成。

## 文档和架构记录

- 架构边界或数据流变化时更新 `ARCHITECTURE.md`；项目路线变化时更新 `docs/ROADMAP.md`。
- 持久架构决策写入 `docs/adr/`，并按已有 ADR 格式记录理由和后果。
- 构建、测试、签名或发布步骤变化时更新 `docs/DEVELOPMENT.md`。
- README 面向用户和首次贡献者，避免塞入实现细节。

不要提交构建产物、密钥、个人路径或复制来的专有素材。
