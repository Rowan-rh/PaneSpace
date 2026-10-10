## Context

- `returnToPreviousColumnFromKeyboard` 当前调用 `navigate(to: parentColumn.directory, restoringSelectionAt:)`，由导航加载把分栏重建为一列。
- 分栏中，`selectColumnItem` 选择文件夹时把 `tab.url` 设为该文件夹；`AppModel.transfer` 直接使用目标面板的 `currentURL`，所以目标变成被选中的文件夹。
- `LocalTransferService.validate` 只检查路径关系，不检查权限；写入失败时把 `CocoaError` 的系统文案原样显示出来。

## Goals / Non-Goals

**Goals:** 左方向键只调整模型中的列与选择；传输目标可以在模型层单测；不可写目录在复制前就失败。

**Non-Goals:** 不改变 `currentURL` 在分栏中的语义（路径栏、新建文件夹、状态栏仍沿用它），也不实现剪切/复制/粘贴快捷键。这些留给快捷键变更统一处理。

## Decisions

1. **原地返回上一列**：截断 `columns` 到 `columnIndex + 1`，清空当前列的 `selectedItemID`，`selection = [parentFolder.id]`，`items` 取当前列内容，并通过 `updateActiveTabURL(parentFolder.url)` 保持“选中文件夹即当前位置”的现有语义（地址已相同时不写历史）。取消进行中的列加载，并同步目录监听。放弃的方案：调用 `selectColumnItem(parentFolder)`。它会重新加载当前列并闪烁加载状态。
2. **`transferDestinationURL`**：列表视图返回 `currentURL`；分栏视图从后往前找第一个 `selectedItemID != nil` 的列，返回其目录，否则返回最后一列的目录，列为空时回退到 `currentURL`。`AppModel.transfer` 改用它。拖放也经由 `AppModel.transfer`，因此自动一致。
3. **可写检查**：`validate` 在路径检查之后调用 `FileManager.isWritableFile(atPath:)` 检查规范化后的目标目录，不可写则抛出新的 `LocalTransferError.destinationNotWritable(name:)`。检查放在 `validate` 中，队列在处理每一项前都会调用它，且它早于创建临时项。
