## Why

传输栏只显示已完成项目数；单个大文件复制时看不到进度，取消后也要等整个文件复制完才停止（ADR 0006 的已知限制）。

## What Changes

- 本地复制改用 `copyfile(3)`：保留与 `FileManager.copyItem` 相同的元数据、扩展属性与符号链接行为，APFS 上尽量克隆；回调统计已复制字节，任务取消时立即中止当前文件，并照常清理暂存数据。
- 任务开始前统计各项目的字节数（不跟随符号链接）；传输栏和任务列表显示“已复制 / 总量”和进度条。
- 新增 ADR 0007，并在 ADR 0003、0006 与架构文档中注明。

## Capabilities

### New Capabilities
- `transfer-byte-progress`: 传输字节进度显示与大文件中途取消。

## Impact

- 新增 `Services/LocalFileCopier.swift`；`LocalTransferService` 的复制注入点增加进度参数；`FileTransferJob`/`FileTransferItem` 增加字节字段；`FileTransferQueueModel` 统计并采样进度；`TransferCenterView` 显示进度。
