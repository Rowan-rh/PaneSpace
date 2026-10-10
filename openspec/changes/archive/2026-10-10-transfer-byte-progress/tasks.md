## 1. 实现

- [x] 1.1 `LocalFileCopier`：copyfile 复制、字节回调、取消、错误归一化、字节统计。
- [x] 1.2 `LocalTransferService` 与 `FileTransferQueueModel` 接入测量与进度采样。
- [x] 1.3 传输栏与任务列表显示字节进度；中文本地化。
- [x] 1.4 测试：元数据保留（原有测试）、字节统计不跟随链接、取消即停止、任务完成时字节总量正确。
- [x] 1.5 ADR 0007，更新 ADR 0003/0006、架构文档、路线图与功能清单。

## 2. 验证

- [x] 2.1 `swift test`、`make app`、签名检查、`openspec validate transfer-byte-progress --strict`。
- [x] 2.2 在 macOS 上实测。

验证记录：`swift test -Xswiftc -warnings-as-errors` 共 100 项通过；`make app` 与严格签名检查通过。在隔离配置的开发版双面板中，从挂载的只读磁盘映像把 769.4 MB 的应用复制到本地临时文件夹：传输栏从 8.6 MB 持续更新到完成；再次复制到 292.8 MB 时点按“取消”，任务立即显示“已取消”，目标文件夹为空；点按“重试”后完整复制到 769.4 MB / 769.4 MB。
