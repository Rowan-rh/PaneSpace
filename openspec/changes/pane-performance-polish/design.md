## Context

- `visibleItems` 与 `displayedItems(from:)` 是计算属性，每次访问都要执行 O(n log n) 的 `localizedStandardCompare` 排序。`AppModel` 把任一面板的 `objectWillChange` 转发给所有视图，于是一次按键会让两个面板都重新渲染。
- `loadCurrentDirectory` 在加载开始时就把 `isLoading` 设为 true，视图据此把内容透明度设为 0 并显示加载提示。

## Goals / Non-Goals

**Goals:** 让显示结果的计算与渲染次数脱钩；去掉不必要的加载闪烁；保持现有测试依赖的 `isLoading` 语义。

**Non-Goals:** 不移除 `AppModel` 的变化转发（工具栏和菜单依赖它），不改为后台线程排序。缓存之后，重复渲染的成本已足够低；如果之后仍有瓶颈，再单独处理。

## Decisions

1. **按内容版本缓存**：`BrowserColumn.items` 在 `didSet` 中刷新一个 `itemsRevision`（UUID）；面板的 `items` 同样维护一个版本。缓存键是（版本、搜索词、排序字段、方向），缓存值是显示结果，存放在不参与发布的字典中。搜索词或排序变化时清空缓存，条目过多时整体清空，避免无限增长。放弃的方案：把显示结果存成 `@Published` 属性并在各个 `didSet` 中重算。这样需要在所有修改 `columns[i].items` 的地方同步更新，容易遗漏。
2. **接口**：新增 `displayedItems(in column: BrowserColumn)`，并把 `visibleItems` 改为读取缓存。原来的 `displayedItems(from:)` 保留给无版本的数组使用，但视图和键盘路径不再调用它。
3. **延迟加载提示**：新增 `@Published private(set) var showsLoadingIndicator`。导航加载开始时启动一个 200 毫秒的任务，届时仍在加载才置为 true；加载结束（成功、失败或被取消）时置为 false。刷新当前已显示的目录时不启动该任务。视图的透明度、命中测试和加载提示都改用它；键盘守卫仍使用 `isLoading`。
5. **选择跟随滚动**：分栏列表在 `selectedItemID` 变化时用 `ScrollViewReader.scrollTo` 让选中项保持可见。这是实测中发现的问题：选中项移出可见区域后没有反馈，看起来像卡住。
4. **焦点框**：在 `FileListView` 的 `List` 和 `ColumnBrowserView` 的 `ScrollView` 上使用 `.focusEffectDisabled()`。

## Risks / Trade-offs

- [加载期间显示旧内容，用户可能点击到旧条目] → 键盘操作仍被 `isLoading` 拦截；点击选中的旧条目会在新内容到达后被选择求交清除。
- [缓存键使用 UUID，版本更新有少量开销] → 相比排序成本可以忽略。
