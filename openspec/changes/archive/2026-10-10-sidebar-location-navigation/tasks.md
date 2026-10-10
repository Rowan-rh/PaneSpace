## 1. 实现与验证

- [x] 1.1 在 `AppModel` 中增加 `openSidebarLocation` 与 `syncSidebarSelection`，并用 `SidebarNavigationTests` 验证打开、重复打开不写历史、高亮同步和保留等价项。
- [x] 1.2 把侧栏行改为可选择标签，由选择变化触发打开，并在当前位置、活动面板或侧栏内容变化时同步高亮。
- [x] 1.3 运行 `swift test`、`make install`、严格签名检查和 `openspec validate sidebar-location-navigation --strict`；在已安装的 App 中点击行内空白处打开“下载”和“桌面”，离开后再次点击“桌面”仍能打开，高亮跟随当前位置。

验证记录：`swift test` 共 73 项通过；`make install` 完成安装并通过签名检查；上述界面操作均已在 `/Applications/PaneSpace.app` 中实测通过。
