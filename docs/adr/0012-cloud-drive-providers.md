# ADR 0012：云盘通过各自的 Web API 接入

- 状态：已接受
- 日期：2026-10-16

## 背景

用户要求在 PaneSpace 中连接 Google 云端硬盘和百度网盘。两者都不提供 SMB、WebDAV 或 SFTP：Google 云端硬盘只有 Drive v3 REST API，百度网盘只有 xpan 开放平台 API，两者都以 OAuth 2.0 授权，并要求调用方是在各自平台注册过的应用。

[ADR 0001](0001-provider-boundary.md) 要求存储差异留在 Provider 之后，[ADR 0004](0004-async-provider-primitives.md) 已把 Provider 原语改为异步。现有面板、标签页、历史和传输队列都以 `URL` 表示位置。

## 决定

1. **位置仍用 URL 表示。** 云盘位置使用自定义 scheme：`panespace-gdrive://<账户 ID>/<路径>` 与 `panespace-baidupan://<账户 ID>/<路径>`，文件夹带结尾斜杠。面板、标签页、会话持久化和历史无需新的位置类型。`CloudLocation` 负责解析与构造；比较路径时带上 scheme 和账户，不同云盘的同名路径不会混淆。
2. **按 scheme 路由 Provider。** `RoutingFileProvider` 把 `file` URL 交给本地 Provider，把云盘 URL 交给 `CloudProviderRegistry` 中对应账户的 `RemoteFileProviding`。每个面板仍各自持有本地 Provider，互不排队。`RemoteFileProviding` 在共享原语之外增加单项查询、下载、上传、盘内移动和容量查询。
3. **传输队列与存储类型解耦。** 队列依赖 `FileTransferServicing` 协议；纯本地传输继续走 `LocalTransferService`，涉及云盘的走 `CloudTransferService`。云盘传输沿用本地的安全规则：先以隐藏的暂存名完整写入再改名发布；“替换”只在新副本完成后把旧项目移入废纸篓或云盘回收站；移动在复制完成后才删除源项目；同一云盘内的移动交给服务端完成，不传输数据。不跟随符号链接，不上传 `.DS_Store`。
4. **路径与 ID 的映射留在 Provider 内。** 百度网盘按路径寻址；Google 云端硬盘按 ID 寻址且允许同名，Provider 维护路径到 ID 的映射，列表中重名的项目追加 ID 前缀区分。Google 自有格式（文档、表格、幻灯片、绘图）下载时导出为 docx、xlsx、pptx、pdf。
5. **授权方式。** Google 使用桌面应用推荐的回环地址重定向（仅监听 `127.0.0.1`）加 PKCE；百度使用设备码模式，不需要登记回调地址。访问令牌与刷新令牌、应用凭据只存钥匙串；偏好设置只保存账户 ID、服务、显示名和起始路径。百度每次刷新都会换发新的刷新令牌，必须立即保存；刷新被拒绝时提示用户重新连接，不重试旧令牌。
6. **应用凭据不进仓库。** 构建可通过环境变量把凭据写入 Info.plist，用户只需登录；未提供时，用户在“连接服务器”中填写一次自己注册的凭据。
7. **云盘操作记录但不撤销。** 云盘回收站无法按路径定位，记录中只要涉及云盘位置，`OperationUndoService.canUndo` 就返回 false。删除确认文案说明删除的是云盘中的项目，而非移入 Mac 废纸篓。

## 后果

- 面板、标签页、会话和传输队列无需区分存储类型即可浏览和复制云盘内容。
- 打开和快速查看云盘文件需要先下载到缓存目录（`~/Library/Caches/org.panespace.app/Cloud`），启动时清空。
- 云盘没有文件系统事件，只在导航、刷新和传输完成后重新读取。
- 百度开放平台只允许第三方应用访问授权目录（默认 `/apps/<应用名>`，即“我的应用数据”），未审核应用每小时调用次数和用户数都受严格限制；这是平台规则，PaneSpace 无法绕过。Google 的 `drive` 权限属于受限范围，应用未经 Google 验证时，登录页会显示未验证警告，“测试”发布状态下刷新令牌 7 天过期。
- SFTP、SMB、WebDAV 将来可以按同一路由与传输协议接入。
