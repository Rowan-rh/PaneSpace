# PaneSpace

[简体中文](README.md) · [English](README.en.md)

<img src="Assets/PaneSpace-AppIcon.png" alt="PaneSpace 应用图标" width="112" />

PaneSpace 是一款面向 macOS 的原生、开源文件管理器，专注于标签页和并排多分栏工作流。项目采用全新独立实现，仅使用 Apple 公开 API，不包含任何商业文件管理器的代码或资源。

![平台](https://img.shields.io/badge/platform-macOS%2026%2B-black)
![Swift](https://img.shields.io/badge/Swift-6.2%2B-orange)
![许可证](https://img.shields.io/badge/license-MIT-blue)

## 当前功能

- 原生 SwiftUI 与 AppKit 界面
- 12 种单栏、双栏、非对称、横向、纵向及网格布局
- 每个分栏均可使用多个标签页
- 列表和多级分栏浏览模式
- 后退、前进和返回上级目录
- 收藏夹与已挂载磁盘侧边栏
- 文件搜索和排序
- 显示或隐藏隐藏文件
- 新建文件夹和重命名项目
- 将项目移到废纸篓
- 使用空格键快速预览
- 使用默认应用打开文件
- 在访达中显示文件
- 在分栏之间复制、移动或拖放本地文件；冲突时可选择跳过、保留两者或替换
- 查看传输任务、取消及重试失败任务；打开的文件夹会自动刷新
- 按 ⌘L 输入文件夹路径，按 Tab 或 Shift-Tab 切换当前分栏
- 按 ⌘W 关闭当前标签页或分栏；仅剩一个分栏时关闭窗口
- 本地文件提供器抽象，为后续远程存储支持预留扩展能力
- 原生设置中心，可实时调整外观、内容密度、侧边栏、地址栏和分栏
- 英文与简体中文界面；默认跟随 macOS 的语言设置
- 为后续搜索、扩展、快捷键和远程存储功能提供清晰标注的配置入口

## 系统要求

- macOS 26 或更高版本
- Xcode 26 或更高版本，或兼容 Swift 6.2 的工具链

## 从源码运行

在项目目录中运行：

```bash
swift run PaneSpace
```

运行测试：

```bash
swift test
```

构建可独立打开的应用包：

```bash
make app
open dist/PaneSpace.app
```

本地构建的应用会使用临时签名，适合开发和测试。当前版本依赖进程已有的文件访问权限；面向沙盒分发所需的安全作用域书签尚未实现。

## 开发路线

1. 传输任务的字节进度和持久历史
2. 网格和画廊视图
3. 工作区保存与会话恢复
4. SFTP、SMB 和 WebDAV 存储提供器
5. 压缩文件浏览、压缩与解压
6. Git 状态标记与访达扩展
7. 插件 API 与命令面板

## 项目文档

目前架构与开发文档以英文维护，便于代码术语保持一致；用户说明与仓库首页提供完整中文内容。

- [产品定义](docs/PRODUCT.md)
- [架构设计](ARCHITECTURE.md)
- [开发指南](docs/DEVELOPMENT.md)
- [开发路线](docs/ROADMAP.md)
- [架构决策记录](docs/adr)
- [安全策略](docs/SECURITY.md)
- [开发代理与贡献规范](AGENTS.md)

## 参与贡献

欢迎提交 Issue 和 Pull Request。开始修改前，请阅读 [贡献指南](CONTRIBUTING.md) 与 [开发规范](AGENTS.md)。请将存储提供器相关逻辑放在视图层之外，并为文件操作补充测试。

## 许可证

PaneSpace 基于 MIT License 开源。
