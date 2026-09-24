## Context

- `BrowserPaneModel.refresh()` 同时承担“导航后加载”和“原地刷新”两种职责，每次都会把 `columns` 重建为当前目录一列。分栏点选只修改 `tab.url`，不会调用 `refresh()`，所以唯一的 `LocalDirectoryObserver` 仍停留在首列目录上，而实际显示的最后一列没有被监听。
- `FileItem.isDirectory` 同时被用于“能否进入”和“排序时置顶”，`LocalFileProvider` 没有读取 `isPackageKey`。
- `PaneKeyboardMonitor` 只修改 `AppModel.activePane`；内容区焦点由 `BrowserPaneView`（列表）和 `ColumnBrowserView`（分栏）各自的 `@FocusState` 管理。`.onDeleteCommand` 跟随焦点，菜单命令跟随 `activePane`。
- `selectedItems` 在列表模式下从未过滤的 `items` 中取，使用 `Dictionary(grouping:)` 导致顺序不稳定。列表右键菜单挂在每一行上，并在执行前改写 `selection`。
- 视图不得直接修改文件系统（AGENTS.md）；删除必须显式确认且可恢复。

## Goals / Non-Goals

**Goals:**
- 刷新与导航在模型层清晰分离，并能用现有的 `ColumnNavigationFixture` 和临时目录测试。
- 包的判定集中在 `FileItem` 上，视图和模型通过同一个属性判断“能否进入”。
- 焦点跟随只由键盘切换面板触发。

**Non-Goals:**
- 不改变分栏视图记录前进/后退历史的现有语义。
- 不实现“展开包内容”设置；包始终按文件处理。
- 分栏视图的右键菜单仍逐项挂载（分栏选择本来就是单选），只统一目标计算和删除确认。
- 不处理 CR 中的中、低优先级问题（跨面板重命名、会话保存、性能），这些留给后续变更。

## Decisions

### 1. 拆分“导航加载”与“原地刷新”

- 新增私有的 `loadCurrentDirectory()`，按现有 `refresh()` 的逻辑以当前目录重建列。`navigate`、`goBack`、`goForward`、`activateTab`、`addTab`、`closeTab`、`toggleHiddenFiles` 以及初始化都改为调用它。
- 公开的 `refresh()` 在列表模式下与导航加载一致（只有一列）。在分栏模式、当前目录已在列中且没有未完成的导航加载时执行原地刷新：依次读取每一列的目录（遇到读取失败即停止），然后按顺序合并：
  - 某列读取失败：该列写入 `errorMessage`、清空条目，并截断它之后的列；
  - 某列的 `selectedItemID` 已不存在：清空选择并截断其后的列；
  - 某列的选中项是文件夹，但下一列目录与之不一致：截断其后的列。
  - 合并后将 `tab.url` 更新为最后一个“目录已被加载且未出错”的列目录；它变化时不写入历史，因为这是刷新导致的纠正，不是用户导航。`items` 和 `errorMessage` 取自该列。
- 放弃的方案：在刷新前记住列路径，再依次调用 `selectColumnItem` 重放。这样会反复写入历史、产生多次加载闪烁，而且与 `columnLoadTask` 的取消逻辑互相干扰。

### 2. 按显示目录集合管理监听

- `BrowserPaneModel` 维护 `[URL: LocalDirectoryObserver]`。私有方法 `syncDirectoryObservers()` 计算需要监听的目录：列表模式为当前目录，分栏模式为全部列目录；未启用监听时为空集。然后创建缺少的监听、停止多余的监听。
- 它在以下时机调用：`columns` 更新后、`setDirectoryObservationEnabled` 时、视图模式切换时。任何一个监听触发都调用 `refresh()`（原地刷新）。每个监听自带 180ms 去抖；多个目录同时变化时，`refresh()` 会取消上一次刷新任务，只保留最后一次。
- 放弃的方案：让 `LocalDirectoryObserver` 支持多个文件描述符。这样会改变已测试的服务接口，收益不大。

### 3. `FileItem.isPackage` 与 `isFolder`

