## Why

侧栏“工作区”分组目前是代码中写死的三项（个人工作区、开发 `~/Code`、下载整理），路径不存在时直接隐藏，用户无法改成自己常用的目录。用户希望在设置里自定义工作区的名称、图标和路径，用来快速打开常用位置。

## What Changes

- 新增可持久保存的自定义工作区列表。每项包含名称、图标（SF Symbol）和文件夹路径。
- 设置 > 侧栏新增“工作区”管理：添加、编辑、删除、上移/下移排序、恢复默认工作区。
- 编辑表单：
  - 名称：必填；
  - 图标：从常用图标网格中点选，或输入任意 SF Symbol 名称并实时预览；
  - 路径：可通过“选择…”打开系统文件夹选择器，也可手动输入（支持 `~`）；保存前校验必须是可访问的文件夹。
- 首次使用时，把现有三项中路径存在的作为初始列表；之后完全由用户管理，也可以恢复默认。
- 侧栏按用户配置的顺序显示工作区，点击后在活动面板中打开。路径失效的工作区置灰显示、提示不可用，并且不可选中；不再隐藏。
- “恢复所有设置”会一并恢复默认工作区。

## Capabilities

### New Capabilities
- `custom-workspaces`: 工作区的自定义配置、校验、持久化及侧栏展示。

### Modified Capabilities

## Impact

- 新增 `WorkspaceShortcut` 值类型和 `WorkspaceShortcutsModel`（`@MainActor`，基于 `UserDefaults`）；`AppModel` 持有共享实例。
- `LocalSidebarLocationProvider` 不再生成写死的工作区；`SidebarView` 从工作区模型生成侧栏项。
- `SettingsView` 侧栏页新增工作区管理与编辑表单。
- `PaneSpacePreferences.allKeys` 加入工作区键；补充中文本地化。
- 新增模型测试；无新依赖。
