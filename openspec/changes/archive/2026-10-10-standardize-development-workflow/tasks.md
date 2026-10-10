## 1. 对齐贡献者文档

- [x] 1.1 更新 `AGENTS.md`，明确仓库级要求并链接到中文开发验证清单；检查每类要求只有一个权威说明位置。
- [x] 1.2 将 `CONTRIBUTING.md` 改为中文并写清分支创建、OpenSpec 评审、实施、验证、合并、推送、PR 和归档流程；检查小型修复的轻量例外。
- [x] 1.3 将 `docs/DEVELOPMENT.md` 改为中文，对齐 CI 实际命令并区分自动检查与手动 macOS UI 检查；逐条对照 `.github/workflows/ci.yml`。
- [x] 1.4 将 `.github/pull_request_template.md` 改为中文并收集变更摘要、测试和界面验证证据；检查不与 `AGENTS.md` 或 CI 要求冲突。

## 2. 验证流程规范

- [x] 2.1 对照 `.github/rulesets/main.json` 和仓库现有分支，验证文档使用实际的 `develop`/`main` 名称、保留直接操作 main 的授权，并未声称 PR 已由保护规则强制。
- [x] 2.2 运行 `openspec validate --strict` 并检查文档链接和交叉引用；验证四份文档说明同一套流程。
