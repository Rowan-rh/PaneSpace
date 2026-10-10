## Why

路线图 0.3 与功能清单都列出“批量重命名”。目前选中多个项目时“重命名…”不可用，用户只能逐个改名。

## What Changes

- 选中多个项目时，右键菜单和“文件 > 重命名…”打开批量重命名表单；选中一个项目时仍使用原来的单项重命名。
- 支持三种方式：替换文本（可忽略大小写、可选择是否包括扩展名）、在名称前后添加文本、按“名称 + 分隔符 + 序号”格式化（起始编号与位数可调）。默认保留扩展名。
- 表单实时预览每一项的新名称，并标出无效名称、本批次内重名、与文件夹中其他项目冲突（按 APFS 默认的大小写与 Unicode 规范化不敏感方式比较）。存在问题或没有任何变化时禁用“重命名”。
- 执行时先把每项改成唯一临时名，再改为最终名，因此名称互换和仅大小写变化都不会冲突；任一步失败时撤回已完成的步骤，并在面板内显示错误。
- 改名后选中新名称；刷新后按标准化路径恢复选择，修复文件夹改名后选择丢失的问题。

## Capabilities

### New Capabilities
- `batch-rename`: 多项目重命名规则、冲突检查、预览与可回滚的执行。

## Impact

- 新增 `Models/BatchRename.swift`、`Services/BatchRenamer.swift`、`Views/BatchRenameView.swift`。
- `BrowserPaneModel` 新增 `requestRename`、`batchRenamePlan`、`applyBatchRename`；刷新后的选择改为按路径匹配。
- 应用菜单“文件”新增“重命名…”；设置 > 扩展中的“批量重命名”不再标为计划中。
- 通过现有 `FileProviding.rename` 执行，未来的远程 Provider 可直接复用；无持久化格式变化。
