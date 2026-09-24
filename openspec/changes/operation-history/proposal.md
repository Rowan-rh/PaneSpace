## Why

传输任务只保存在内存中，重启后无法查看做过哪些复制、移动、重命名或删除；下一步的撤销功能也需要可靠的操作记录。

## What Changes

- 新增持久化操作历史：复制/移动（每次运行一条）、单项与批量重命名、移到废纸篓、新建文件夹都会生成记录，包含时间、结果、错误信息和每个项目的原位置、结果位置、进入废纸篓后的位置、被“替换”移入废纸篓的原有项目。
- `FileProviding.moveToTrash` 与本地传输服务返回项目在废纸篓中的实际位置。
- 历史保存为带版本号的 JSON，最多 200 条；在“传输 > 操作历史…”（⌃⌘H）和传输栏的“传输任务”按钮打开，窗口同时显示本次会话的任务（可取消/重试）与历史记录，并可清除历史。
- 新增 ADR 0008。

## Capabilities

### New Capabilities
- `operation-history`: 文件操作记录的生成、持久化与查看。

## Impact

- 新增 `OperationRecord`、`OperationHistoryStore`、`OperationHistoryModel`、`OperationHistoryView`；`AppModel` 持有历史并连接队列和各面板；`TransferCenterView` 的会话任务表单并入历史窗口。
- 所有测试替身的 `moveToTrash` 改为返回 `URL?`。
