## Why

用户反馈了两个分栏视图的问题。第一，按左方向键时，整个分栏被重建成只剩上一级目录的一列，左侧的列全部消失，看起来像跳回了别的目录。这偏离了 folder-arrow-navigation 规格中“焦点返回上一列”的约定。第二，在分栏视图中，面板的当前目录是最深一层被选中的文件夹，所以“复制/移动到面板 N”会把项目放进用户只是选中、并未打开的文件夹；目标不可写时，只会显示系统的“没有访问许可”，让人摸不着头脑。

## What Changes

- 分栏视图中按左方向键：焦点和选择回到上一列中打开当前列的文件夹，左侧所有列和当前列保持显示，只移除当前列之后的列，不重新加载目录。首列仍按原规格返回上级目录。
- 分栏视图的传输目标改为“最深一个有选中项的列所在的目录”；没有任何选中项时，使用最后一列的目录。列表视图不变，仍为当前目录。菜单、右键菜单和拖放都使用同一目标。
- 传输开始前检查目标目录是否可写。不可写时任务失败，并显示指明目标文件夹名称的本地化提示，不再只显示系统的通用错误。

## Capabilities

### New Capabilities
- `column-keyboard-return`: 分栏视图左方向键返回上一列时保留分栏上下文。
- `pane-transfer-target`: 面板作为传输目标时的目录判定，以及目标不可写时的明确提示。

### Modified Capabilities

## Impact

- `BrowserPaneModel.returnToPreviousColumnFromKeyboard` 改为原地调整列；新增 `transferDestinationURL`。
- `AppModel.transfer` 使用新的目标目录。
- `LocalTransferService.validate` 增加可写检查，`LocalTransferError` 增加对应错误与本地化文案。
- 更新 `BrowserPaneModelTests` 中的列返回断言，新增传输目标与不可写目录测试。
