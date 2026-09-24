# 开发指南

## 环境要求

- macOS 26.0 或更新版本
- Xcode 26 或更新版本
- Swift 6.2 或更新版本
- 使用 Git 和 GitHub CLI 参与仓库分支及合入请求流程

## 常用命令

```bash
swift build
swift test
swift run PaneSpace
make app
open dist/PaneSpace.app
codesign --verify --deep --strict dist/PaneSpace.app
make install
```

`make install` 会先执行 `make app`，再用新构建替换“应用程序”文件夹中的 `PaneSpace.app`，并校验签名。若已安装的 PaneSpace 正在运行，命令会停止并提示先退出。需要安装到其他位置时可以指定目录，例如 `make install INSTALL_DIR=~/Applications`。安装版与 `dist/` 中的开发版共用同一个应用标识，因此偏好设置和会话也是共用的。

`make app` 会生成使用 ad-hoc 签名的开发版应用包。构建脚本会在 Info.plist 中写入受保护目录和外部卷的本地化用途说明，便于 macOS 显示系统授权提示。公开发行版本后续使用 Developer ID 签名、公证和发布自动化。

## 仓库目录

```text
Sources/PaneSpaceApp/
  Models/       文件元数据和导航值类型
  Resources/    本地化字符串和内置素材
  Services/     Provider 和 macOS 集成
  State/        应用与面板状态
  Support/      通用应用辅助代码
  Views/        SwiftUI 展示层
Tests/          单元和集成测试
docs/           产品说明、路线图和架构决策
scripts/        可重复执行的本地构建工具
```

## 本地化

英文是 Swift 源码中的默认字符串；简体中文翻译位于 `Sources/PaneSpaceApp/Resources/zh-Hans.lproj/Localizable.strings`。SwiftUI 静态文字使用标准本地化查找；可复用视图或模型中的文字使用 `L10n`，确保运行时可以本地化。

Swift Package 会处理源代码构建所需的本地化资源。`scripts/build-app.sh` 也会把支持的 `.lproj` 目录复制到独立应用包。新增语言时，同时更新 `CFBundleLocalizations` 和构建脚本中的资源复制逻辑，并在界面验证时使用该语言启动应用。

## 应用图标

可编辑的栅格源文件是 `Assets/PaneSpace-AppIcon.png`，生成的 macOS 图标文件是 `Assets/PaneSpace.icns`。修改图标时保持两者同步。应用包构建会将 `.icns` 复制到 `Contents/Resources`，写入 `CFBundleIconFile` 后再签名。

## 添加 Provider

1. 实现界面前先定义 Provider 能力。
2. 凭证保存在 Keychain，认证逻辑放在视图之外。
3. 将错误归一化为用户可采取行动的类别。
4. 让目录读取和传输操作支持异步与取消。
5. 使用确定性夹具或本地测试服务器编写 Provider 契约测试。
6. 共享契约变化时更新 `ARCHITECTURE.md` 并添加 ADR。

当前 `FileProviding` 协议保持精简并以异步方式工作。本地 actor 将阻塞的 `FileManager` 调用隔离在主线程之外。首个远程 Provider 上线前，应补充能力报告、进度和 Provider 级取消；不要把这些逻辑放入 SwiftUI 视图。

## 界面验证清单

- 启动生成的应用包。
- 检查单面板和双面板布局；影响共享面板内容时两种布局都要检查。
- 将窗口缩放到最小尺寸，检查路径栏和搜索控件的布局。
- 测试改动控件的键盘操作和 VoiceOver 名称。
- 检查长文件名和非拉丁字符。
- 检查英文与简体中文界面，包括设置窗口的关闭控件。
- 按改动范围检查空目录、权限错误、已断开的卷和大目录。

## 自动化验证

提交前至少运行 `swift test`、`make app` 和应用包签名检查。GitHub Actions 当前在针对 `main` 的推送和合入请求上运行以下自动检查：

```bash
swift test -Xswiftc -warnings-as-errors
make app
codesign --verify --deep --strict --verbose=2 dist/PaneSpace.app
```

CI 不会启动应用，也不会执行桌面界面检查；改动界面的人工 macOS 验证仍是完成条件。更完整的提案、分支、合并和归档流程见 [`CONTRIBUTING.md`](../CONTRIBUTING.md)。

## Git 分支和发布

默认从仓库实际存在的 `develop` 分支建立聚焦分支，开发完成后保留合并提交合回 `develop`，推送后创建目标为 `main` 的合入请求。仓库目前没有名为 `developers` 的分支。项目维护者授权时可以直接操作 `main`，但必须保留提交/合并记录，不得强制推送，并用中文说明改动和验证结果。详细步骤见贡献指南。

### 发布 macOS 下载包

当前应用包构建脚本使用 ad-hoc 签名，不会生成 Developer ID 签名或 Apple 公证票据。公开预览版可以发布这种构建，但发行说明必须清楚标明它未经公证，并说明首次启动可能需要在 Finder 中 Control-点按应用并选择“打开”。不要将 ad-hoc 签名描述为可信开发者签名。

发布预览版时：

1. 更新 `scripts/build-app.sh` 中的 `CFBundleShortVersionString` 和 `CFBundleVersion`，使其与发布版本一致；确认目标分支的 CI 通过，并按改动范围完成人工界面检查。
2. 在目标 macOS 架构上运行 `make app`，并执行 `codesign --verify --deep --strict dist/PaneSpace.app`。
3. 检查应用二进制架构，然后将 `.app` 打成 ZIP，并生成校验和：

   ```bash
   lipo -archs dist/PaneSpace.app/Contents/MacOS/PaneSpace
   ditto -c -k --sequesterRsrc --keepParent dist/PaneSpace.app dist/PaneSpace-0.1.0-macos-arm64.zip
   (cd dist && shasum -a 256 PaneSpace-0.1.0-macos-arm64.zip > PaneSpace-0.1.0-macos-arm64.sha256)
   ```

   文件名中的版本和架构必须与构建产物相符；不要将单架构构建标为通用版本。
4. 将版本标签指向 `main` 上对应的提交，并在 GitHub Release 上传 ZIP 与 SHA-256 文件。发行说明应写明最低 macOS 版本、支持的架构、签名/公证状态和主要变化。

正式稳定版应使用 Developer ID Application 证书签名，提交 Apple 公证并 staple 公证票据后再打包发布。仓库密钥和发布政策获批前，不要自动执行签名与公证。GitHub Actions 中名为 `PaneSpace-development` 的制品是 CI 开发包，不代替带版本号的 Release 下载包。

## 仓库分支规则

期望的轻量 `main` 规则集保存在 `.github/rulesets/main.json`。它禁止删除分支和强制推送，但当前单人维护阶段没有强制要求 PR。本文和贡献指南将 PR 作为默认交付约定；如果协作规模变化，再通过评审调整规则集。
