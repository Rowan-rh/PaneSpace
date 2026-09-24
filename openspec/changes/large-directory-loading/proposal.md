## Why

打开包含数万个项目的文件夹时，界面会停顿数秒：5 万个文件在发布构建下读取约 2.9 秒（其中查询“种类”占 2.3 秒），在主线程排序约 2.5 秒。

## What Changes

- Provider 新增分批读取的 `contentBatches`；本地 Provider 每 1,000 项一批，离开文件夹时停止读取。
- “种类”描述按扩展名缓存（普通文件夹、同扩展名的文件/软件包/符号链接各自共享；卷和无扩展名文件单独查询）。
- `FileItem` 保存名称；新增 `FileItemSorter` 对预备好的键排序下标。
- 打开新文件夹时先显示第一批，之后最多每 250 毫秒合并一次，状态栏显示“正在载入…”；刷新当前文件夹时仍等待完整结果。
- 所有目录列表的过滤与排序在后台完成后再交给界面。
- 新增 ADR 0010。

## Capabilities

### New Capabilities
- `large-directory-loading`: 大文件夹的渐进显示与不阻塞界面的排序。

## Impact

- `FileProviding`、`LocalFileProvider`、`FileItem`、`BrowserPaneModel` 加载流程与状态栏。测量结果：读取约 0.8 秒、排序约 0.17 秒（5 万个文件，发布构建）。
