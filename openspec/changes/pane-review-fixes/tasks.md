## 1. 包按文件处理

- [x] 1.1 为 `FileItem` 增加 `isPackage` 与 `isFolder`，`LocalFileProvider` 读取 `.isPackageKey`；在 `LocalFileProviderTests` 中用临时 `.app` 目录验证 `isPackage == true`、`isFolder == false`。
- [x] 1.2 把进入目录、排序置顶、分栏追加列、列行箭头和大小显示的判断改为 `isFolder`；用模型测试验证右方向键不进入包、分栏选择包不追加列，以及排序顺序为 `Zeta`、`Alpha.app`、`beta.txt`。

## 2. 分栏刷新与目录监听

- [x] 2.1 拆分 `loadCurrentDirectory()`（导航重建）与 `refresh()`（分栏原地刷新），并更新所有导航入口；用测试验证分栏 A→B→C 在 A 变化后刷新时三列和选择都保留，显式导航后只剩一列。
- [x] 2.2 实现原地刷新的截断规则（选中项消失、列目录不可访问），并在不写历史的前提下纠正 `tab.url`；用临时目录测试删除中间目录后的列与位置。
- [x] 2.3 用按目录管理的监听集合替换单个监听，列变化、视图模式切换和启用状态变化时同步；用临时目录测试最后一列目录中的文件变化会刷新该列，被收起的列不再触发刷新。

## 3. 键盘切换面板的焦点跟随

- [x] 3.1 在 `AppModel` 增加只由 `cycleActivePane` 递增的 `paneFocusRequest`；用 `AppSessionTests` 验证 Tab 切换会递增它，而直接设置 `activePane` 不会。
- [x] 3.2 `BrowserPaneView` 与 `ColumnBrowserView` 响应该请求，将焦点移到活动面板的内容区；构建后在双面板中实测 Tab 后的方向键和 Delete 都作用于新面板，点击另一面板的搜索框时焦点仍在搜索框。

## 4. 选择范围与右键菜单

- [x] 4.1 让 `selectedItems` 只包含可见选中项并按显示顺序排列，新增 `items(for:)`；用测试验证过滤隐藏选中项后 `selectedItems` 为空、清空搜索后恢复，以及多选顺序跟随排序。
- [x] 4.2 将删除改为 `trash(_:)` 并保留 `trashSelection()`；状态栏计数和 `.onDeleteCommand` 改用可见选择；视图用 `pendingTrashItems` 驱动带数量的确认提示，并补充中文本地化；用模型测试验证 `trash(_:)` 只处理传入的项。
- [ ] 4.3 列表视图改用 `.contextMenu(forSelectionType:menu:primaryAction:)`，菜单操作使用目标集合、多目标时禁用重命名，主操作覆盖双击与回车；`TransferActionsMenu`、Quick Look、在 Finder 中显示改为接收目标。在单、双面板中实测多选后右键删除（带确认）、右键未选中项、双击和回车打开文件夹/文件/应用。
- [ ] 4.4 分栏视图的右键删除走同一确认流程；实测后确认不再有未经确认的删除入口。

## 5. 集成验证

- [x] 5.1 运行 `swift test`、`make app`、`codesign --verify --deep --strict dist/PaneSpace.app` 和 `openspec validate pane-review-fixes --strict`，全部通过且没有新警告。
- [ ] 5.2 启动当前构建，在单面板和双面板的列表与分栏视图中回归左右方向键导航、搜索、传输和删除，截取界面变更截图供合入请求使用。

验证记录：`swift test` 共 64 项全部通过，`make app`、严格签名检查和 `openspec validate --strict` 均通过。已在当前构建中实测：分栏 A→B→C 展开后，首列和末列目录的外部变化会原地刷新且不折叠；`Tool.app` 显示为文件，选中后不追加列；双面板中 Tab / Shift-Tab 后焦点框跟随，列表和分栏的方向键作用于新活动面板；面板 2 无选择时 Delete 不弹确认，切回面板 1 后弹出“‘b.txt’将被移到废纸篓”；搜索过滤掉选中项后状态栏不再计数，清空后恢复；双击与回车进入文件夹。实测发现回车不会触发 `primaryAction`，已改为在列表容器上处理回车并复测通过。右键菜单（多选范围、未选中项、删除确认、分栏右键删除）无法用自动化工具发出右键，需要人工复核。
已知限制：通过 Tab 让列表获得焦点、但尚未点击任何行时，上下方向键和 ⌘A 不会移动选择（焦点在列表外层容器上，这是本次变更之前就存在的行为），留待后续变更处理。
