## Why

搜索框一直显示会占用路径栏和文件列表的空间，即使用户当前并未搜索。PaneSpace 已支持使用 Command-F 搜索当前面板，因此可以在闲置时收起搜索框，需要时再展开。

## What Changes

- 没有搜索词时，只显示放大镜按钮。
- 点击按钮或按 Command-F 时展开搜索框并聚焦。
- 搜索词存在时继续显示搜索框；点击清除按钮后清空搜索词并收起。
- 保持当前面板内按文件名实时过滤的行为和现有 Command-F 快捷键。

## Capabilities

### New Capabilities

- `pane-search`：规定面板内搜索的入口、过滤方式和显示状态。

### Modified Capabilities

无。仓库目前还没有已归档的主规格。

## Impact

影响 `BrowserPaneView` 中的路径栏和搜索控件、`AppModel` 的搜索焦点请求、应用菜单命令、本地化字符串，以及单面板和双面板界面检查。不涉及 Provider API、持久化数据或外部依赖。
