# PaneSpace

[简体中文](README.md) · [English](README.en.md)

<img src="Assets/PaneSpace-AppIcon.png" alt="PaneSpace 应用图标" width="112" />

PaneSpace 是一款面向 macOS 26+ 的原生开源文件管理器，适合经常在项目、文件夹和磁盘之间切换的工作流。它提供最多四个协作分栏、每栏独立标签页，以及列表和多级分栏浏览。项目采用 clean-room 独立实现，仅使用 Apple 公开 API，不包含商业文件管理器的代码或素材。

[![最新版本](https://img.shields.io/github/v/release/Rowan-rh/PaneSpace?label=下载)](https://github.com/Rowan-rh/PaneSpace/releases/latest)
[![CI](https://img.shields.io/github/actions/workflow/status/Rowan-rh/PaneSpace/ci.yml?branch=main&label=CI)](https://github.com/Rowan-rh/PaneSpace/actions/workflows/ci.yml)
![平台](https://img.shields.io/badge/platform-macOS%2026%2B-black)
![许可证](https://img.shields.io/badge/license-MIT-blue)

## 下载

**[下载 PaneSpace 0.1.1（Apple silicon）](https://github.com/Rowan-rh/PaneSpace/releases/download/v0.1.1/PaneSpace-0.1.1-macos-arm64.zip)** · [查看所有版本](https://github.com/Rowan-rh/PaneSpace/releases)

下载并解压 ZIP，将 `PaneSpace.app` 拖到“应用程序”文件夹后启动。当前下载包适用于 **macOS 26 或更高版本的 Apple silicon Mac**。

> 当前公开版使用临时签名，未经 Apple 公证。首次打开时，如果 macOS 阻止启动，请在 Finder 中按住 Control 点按 `PaneSpace.app`，选择“打开”，然后确认提示。应用只访问 macOS 已授权的文件位置。

## 功能

- **多面板浏览：** 12 种面板排布，包括单栏、对称与非对称分栏及网格；最多四个分栏，每栏可独立打开多个标签页并保留浏览历史，窗口布局会在下次启动时恢复。
- **两种浏览模式：** 列表与多级分栏视图；支持前进、后退、上级目录，以及用左右方向键浏览文件夹。
- **本地文件操作：** 收藏夹和已挂载磁盘；搜索、排序、显示隐藏文件、新建文件夹、重命名、移到废纸篓、快速预览、使用默认应用打开和在访达中显示。包含数万个项目的文件夹会先显示首批内容，排序在后台完成，界面不会停顿。
- **多选与批量重命名：** 像访达一样用 Shift 点按选择范围、`⌘` 点按逐项增减、Shift+方向键扩展选择、`⌘A` 全选；选中多个项目后可按替换文本、添加前后缀或序号格式批量重命名，执行前实时预览并检查重名冲突。
- **面板间传输：** 在分栏间复制、移动或拖放本地文件；按字节显示进度，大文件复制中途也能立即取消，并可重试；为同名文件选择跳过、保留两者或替换。
- **拷贝与粘贴文件：** 选中文件后按 `⌘C`，在任意面板按 `⌘V` 粘贴到当前文件夹；可与访达互相拷贝粘贴，粘贴到原文件夹时生成副本。
- **操作历史与撤销：** 复制、移动、重命名、移到废纸篓和新建文件夹都会记录，重启后仍可在“传输 > 操作历史”查看；用 `⌘Z` 或历史中的“撤销”还原操作，撤销只使用可恢复的步骤，不会永久删除文件。
- **按需定制：** 管理侧栏工作区快捷方式，调整图标、名称与路径；设置外观、内容密度、侧栏和面板布局。
- **键盘操作：** `⌘L` 输入路径，`Tab` / `Shift-Tab` 切换活动分栏，`⌘W` 关闭当前标签页或分栏，`⌘Z` 撤销上一次文件操作，`⌃⌘H` 打开操作历史。
- **中英文界面：** 支持简体中文和英文，默认跟随 macOS 语言设置。

## 当前限制

目前只支持本地文件系统；SFTP、SMB 和 WebDAV 仍在路线图中。应用尚未实现沙盒分发所需的安全作用域书签，因此文件访问受 macOS 对当前进程授予的权限约束。功能计划见[开发路线](docs/ROADMAP.md)。

## 从源码运行

需要 macOS 26+，以及 Xcode 26+ 或兼容 Swift 6.2 的工具链。

```bash
swift run PaneSpace
```

构建独立应用包并打开：

```bash
make app
open dist/PaneSpace.app
```

运行测试：

```bash
swift test
```

## 参与贡献

欢迎提交 Issue 和 Pull Request。开始前请阅读[贡献指南](CONTRIBUTING.md)和[开发规范](AGENTS.md)。更多信息：[产品定义](docs/PRODUCT.md) · [架构](ARCHITECTURE.md) · [开发指南](docs/DEVELOPMENT.md) · [安全策略](docs/SECURITY.md) · [开发路线](docs/ROADMAP.md)。

## 许可证

PaneSpace 基于 [MIT License](LICENSE) 开源。
