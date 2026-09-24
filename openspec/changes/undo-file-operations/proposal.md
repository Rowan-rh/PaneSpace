## Why

路线图 0.2 列出“在平台允许的范围内支持撤销”。操作历史已经记录了逆转所需的位置信息，但用户还无法撤销误操作。

## What Changes

- 新增 `OperationUndoService`，按记录撤销：重命名改回、从废纸篓放回、空的新文件夹移到废纸篓、复制的副本移到废纸篓并恢复被替换项、移动放回原项目并将副本移到废纸篓。只使用可恢复步骤，原位置被占用或项目已不存在时停止并说明；部分成功时报告数量。
- “编辑 > 撤销”（⌘Z）撤销最近一条未撤销的操作，菜单标题显示操作名称；文本框获得焦点时 ⌘Z 仍撤销文字。“重做”只用于文字编辑。
- 操作历史中每条可撤销记录提供“撤销”按钮；撤销后标记“已撤销”。
- 撤销后刷新位于受影响文件夹内的面板，标签页跟随被改回的名称。
- 修复：重命名 `/tmp`、`/var` 下已打开的文件夹后，标签页仍指向旧路径（`standardizedFileURL` 只在路径存在时去掉 `/private`）。
- 新增 ADR 0009。

## Capabilities

### New Capabilities
- `undo-file-operations`: 以可恢复步骤撤销已记录的文件操作。

## Impact

- 新增 `Services/OperationUndoService.swift`；`AppModel` 新增撤销入口与面板刷新；`BrowserPaneModel` 新增 `followRename` 与 `comparablePath`；`PaneSpaceApp` 替换撤销菜单组；`OperationHistoryView` 增加撤销按钮。
