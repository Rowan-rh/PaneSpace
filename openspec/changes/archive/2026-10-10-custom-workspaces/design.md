## Context

- 工作区现在由 `LocalSidebarLocationProvider.snapshot()` 写死生成，并过滤掉不存在的路径。
- `SidebarView` 通过列表选中触发 `AppModel.openSidebarLocation`（上一个变更），并按当前位置同步高亮。
- 设置以 sheet 形式展示在 `ContentView` 中，能取到 `AppModel` 环境对象；各设置页使用 `@AppStorage` 保存简单值。

## Goals / Non-Goals

**Goals:** 工作区数据是可测试的值类型，校验在模型层完成；侧栏与设置共享同一个实时更新的来源；失效检查不阻塞主线程。

**Non-Goals:** 不做侧栏内的添加、右键编辑或拖动排序（用户选择只在设置里管理）；不做沙盒所需的安全作用域书签。

## Decisions

1. **数据与存储**：`WorkspaceShortcut { id: UUID, name, systemImage, path }` 实现 `Codable`、`Hashable`、`Sendable`。`WorkspaceShortcutsModel`（`@MainActor ObservableObject`）以 JSON 形式保存到 `UserDefaults` 的 `workspaceShortcuts` 键。键不存在时生成默认项，解码失败时同样回退到默认项。`AppModel` 用同一个 `UserDefaults` 持有它，因此测试可以注入独立的 suite。放弃的方案：对数组使用 `@AppStorage`。它不支持自定义结构，也不便于在模型层测试。
2. **路径保存**：保存标准化后的绝对路径。用户输入的 `~` 和 `file://` 通过现有的 `LocalPathResolver` 解析，它本身就会校验路径存在、是文件夹且可读取。
3. **可用性**：模型维护 `unavailableIDs: Set<UUID>`。列表变化、应用回到前台、卷挂载或推出、点击工作区以及活动面板加载失败时，通过 `Task.detached` 批量检查每个路径是否为可访问的文件夹，完成后回到主线程发布结果，避免网络卷拖慢主线程。
4. **侧栏**：`LocalSidebarLocationProvider` 的工作区列表改为空，并删除相关代码。`SidebarView` 把工作区映射为 id 为 `workspace:<uuid>` 的 `SidebarLocation`；失效项不带选择标签（因此不可选中，已有的选中也会被清除），显示为次要颜色并带有提示。实测发现，`.selectionDisabled()` 在行失效时不会清除残留的选中高亮，因此没有采用。`navigableLocations` 只包含可用项。
5. **图标校验**：使用 `NSImage(systemSymbolName:accessibilityDescription:) != nil` 判断图标是否有效。常用图标网格为约 24 个预置 SF Symbol。
6. **恢复设置**：`PaneSpacePreferences.allKeys` 加入 `workspaceShortcuts`。高级页执行恢复后调用 `workspaceShortcuts.reload()`，让内存状态与已清空的偏好保持一致。

## Risks / Trade-offs

- [默认项名称在生成时按当前语言本地化，并作为用户数据保存，之后切换语言不会跟着变] → 用户可以自行改名，或恢复默认。
- [保存绝对路径后，换用户或换机器会失效] → 失效项会置灰提示，用户可以编辑修复。
