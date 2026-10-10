## Why

功能清单把“多选与范围选择（访达式）”列为未完成。实测发现：列表视图的鼠标 Shift/Command 点按由系统表格处理，可以正常多选；但键盘焦点落在外层可聚焦容器上，上下方向键、Shift+方向键和 Command-A 都不起作用。分栏视图的每一列只能单选，Command/Shift 点按也不会扩展选择。

## What Changes

- 列表视图：上下方向键移动选择，Shift+上下方向键从锚点扩展或收缩连续选择，Command-A 选中全部可见项目。
- 分栏视图：同一列内支持 Command 点按逐项添加/取消、Shift 点按选择连续范围，以及 Shift+上下方向键扩展选择。选中多个项目时不展开子列；只剩一个文件夹时恢复展开。Command-A 选中当前列全部项目。
- 选择计算放在独立的值类型中，由 `BrowserPaneModel` 调用，便于单元测试。

## Capabilities

### New Capabilities
- `multi-item-selection`: 列表和分栏视图中的访达式多选、范围选择与键盘扩展选择。

## Impact

- 新增 `Models/ItemSelection.swift`；`BrowserPaneModel` 新增键盘移动、扩展、全选和分栏修饰键点按方法。
- `BrowserPaneView` 的列表和分栏视图增加按键处理，分栏行根据修饰键调用模型。
- 新增单元测试；无新依赖，无持久化格式变化。