- `FileItem` 增加 `isPackage`（默认 `false`，保持现有初始化调用源码兼容），并提供 `var isFolder: Bool { isDirectory && !isPackage }`。`LocalFileProvider` 读取 `.isPackageKey`。
- 所有“能否进入 / 置顶 / 显示箭头 / 大小显示 `—`”的判断都改用 `isFolder`。`isDirectory` 只保留原始文件系统语义。传输服务依赖自己的资源值读取，不受影响。
- 包的大小：`fileSizeKey` 对目录返回 nil，所以包显示“—”。与 Finder 保持一致需要递归计算，不在本次范围内。

### 4. 键盘面板切换的焦点请求

- `AppModel` 仿照 `locationEditRequest` 增加 `@Published private(set) var paneFocusRequest = 0`，只在 `cycleActivePane` 中递增。
- `BrowserPaneView` 观察它，若 `appModel.activePane == slot`：列表模式设置 `isBrowserContentsFocused = true`；分栏模式通过一个递增的 `focusToken` 参数传给 `ColumnBrowserView`，由后者设置自己的 `@FocusState`。
- 放弃的方案：在 `activePane` 变化时统一抢焦点。点击搜索框也会改变 `activePane`，这样会把刚获得的输入焦点抢走（spec：鼠标激活不抢焦点）。

### 5. 可见选择与统一的目标计算

- `selectedItems` 改为：列表模式遍历 `visibleItems`；分栏模式按列依次遍历 `displayedItems(from:)`；筛选出 `selection` 包含的项，并按 id 去重。这样顺序天然与显示一致。`selection` 本身不修改，清空搜索后恢复。
- 状态栏选中计数改用 `selectedItems.count`；`.onDeleteCommand` 与删除确认的前置条件也改用 `selectedItems`。
- `trashSelection()` 改为 `trash(_ items: [FileItem])`，保留一个 `trashSelection()` 便捷方法供 Delete 路径使用。视图持有 `pendingTrashItems: [FileItem]`，alert 由它是否为空驱动，消息带上数量（新增可本地化格式串）。
- 列表视图改用 `List` 的 `.contextMenu(forSelectionType: FileItem.ID.self, menu:primaryAction:)`：
  - SwiftUI 传入的 id 集合正好符合“右键项属于选择则为整个选择，否则为右键项”的语义；
  - 模型提供 `items(for ids: Set<FileItem.ID>) -> [FileItem]`（按显示顺序、只含可见项）；
  - 菜单中的 Quick Look、在 Finder 中显示、传输、删除都使用这组目标，不再改写 `selection`；重命名仅在目标数为 1 时可用；
  - `primaryAction` 覆盖双击；实测发现列表的键盘焦点落在可聚焦容器上而不是表格，回车不会触发 `primaryAction`，因此在容器上另加 `onKeyPress(.return)` 打开可见选择。两者的打开规则相同：单个文件夹则导航，其余逐个交给 `NSWorkspace` 打开；多目标中包含文件夹时只打开非文件夹项，避免一次导航多个目录。
  - 移除行级 `onTapGesture(count: 2)`，保留用于获取焦点的单击手势。
- `TransferActionsMenu` 改为直接接收目标 URL 列表，行级和列表级菜单共用它。`QuickLook` / `Reveal` 增加接收目标的重载。

## Risks / Trade-offs

- [`contextMenu(forSelectionType:)` 的 `primaryAction` 可能与现有 `onKeyPress` 或单击焦点手势冲突] → 实现后在单、双面板中实测双击、回车、左右方向键和多选；如有冲突，把回车处理移到 `onKeyPress(.return)`。
- [分栏原地刷新会读取多个目录，深层路径下 I/O 增多] → 分栏列数通常较少；读取在 provider actor 上串行执行，不阻塞主线程。
- [每列一个 `DispatchSource` 会占用更多文件描述符] → 只有可见面板的显示列会被监听，数量有上限（面板数 × 列数）。
- [刷新时纠正 `tab.url` 不写历史，后退可能回到已删除的目录] → 后退到不可用目录时，现有的“文件夹不可用”提示仍然适用。
