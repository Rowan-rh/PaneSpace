---
status: accepted
date: 2026-10-03
revised: 2026-10-04（第二轮，按 PaneSpace-TL 复审评论 01a10453-9c4a：补 hardened runtime
  与 library validation 一节，改为 accepted，附启动验证与重跑的端到端证据；
  第三轮，按 NERE-23 的 Rowan 确认 01a1072b-9303：放弃 delta 增量更新包，
  见「决定 3」与「决定 7」；
  第四轮，2026-10-10（NERE-51 P2-2：宿主改为带 hardened runtime 与
  com.apple.security.cs.disable-library-validation，新增 §7b 启动冒烟测试，
  见 §2b 与「决定 5」）
accepted: Rowan 2026-10-03 批准引入 Sparkle
amended: Rowan 2026-10-04 确认暂不提供 delta 增量更新（见决定 7）
deciders: PaneSpace-TL, Rowan
consulted: NERE-21 (spike)
---

# 0011 应用内更新采用 Sparkle 2

## 结论

**采用 Sparkle 2（固定 2.10.0）实现应用内更新。** 阶段 3 的五项验证全部通过，Sparkle 在
「SPM 构建 + 手工组装 .app + 自签名证书 + EdDSA」这组特定约束下没有发现阻断性问题。
**Rowan 已于 2026-10-03 批准引入**（本仓库第一个第三方依赖），本文档状态为 `accepted`。

本 ADR 只记录结论与证据。实现本身（appcast 生成、设置项、菜单入口）另立任务。

> **修订记录。** 结论始终未变，但有多处第一版写错、写虚或与实际不符的地方已改正。
>
> - **第一轮**（按 PaneSpace-TL CR 评论 `01a1011f-e3bf` 修订第 1–3 条）：
>   1. **§2 签名**——第一版漏签 `Autoupdate`（仍是 `adhoc`），并且重签时丢了
>      hardened runtime 和 entitlements。已修，见 §2。
>   2. **§5 与决定 2 共存方案**——第一版「Sparkle 不管跳过此版本和非模态提示」是
>      事实错误。按「以 appcast 为唯一来源、`UpdateModel` 降级为 UI 适配层」重写。
>   3. **决定 3 Beta 通道与 allKeys**——第一版只写「合并后复核」，已落成明确规则，
>      含 Beta 映射、reset 清哪些键、以及从 NERE-19 键迁移的一次性规则。
> - **第二轮**（按 PaneSpace-TL 复审评论 `01a10453-9c4a`）：
>   1. **新增 §2b「hardened runtime 与 library validation」**——第二轮加上的
>      「与上游和宿主一致」这句话是错的：**宿主加 `-o runtime` 会让应用启动即崩溃**，
>      见 §2b。
>   2. **§2 签名断言的匹配条件**——只匹配 `certificate root` 会把用自签名证书签的
>      正确构建判为失败，改为接受 `certificate leaf` 与 `certificate root` 两种形式。
>   3. **§7 端到端证据重跑**——签名标志改过之后原有证据不能沿用，重跑了一遍
>      0.2.0 → 0.3.0，并补了 ad-hoc / 证书两种构建的启动验证，见 §7。
> - **第三轮**（按 NERE-23 的 Rowan 确认评论 `01a1072b-9303`）：
>   1. **放弃 delta 增量更新包**，新增决定 7。前两轮关于 delta 的说法（决定 3 的
>      「上一版作为输入」和 §8 的「自动生成 delta」）建立在「两份归档能同时放进
>      输入目录」这个前提上，而该前提经实测不成立——见决定 7。
>   2. **§8 体积一节**删去「小版本升级的下载量会很小」的说法，改为记录完整包
>      的实测体积。
> - **第四轮**（2026-10-10，NERE-51 P2-2，按 CR 实测复测结论）：
>   1. **§2b 与决定 5 反转**——第二轮的「宿主不带 hardened runtime」和
>      「`disable-library-validation` 不采用」被推翻。推翻的理由是推理链少了一环：
>      必然失败的是 library validation 这一项，不是 runtime 本身，而那一项可以
>      单独关掉。新增 §7b 记录配套的启动冒烟测试，以及「验签通过但启动即死」这条
>      实测，并把该脚本接进 `ci.yml` 与 `release.yml`。
>
> 另外 §6 改正了一处自相矛盾的表述（「固定 URL 指向最新 release」），并记下了
> CR 指出的一处不准确说法（XPC services 并非「自动检测」）。

## 背景

阶段 1（NERE-18）已经落地了自签名证书和 Ed25519 更新签名密钥，发布 workflow 会产出
zip、SHA-256 和 `.sig`。阶段 2（NERE-19）实现了「启动检查 + 24 小时轮询 + 非模态提示」，
但不替换文件。阶段 3 要回答的是：能不能在现有约束下把「下载 → 验签 → 替换 → 重启」也做掉。

关键约束是 PaneSpace 用 `scripts/build-app.sh` **手工组装 .app**，不是 Xcode 工程。
这意味着框架嵌入、rpath、内层签名顺序都要自己负责，而 Sparkle 2 的标准安装方式
（Xcode 工程的 Embed Frameworks 阶段）在这里不存在。

## 验证环境

| 项目 | 值 |
| --- | --- |
| 工具链 | Xcode 26.1.1，Swift 6.2.1，macOS 27.0 (26A428) |
| Sparkle | 2.10.0（2026-09-13 发布，当前最新稳定版），`exact` 固定 |
| 基线 | 本地 `develop` 的 `0d2535b`（含 NERE-18 签名改动） |
| 分支 | `codex/sparkle-spike`，**不合入 `develop`**，不推送 |
| 签名身份 | 临时自签名证书，SHA-1 `DBF0DC5643238A73D904607C04155AF3DEF1F64E`（2026-10-04 重跑用；第一版为 `93CE188B…3A33CF`，CR 复验时曾换过第三张） |
| 私钥位置 | 仓库外的临时目录，用完删除（见「安全」） |

## 证据

### 1. SPM 引入与 .app 嵌入

`Package.swift` 精确固定版本，SPM 拉取的是官方预编译产物而非从源码构建：

```
.package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.10.0")
```

```
Fetching https://github.com/sparkle-project/Sparkle.git
Downloading binary artifact .../Sparkle-for-Swift-Package-Manager.zip
[0/4] Copying Sparkle.framework
Build complete! (33.27s)
```

**这里有一个必须知道的坑：`swift build` 只负责链接，不会把框架复制进 .app。**
产物里只有 `@rpath/Sparkle.framework/Versions/B/Sparkle` 这一条 load command，
而 `swift build` 出来的二进制只有 `@loader_path` 一个 rpath。所以 `build-app.sh`
必须自己补两件事：

1. `ditto` 框架到 `Contents/Frameworks`；
2. `install_name_tool -add_rpath @executable_path/../Frameworks` 加到主二进制。

> 按 CR 的建议改进了这一点：`install_name_tool` 在 rpath 已存在时**返回非零**，
> 第一版用 `2>/dev/null || print warning` 吞掉，那会同时掩盖真正的工具失败。
> 现在先用 `otool -l` 检查是否已存在，再决定要不要加。

改完之后：

```
$ otool -l dist/PaneSpace.app/Contents/MacOS/PaneSpace | grep -A2 LC_RPATH | grep path
         path @loader_path (offset 12)
         path @executable_path/../Frameworks (offset 12)
```

### 2. 内层签名顺序、hardened runtime 与 entitlements

框架内部带四个需要独立签名的嵌套产物（`Autoupdate` 可执行文件、`Updater.app`、
`Installer.xpc`、`Downloader.xpc`）。必须由内到外签：

```zsh
sparkle_bin="$frameworks_dir/Sparkle.framework/Versions/Current"
nested_targets=(
    "$sparkle_bin/Autoupdate"
    "$sparkle_bin/XPCServices/"*.xpc
    "$sparkle_bin/Updater.app"
)
for nested in $nested_targets; do
    [[ -e "$nested" ]] || continue
    sign_one "$nested"
done
sign_one "$frameworks_dir/Sparkle.framework"
# 最后才签宿主 .app
```

`sign_one` 复用同一身份和 `--keychain`，所以整套产物用的是同一张证书。
签名仍然**不用 `--deep`**（`--deep` 只用于校验），这一点和阶段 1 的结论一致。

**第一版这里漏掉了 `Autoupdate`，而且顺带把 hardened runtime 丢了。** CR 复核在
`Autoupdate` 上跑 `codesign -dvv` 看到 `Signature=adhoc` 且没有 Authority，
复核者进一步注意到重签过的嵌套产物都从上游的 `flags=0x10002(adhoc,runtime)`
退化成 `flags=0x0`——hardened runtime 被去掉了。两条都属实，本次已修。

Sparkle 上游发布这四个产物时的状态（从 SPM 预编译产物直接读出）：

| 产物 | 上游 flags | 上游签名 | 上游 entitlements |
| --- | --- | --- | --- |
| `Autoupdate` | `0x10002(adhoc,runtime)` | adhoc | `com.apple.application-identifier` = `org.sparkle-project.Sparkle.Autoupdate` |
| `Updater.app` | `0x10002(adhoc,runtime)` | adhoc | 空 |
| `Installer.xpc` | `0x10002(adhoc,runtime)` | adhoc | 空 |
| `Downloader.xpc` | `0x10002(adhoc,runtime)` | adhoc | 空 |

所以 `sign_one` 必须显式带上两样东西，否则 `codesign` 在重签时会静默丢弃它们：

- `--preserve-metadata=entitlements`——保住 `Autoupdate` 的
  `com.apple.application-identifier`。这个 entitlement 让 `Autoupdate` 拥有自己的
  XPC 身份（`org.panespace.app-spki`），installer 正是靠它与 App 通信；丢了它
  端到端替换会静默失败。
- `-o runtime`——保住上游的 hardened runtime 标志。**宿主也带 runtime，但额外挂
  `com.apple.security.cs.disable-library-validation`（见 §2b）**；嵌套产物则不需要，
  它们不加载 `Sparkle.framework`。

修完之后四个产物的状态（`dist/PaneSpace.app` 实测，2026-10-04，
证书 SHA-1 `DBF0DC56…1F64E`）：

| 产物 | 修好后 flags | designated requirement |
| --- | --- | --- |
| `Autoupdate` | `0x10000(runtime)` | `identifier Autoupdate and certificate leaf = H"dbf0dc56…1f64e"` |
| `Updater.app` | `0x10000(runtime)` | `identifier "org.sparkle-project.Sparkle.Updater" and certificate leaf = H"dbf0dc56…1f64e"` |
| `Installer.xpc` | `0x10000(runtime)` | `identifier "org.sparkle-project.InstallerLauncher" and certificate leaf = H"dbf0dc56…1f64e"` |
| `Downloader.xpc` | `0x10000(runtime)` | `identifier "org.sparkle-project.DownloaderService" and certificate leaf = H"dbf0dc56…1f64e"` |

entitlements 逐字节保留（与上游产物做 SHA 对比，四个全部 `same`）。
`flags` 从 `0x10002` 变成 `0x10000` 是对的：ad-hoc 位（`0x2`）在换成正式身份后
必须去掉，留着会让 `codesign` 认为这仍是自签产物。

**`Autoupdate` 必须签，这是正确性要求而不是整洁性问题。** 它是真正执行替换
`PaneSpace.app` 的那个进程；不签就意味着「动安装目录」这一步是唯一一个
不在发布身份覆盖范围内的步骤。脚本现在对此做了断言：签完宿主之后逐个检查
四个产物的 designated requirement，缺证书就 `exit 1`。

断言用的是 **DR 而不是 `codesign -dvv` 的 `Authority=` 行**。这一条是实现时踩到的：
`Authority=` 来自信任缓存，不是签名的直接产物，不能区分「用我们的证书签了」
和「根本没签」，还会让正确的构建误报失败。DR 是从签名本身算出来的，ad-hoc 签名会
退化成 `cdhash`，正好是要断言的那个区别。负向测试：把 `Autoupdate` 重新签成 ad-hoc 后

```
# designated => cdhash H"38b35957…" or cdhash H"f74d1d72…"
```

守卫如期触发，并且错误信息里会把这行 DR 打出来，便于直接定位。

**匹配的是「DR 里存在证书子句」，而不是某一个固定措辞。** 证书子句有两种形式，
取决于证书本身：

```
… and certificate leaf = H"…"   # 叶子证书不是 CA（自签名开发证书就落在这里）
… and certificate root = H"…"   # 叶子是 CA，或链上有根
```

第一版只匹配 `certificate root`，结果是**任何用自签名证书签的正确构建都会被判失败**
——断言本身成了误报源，和它要防的那类问题同一性质。现在两种都接受，被禁止的只有
ad-hoc 形式（`… or cdhash H"…" or cdhash H"…"`）。这一点对 release 也有意义：将来换
Developer ID 时，无论 codesign 给出哪种措辞，守卫都成立。

### 2b. hardened runtime 与 library validation（宿主带 runtime + disable-library-validation）

**第四轮修订（2026-10-10，NERE-51 P2-2）。** 本节此前（第二轮）的结论是「宿主不带
hardened runtime」，并明确否定了 `disable-library-validation`。**那个结论只对了一半：
否定的理由（library validation 在没有 Team ID 时必然失败）是实测事实，但由此推出
「因此不用 runtime」是错的——runtime 和 library validation 是可以分开的两件事。**
本节按 CR 复测重新记录。

hardened runtime 默认开启 library validation，要求被加载的库与进程有相同 Team ID，
或由 Apple 签名。自签名证书和 ad-hoc 签名都不带 Team ID，这项校验必然不通过：

```
dyld: Library not loaded: @rpath/Sparkle.framework/Versions/B/Sparkle
  Referenced from: <…> PaneSpace.app/Contents/MacOS/PaneSpace
  Reason: code signature in '…/Sparkle.framework/Versions/B/Sparkle' not valid for
  use in process: mapping process and mapped file (non-platform) have different
  Team IDs
```

实测（第三轮：临时证书 SHA-1 `DBF0DC56…1F64E`，2026-10-04；第四轮：ad-hoc，
2026-10-10，均由 `scripts/launch-smoke-test.sh` 判定）：

| 构建 | 宿主 flags | 宿主 entitlements | `codesign --verify --deep --strict` | 启动结果 |
| --- | --- | --- | --- | --- |
| ad-hoc，无 runtime | `0x2(adhoc)` | 空 | 通过 | 存活 ≥12s，Sparkle 已加载 |
| 临时证书，无 runtime | `0x0(none)` | 空 | 通过 | 存活 ≥12s，Sparkle 已加载 |
| ad-hoc，`-o runtime`，无 entitlement | `0x10002(adhoc,runtime)` | 空 | **仍然通过** | 立即退出（exit 134），dyld 拒绝加载 Sparkle |
| ad-hoc，`-o runtime` + `disable-library-validation` | `0x10002(adhoc,runtime)` | 仅 `com.apple.security.cs.disable-library-validation` | 通过 | 存活 ≥10s，Sparkle 已加载，`DYLD_INSERT_LIBRARIES` 被忽略 |

**第三行是这个坑最要命的地方：签名是有效的，所有 codesign 检查都过，dyld 仍然拒绝加载。**
「验签通过」证明不了「能启动」，只验签的检查会把这个构建当成正确的。第四轮把这条
写进了 CI：打包之后真的把应用启动一次，而不是只验签（见 §7b）。

**决定：宿主带 `-o runtime`，并带唯一一个 entitlement
`com.apple.security.cs.disable-library-validation`（`scripts/PaneSpace.entitlements`）。**
ad-hoc 和证书签名两条路径一致。

**为什么第二轮否掉它、第四轮又加回来。** 第二轮的论据是「不做公证，runtime 换不到
任何东西」，这句话本身没有变；变的是它没有穷举 runtime 的其他内容。runtime 是多项
独立检查的总开关，其中只有 library validation 这一项在自签名/ad-hoc 下必然失败，
而它正是可以用一个 entitlement 单独关掉的那一项。加上这个 entitlement 之后，
runtime 的其余部分照常生效：

| runtime 下的检查 | 关掉后 | 是否需要为 PaneSpace 关掉 |
| --- | --- | --- |
| library validation | `cs.disable-library-validation` | **需要**（无 Team ID） |
| 拒绝 `DYLD_INSERT_LIBRARIES` 等注入 | 否 | 不需要，保持开启 |
| 拒绝 JIT / 匿名可执行内存 | 否 | 不需要，保持开启 |
| 拒绝未签名代码 | 否 | 不需要，保持开启，但见下 |

**最后一行写“保持开启”写得过满，必须说清楚它到底拦住了什么。**
`disable-library-validation` 关掉的不是“签名有效”这项检查，而是“被加载的库必须与进程
同 Team ID 或由 Apple 签名”这一项。于是进程仍然要求每个 dylib 有合法签名，但**签名是
ad-hoc 的库现在也能被加载**——而 Sparkle 及其嵌套产物正是 ad-hoc 签名，关掉这项检查
换来的是“不校验来源”，不是“可以加载任意文件”。所以它拦的是被篡改或无效签名的库，
不拦从磁盘任何位置拿来的、签名有效的库。

真正起缓解作用的是 rpath 只指向 bundle 内部。宿主二进制实测只有两条 rpath
（`@loader_path` 和 `@executable_path/../Frameworks`），且除 Sparkle 外所有 load command
都指向 `/System` 或 `/usr/lib`：

```
$ otool -l dist/PaneSpace.app/Contents/MacOS/PaneSpace | grep -A2 LC_RPATH | grep path
         path @loader_path (offset 12)
         path @executable_path/../Frameworks (offset 12)
$ otool -L dist/PaneSpace.app/Contents/MacOS/PaneSpace | grep -v '^/System\|^/usr/lib'
	@rpath/Sparkle.framework/Versions/B/Sparkle (compatibility version 1.6.0, current version 2.10.0)
```

两条都落在 `PaneSpace.app` 内部，所以攻击者得先把文件放进应用包（或替换掉包里的
Frameworks）才能让 dyld 找到它——这需要写权限，而那本身就是另一道门。嵌套的
`Autoupdate` 和 `Updater.app` 更彻底：没有任何 rpath，只链接系统库。

一句话：**DLV 放宽的是签名来源的校验，路径上的把关交给 rpath。** 如果哪天往宿主里
加一条指向 bundle 外部的 rpath（`/usr/local/lib`、`/opt/homebrew/lib` 这类），这项
取舍就不再成立，必须重新评估。

实测确认注入确实被拒绝：第四行里 `DYLD_INSERT_LIBRARIES` 指向一个真的会被加载的
dylib，宿主正常启动 5 秒且该 dylib 的构造函数从未执行（同一个探针注入一个未签名
进程时正常执行，见 `scripts/launch-smoke-test.sh` 的正向对照）。

**entitlements 严格只有这一项。** 授权清单写在 `build-app.sh` 的
`PaneSpaceENTITLEMENTS_KEYS` 里，构建前先生成一份参考 plist，和
`scripts/PaneSpace.entitlements` 规范化后逐字比；签名后把签名里的 entitlements blob
取出来再和该文件逐字比（两边都过 `plutil -convert xml1`），任何一处不一致就
`exit 1`。两条断言缺一不可：只比签名只能证明“签名等于文件”，而那个文件是可编辑的
文本，往里加一个 key 照样能构建出来；只比文件则证明不了签进去的到底是什么。

写成逐字比对而不是 grep 那一个 key，是因为多出来的第二项就是多出来的一项能力，
而那不该由构建脚本悄悄决定；授权清单放在脚本里，是为了让新增能力必须是一次显眼的
改动，而不是对某个 plist 的静默修改。

因此该文件里**不能写注释**——codesign 的 plist 解析器不接受 XML 注释，
所以说明文字都在 `build-app.sh` 里。

**嵌套产物保留上游的 `-o runtime`，entitlements 用
`--preserve-metadata=entitlements` 原样保留**（见 §2），依据是实测它们的链接依赖：

| 产物 | 是否链接 `Sparkle.framework` |
| --- | --- |
| `Autoupdate` | 否（只有 libz、CoreServices、Foundation 等系统库） |
| `Updater.app` | 否（Cocoa、AppKit、Security、Foundation） |
| `Installer.xpc` | 否（AppKit、CoreServices、ServiceManagement、SystemConfiguration、Security） |
| `Downloader.xpc` | 否（Foundation、Security） |

四个都是独立进程，加载的全是系统框架，**library validation 对它们不适用**，
所以它们不需要 `disable-library-validation`，也不需要 `sign_one` 传入宿主的
entitlements 文件——`Autoupdate` 自己的 `com.apple.application-identifier` 必须保住。

**如果将来改用 Developer ID 签名并做公证，这一节必须重新评估。** 那时宿主和框架
会有同一个 Team ID，library validation 可以直接通过，
`com.apple.security.cs.disable-library-validation` 就应该从
`scripts/PaneSpace.entitlements` 里删掉，而不是留着。判断依据是那时的 Team ID，
而不是本文档的结论。

### 3. 签名校验

```
$ codesign --verify --deep --strict --verbose=2 dist/PaneSpace.app
dist/PaneSpace.app: valid on disk
dist/PaneSpace.app: satisfies its Designated Requirement
```

跨版本 designated requirement 完全一致——这正是阶段 1 想要的、让 TCC 授权存活的前提。
下面三行是本轮重跑（2026-10-04，证书 SHA-1 `DBF0DC56…1F64E`）的实测输出，
其中最后一行是**升级之后**磁盘上那份：

```
$ codesign -d -r- dist/PaneSpace.app            # 0.1.0 (build 10099)
designated => identifier "org.panespace.app" and certificate leaf = H"dbf0dc56...1f64e"

$ codesign -d -r- dist/PaneSpace.app            # 0.2.0 (build 20099)
designated => identifier "org.panespace.app" and certificate leaf = H"dbf0dc56...1f64e"

$ codesign -d -r- dist/PaneSpace.app            # 0.3.0 (build 30099)
designated => identifier "org.panespace.app" and certificate leaf = H"dbf0dc56...1f64e"
```

嵌入框架没有让 DR 退化成 cdhash。

### 4. Swift 6 严格并发

```
$ swift build -c release -Xswiftc -warnings-as-errors
Build complete! (15.44s)
```

零错误零警告。过程中撞到两个真实的 Swift 6 约束，都记录下来供实现时参考：

**`SPUStandardUpdaterController` 是 `NS_SWIFT_UI_ACTOR`，只能用在主 actor 上。**
这个符合预期，封装成 `@MainActor` 的类即可。

**它的 delegate 只能在初始化时传入，没有 setter。** 而 Swift 要求所有存储属性
在 `super.init()` 之前完成初始化，所以不能在 init 之后补挂 delegate。必须这样写：

```swift
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // NSApplicationDelegate 在 Swift 6 里不是 @MainActor 隔离的，
    // 所以主 actor 隔离的属性不能用默认值，必须显式创建。
    private var probe: SparkleSpikeProbe?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let probe = SparkleSpikeProbe()   // 主 actor 上显式创建
        self.probe = probe                // 保活：Sparkle 弱引用 delegate
        probe.start()
    }
}
```

第一版把 `@MainActor` 加在 `PaneSpaceApplicationDelegate` 上并用 `= SparkleSpikeProbe()`
作默认值，直接编译失败：

```
error: main actor-isolated default value in a nonisolated context
```

**`NSApplicationDelegate` 本身不是 `@MainActor` 隔离的**，所以加上 `@MainActor` 之后
默认值仍是非隔离上下文里的主 actor 值。解法是不用默认值，在
`applicationDidFinishLaunching` 里显式创建。

### 5. 与阶段 2 `UpdateModel` 的关系：`UpdateModel` 降级为 UI 状态适配层

**本节按 CR 第 2 条重写。第一版的依据有事实错误，已作废。** 原 ADR 写的是
「Sparkle 不负责『跳过此版本』和『非模态提示』，所以两者职责不重叠、共存即可」。
前半句是错的：Sparkle 2.10 有 `SPUUserUpdateChoiceSkip`（`SPUUserUpdateState.h`）
和 `SUSkippedVersion`；后半句也站不住：非模态提示可以用 gentle reminders 实现。
CR 的两条指正都已在下面引用的头文件里逐条核实。

**为什么原来的「共存」写法是个真问题。** 如果两套都按原样跑起来，会同时存在：

| 重复的东西 | 阶段 2 | Sparkle |
| --- | --- | --- |
| 调度器 | 24 小时 `Task` 轮询 | `SUEnableAutomaticChecks` + `SUScheduledCheckInterval` |
| UI | NERE-20 的横幅 | 标准驱动的模态更新窗 |
| 跳过状态 | `skippedUpdateVersion` | `SUSkippedVersion` |
| 数据源 | GitHub Releases API | appcast |

尤其最后一行会直接咬人：点「安装」时若转交 `checkForUpdates()`，Sparkle 会**重新拉一次
appcast**，此时返回的版本可能和横幅上显示的不一致——用户在横幅上看到的版本不是他
装上的那个。

**改为：appcast 是发现更新和划分通道的唯一依据，调度和跳过都交给 Sparkle。**

- 调度、跳过、下载、验签、替换、重启，全部由 Sparkle 负责。Sparkle 自己持有
  `SULastCheckTime` 决定下次检查，PaneSpace 不再另起轮询。
- 通道过滤交给 `allowedChannels(for:)`（`SPUUpdaterDelegate.h`：空集表示只看
  default 通道，default 通道**总是**被包含）。
- `UpdateModel` 降级为**纯 UI 状态适配层**：不再自己发请求、不再比较版本，
  只把 Sparkle 的 delegate 回调翻译成 NERE-20 横幅需要的状态。
  `updater(_:didFindValidUpdate:)` → 有更新；`didAbortWithError` → 静默；
  `didFinishUpdateCycleForUpdateCheck:error:` → 结束检查中。
- 横幅走 gentle reminders：`supportsGentleScheduledUpdateReminders` 返回 `true`，
  并实现 `standardUserDriverShouldHandleShowingScheduledUpdate:andInImmediateFocus:`
  返回 `false`，把「显示更新」的职责接管到 PaneSpace 自己的横幅上
  （`SPUStandardUserDriverDelegate.h` 明确说明返回 `NO` 后 delegate 负责展示）。
  横幅需要聚焦时调 `checkForUpdates()`。
- 跳过：横幅上的「跳过此版本」走 `SPUUserUpdateChoiceSkip`，状态落在
  `SUSkippedVersion`，不再自己写 `skippedUpdateVersion`。
- `GitHubReleaseFeed` **只作为后备**：在没有链接 Sparkle 的构建，或
  没有 `SUPublicEDKey`（因而没有 appcast）时才启用。NERE-19 可以照常推进，
  在这两种构建里它就是完整路径。

**「自动检查」这个设置只能存一处。** spike 里每次启动把
`automaticallyCheckForUpdates` 镜像写进 `SUEnableAutomaticChecks`，会出现两份
互相漂移的状态——比如用户在 Sparkle 的 UI 里关掉，PaneSpace 下次启动又写回
去。规则：**以 Sparkle 的属性为准，界面直接绑定 updater**，
`updater.automaticallyChecksForUpdates` 双向绑定到设置项的 Toggle，
PaneSpace 不再镜像写入自己那个键。详见「决定 3」里的迁移规则。

### 6. appcast 来源

**推荐：让 release workflow 生成 `appcast.xml`，并发布在一个固定 URL 上。**

> 原稿写的是「作为 Release 资产，固定 URL 指向最新 release」，按 CR 第 3 条改正：
> 「指向最新 release」和「固定 URL」是矛盾的。固定 URL 要指向一个**长期存在**的
> 位置（专用分支 / Pages / 固定 tag 的资产），不能用会随发布移动的
> `latest`。载体三选一，由实现任务决定，规则见「决定 3」。

`generate_appcast` 是 Sparkle 官方的 appcast 生成工具，可以用官方预编译产物：

```
$ xcodebuild -project Sparkle.xcodeproj -scheme generate_appcast \
    -configuration Release -derivedDataPath ... build
** BUILD SUCCEEDED **
```

它用 `--ed-key-file -` 从 stdin 读私钥，正好能和现有的 `PANESPACE_ED25519_PRIVATE_KEY`
环境变量对接，私钥不进 argv：

```
$ cat "$PANESPACE_ED25519_PRIVATE_KEY" | generate_appcast --ed-key-file - \
    --download-url-prefix "https://github.com/Rowan-rh/PaneSpace/releases/download/v$VERSION/" \
    dist/
Wrote 1 new updates, updated 0 existing updates, and removed 0 old updates in appcast.xml
```

**生成时必须把上一版 `appcast.xml` 一起作为输入**（`--previous-appcast`
或把旧文件放进输入目录）。否则每次发布都从零生成，历史条目会丢。上面那次实测
之所以「updated 0 existing updates」，是因为那是第一份 appcast。

**注意：保留上一版 appcast 不等于能生成 delta。** 前一版归档不能放进输入目录，
否则旧条目的下载 URL 会被改写成当前 tag 的前缀（404），详见决定 7。

生成的 appcast 里，`edSignature` 由工具直接算好，PaneSpace 不需要自己拼 XML：

```xml
<item>
    <title>0.2.0</title>
    <sparkle:version>20099</sparkle:version>
    <sparkle:shortVersionString>0.2.0</sparkle:shortVersionString>
    <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
    <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
    <enclosure url="http://127.0.0.1:8791/PaneSpace-0.2.0-macos-arm64.zip"
               length="3720453" type="application/octet-stream"
               sparkle:edSignature="2YnzbCXtFYPwuR964bPm88qeXx7Daqgi4qqtsbK4M4uk3zJm7sQqBklz9VhrfJOsMyJ30e/UeNppUPZwY/P/CQ=="/>
</item>
```

`minimumSystemVersion` 和 `hardwareRequirements` 是工具从 bundle 里读出来的，
和 `version-from-tag.sh` 产出的 `CFBundleVersion` 编码（`20099`）配合正常——
Sparkle 按各段数值比较，和阶段 1 的设计一致。

**`releases/latest/download/` 的重定向可用**，实测：

```
$ curl -sIL "https://github.com/Rowan-rh/PaneSpace/releases/latest/download/PaneSpace-0.1.2-macos-arm64.zip"
HTTP/2 302
location: https://github.com/Rowan-rh/PaneSpace/releases/download/v0.1.2/PaneSpace-0.1.2-macos-arm64.zip
HTTP/2 302
location: https://release-assets.githubusercontent.com/...
HTTP/2 200
```

但**不推荐**用它作为 appcast 源：`latest` 指向最新发布，prerelease 不会出现在
`latest` 里，Beta 通道无从谈起；如果要两个通道，就得挂两个固定 URL，或者一个 appcast
里带通道标签（推荐后者）。固定 URL 要指向一个长期存在的资产（例如仓库里的
`appcast.xml`，或某个专门存放 feed 的 release）。

### 7. 端到端实机验证

全部在本机完成，用临时自签名证书（SHA-1 `DBF0DC56…1F64E`）和临时 Ed25519 密钥。
appcast 由本地 HTTP 服务（`127.0.0.1:8931`）提供。

> **本节证据已于 2026-10-04 在新的签名标志下全部重跑。** 嵌套产物的签名标志
> 相对第一版改过（见 §2、§2b），旧证据不能沿用。重跑用的是与 §2b 同一张证书。
>
> **本地 feed 需要一个仅供测试的开关。** 脚本默认只接受 https 的 `SUFeedURL`
> （见 §6），本地 HTTP 服务喂不了 appcast，所以加了
> `PANESPACE_APPCAST_ALLOW_LOCALHOST=1`：它只放行 `http://127.0.0.1`，
> 其余一律仍然报错。**release workflow 禁止设置这个变量**，脚本在放行时会打印
> 两行警告说明这个构建信任明文 feed、不得发布。三个分支都实测过：
> 缺 URL 报错、`http://` 不带开关报错、带开关只放行 `127.0.0.1`。

**成功升级：0.2.0 → 0.3.0，下载、验签、替换、重启全部走通。**

应用抓到 appcast，验签通过，找到更新并下载，然后 `Updater` 接管：

```
Sparkle: OK: EdDSA signature is correct for appcast
Sparkle: OK: EdDSA signature is correct for update
Autoupdate: activating connection: name=org.panespace.app-spki.peer[26158]
PaneSpace [26158]: applicationShouldTerminate: NSTerminateNow
PaneSpace [26158]: Termination complete. Exiting without sudden termination.
PaneSpace [27453]: （新进程，Sparkle 重新拉起）
```

进程号的对应关系就是「替换 + 重启」的直接证据——旧进程 26158 退出，
新进程 27453 从同一个路径起来，版本已经变成 0.3.0：

```
$ pgrep -f .spike-apps/PaneSpace.app/Contents/MacOS/PaneSpace
27453
$ defaults read .spike-apps/PaneSpace.app/Contents/Info.plist CFBundleShortVersionString
0.3.0
$ lsof -p 27453 | grep Sparkle
  … .spike-apps/PaneSpace.app/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle
  … Sparkle.framework/Versions/B/Resources/zh_CN.lproj/Sparkle.strings
```

重新拉起后的进程存活超过 10 秒，且 Sparkle 已经映射进它的地址空间——
这同时说明「升级后的应用真的能启动」，而不只是「磁盘上的文件被换掉了」。

结果：

```
$ codesign --verify --deep --strict .spike-apps/PaneSpace.app
# 通过
$ codesign -d -r- .spike-apps/PaneSpace.app
designated => identifier "org.panespace.app" and certificate leaf = H"dbf0dc56…1f64e"
$ xattr .spike-apps/PaneSpace.app
com.apple.provenance:      # 没有 com.apple.quarantine
```

**下载的更新不带 quarantine**，所以更新后的应用不会再被 Gatekeeper 拦。
0.2.0、0.3.0（归档内）和升级后的磁盘副本三者 DR **逐字相同**，阶段 1 的 TCC 前提成立。

> 复现时有两个容易踩空的地方，都不是 Sparkle 的问题，记录下来免得下次重跑时误判：
>
> 1. **必须用 `open -a` 启动。** 直接跑 `Contents/MacOS/PaneSpace` 绕过了
>    LaunchServices，进程没有注册成这个 bundle 的运行副本，替换能完成但不会重启。
> 2. **必须清掉 `SULastCheckTime`。** Sparkle 会按 `SUScheduledCheckInterval`
>    跳过本轮检查，只看到 appcast 被拉取却没有任何后续动作。`defaults delete
>    org.panespace.app` 会一起清掉它。

**失败拒绝：篡改归档被 EdDSA 拒绝，原应用未受影响。**

为了排除「zip 结构损坏」这种假阳性，做了一对 A/B——同样的 app、同样的 appcast
签名，只换归档字节，并且**两个归档长度完全相同**（用 `zip -0` 存 uncompressed，
避免压缩后长度变化让「长度检查」成为拒绝原因而掩盖验签）：

| 归档 | 长度 | Sparkle 的判定 | `ed25519.swift` 的判定 |
| --- | --- | --- | --- |
| 篡改版（icns 翻 1 bit，长度不变） | 9060165 | `Error: failed to pass signing verification.` | `error: signature mismatch` |
| 干净版（同一签名） | 9060165 | 通过（rc=0） | `signature OK` |

**长度相同这一点是刻意的**：之前那组 A/B 改动过文件长度，Sparkle 的日志里会专门
提到 expected length 与实际不符，那样「拒绝」可能来自长度检查而不是验签。
等长重测之后可以确认，拒绝靠的是验签。

PaneSpace 自己的 `scripts/ed25519.swift` 独立得出同样结论：

```
$ swift scripts/ed25519.swift verify <篡改版> <appcast 中的签名> <公钥>
error: signature mismatch for tamper.zip
$ swift scripts/ed25519.swift verify <干净版> <同一签名> <公钥>
signature OK: clean.zip
```

**这一对 A/B 是「验签真的起作用」的证据**：唯一的变量是归档字节，签名相同，
长度相同，结果一个被拒一个被装上。

密钥互通也顺带确认了：Sparkle 的 `sign_update` 用 PaneSpace 格式的私钥签出的签名，
`scripts/ed25519.swift` 能验过；反之亦然。

**TCC 授权保持：未能直接验证。** TCC 数据库受 SIP 保护，
`sqlite3 ~/Library/Application Support/com.apple.TCC/TCC.db` 读不到
（`unable to open database file`），`tccd` 日志里也无法注入一条可控的授权记录。
可确证的是更新前后 DR 逐字节相同、且更新不带 quarantine——这两点是 TCC 授权存活的
**必要条件**，阶段 1 已用同样方式验证过。**这一项仍需 Rowan 在真实用户机器上
点一次授权来最终确认**（装旧版本 → 授权桌面/文稿/下载 → 用本地 appcast 升级 →
确认不再弹授权；PaneSpace 不要放在下载或桌面目录里测）。

### 7b. 打包后的启动冒烟测试（2026-10-10，第四轮）

§7 里的端到端验证是一次性的、本机手工做的，跑一次就没了。**第四轮把它写成了脚本**：
`scripts/launch-smoke-test.sh`，任何人对任何一个已打包的 bundle 都能重跑同一组判定。
把它接进 `ci.yml` 和 `release.yml` 是同一轮的收尾（见 NERE-51 P2-5）。
它存在的原因就是 §2b 表格里那行「验签通过但启动即死」：`ci.yml` 在验签之后
跑一次这个脚本，`release.yml` 在打包之前同样跑一次（发布出去的就是那个 bundle）。
这种构建不会被任何 codesign 检查发现，所以脚本判的是四件真正发生过的事：

| 判定 | 失败时的含义 |
| --- | --- |
| 进程存活 ≥10s（默认） | 应用根本没起来，或起来就崩 |
| 输出里没有 dyld 报错 | 起来了但某个库没能映射，只是恰好还没崩 |
| `lsof` 里能看到 `Frameworks/Sparkle.framework/` | 框架完全没被加载 |
| `DYLD_INSERT_LIBRARIES` 被忽略 | runtime 没真正生效（或多了 `allow-dyld-environment-variables`） |

第四项用 `scripts/dyld-injection-probe.c` 编出来的 dylib 实测，不靠读 entitlements
推断。**同一个探针先注入一个未签名的可执行文件作为正向对照**——对照不工作就说明
探针本身坏了，「没有生效」就什么都不能证明。

第四轮的实测（ad-hoc，`make app` 默认构建）：

```
$ ./scripts/launch-smoke-test.sh
Positive control: DYLD_INSERT_LIBRARIES works on an unsigned process
Survived 10s
No dyld errors in the app's output
Sparkle.framework is loaded
DYLD_INSERT_LIBRARIES is ignored
Launch smoke test passed: …/dist/PaneSpace.app
```

负向测试：把同一个 bundle 重新签成「`-o runtime` 但不带 entitlement」，再跑同一个脚本：

```
$ codesign --verify --deep --strict --verbose=2 /tmp/broken.app
/tmp/broken.app: valid on disk
/tmp/broken.app: satisfies its Designated Requirement      # exit 0

$ ./scripts/launch-smoke-test.sh /tmp/broken.app
--- output from the app ---
       dyld[63247]: Library not loaded: @rpath/Sparkle.framework/Versions/B/Sparkle
         …
         Reason: … code signature … not valid for use in process: mapping process
         and mapped file (non-platform) have different Team IDs …
--- end of output ---
error: the app exited with code 134 before the 10s mark
```

**验签通过、冒烟失败**，这正是这个检查要拦下的组合。

**前置条件：runner 需要有窗口服务器。** 没有 Aqua 会话时 AppKit 应用会以
「FAILED to establish the default connection to the WindowServer」死掉，那是环境问题
不是打包问题。脚本先查 `launchctl managername`，不是 `Aqua` 就直接报成环境问题并退出。

### 8. 体积与许可证

| | 大小 |
| --- | --- |
| 原始 .app | 5.8 M |
| 嵌入 Sparkle 后的 .app | 8.8 M |
| 增量 | **+3.0 M（约 +52%）** |
| `Sparkle.framework` | 2.9 M |

框架内部构成：

| 组件 | 大小 |
| --- | --- |
| `Sparkle`（主框架） | 956 K |
| `Autoupdate`（installer 可执行文件） | 692 K |
| `XPCServices/`（Installer + Downloader） | 408 K |
| `Updater.app`（进度代理） | 344 K |
| `Resources/`（含 7 个本地化） | 364 K |

`+3.0 M` 对一个文件管理器可以接受。**更新时的下载量是完整包，本 ADR 不提供
delta 增量更新包**（决定 7），当前实测每个完整包约 3.2 M。

许可证是 **MIT**（`Copyright (c) 2006-2013 Andy Matuschak` 等，
"Permission is hereby granted, free of charge..."）。GitHub API 把仓库 license
标为 `NOASSERTION`（因为 LICENSE 文件是多版权人拼接），但内容是标准 MIT，
与 BSD/MIT 兼容，可以随闭源或开源分发，只需保留版权声明。
**需要在应用或 README 中附带 Sparkle 的版权声明。**

## 关键决策

### 决定 1：采用 Sparkle 2.10.0，精确固定版本

理由：五个验证项全部通过；自研方案要自己实现验签、提权、替换、回滚，
成本远高于引入一个 MIT 依赖。

版本必须 `exact` 固定而不是范围依赖。Sparkle 的 appcast 格式和通道语义在小版本间
会演进，PaneSpace 的更新路径一旦被大量用户依赖，一次上游自动升级就可能改变行为。
阶段 1 的发布链已经确定「tag 是版本的唯一来源」，这里保持同样的克制。

### 决定 2：以 appcast 为唯一来源，`UpdateModel` 降级为 UI 状态适配层

**本条按 CR 第 2 条重写，作废「两者共存、职责不重叠」的旧结论。**
旧结论的依据（Sparkle 不管跳过和不提示）是事实错误，已在「与 `UpdateModel` 的关系」
一节列出正确的 API 和两套并行会造成的问题。

新结论：appcast 是发现更新和划分通道的**唯一**依据；调度、跳过、下载、验签、
替换、重启全部交给 Sparkle；`UpdateModel` 保留代码但只做状态翻译，
不再自己发请求、不再比较版本。NERE-20 的横幅通过 gentle reminders 接管展示。

`UpdateModel` 的网络与比较逻辑不会白写：它是 `GitHubReleaseFeed` 后备路径的
实现载体，在没有 Sparkle 或没有 `SUPublicEDKey` 的构建里继续完整工作，
那部分单测继续有效。

### 决定 3：Beta 通道与偏好键的具体规则

**本条按 CR 第 3 条从「合并后复核」落成明确决定。**

**Beta 通道。** Sparkle 没有 beta 开关，只有通道。规则固定为：

- `betaUpdates` 映射到 `allowedChannels(for:)`，开启返回 `["beta"]`，
  关闭返回**空集**。default 通道总是被包含，不需要（也不应该）显式列出。
  返回 `["default", "beta"]` 是多余的——头文件写明 default 通道总是包含在允许集合里。
- release workflow 按 tag 处理：预发布 tag 用 `generate_appcast --channel beta`，
  正式版**不**打 `--channel`（即落在 default 通道）。
- GitHub 的 `prerelease` 标记**只影响 Releases 页面的展示，不参与**「有没有更新」
  的判断。判断依据是 appcast 条目上的通道标签。
- 两个通道**放在同一份 appcast 里**，不维护两个 feed。
- 生成时必须把**上一版 `appcast.xml` 作为输入**，否则历史条目会丢。
  **但这不等于会生成 delta**，两者互斥，理由见决定 7。
- feed 不用 `latest/download`（`latest` 不跟 prerelease），放在固定 URL 上——
  专用分支、Pages 或固定 tag 的资产，三选一，由实现任务确定。

**`PaneSpacePreferences.allKeys` 重置时清哪些键。** 判据是「用户能在 UI 里看到或改到」：

| 键 | reset 时 | 为什么 |
| --- | --- | --- |
| `SUEnableAutomaticChecks` | **清** | 用户可见的「自动检查」开关 |
| `SUAutomaticallyUpdate` | **清** | 用户可见的「自动下载/自动安装」开关 |
| `SUScheduledCheckInterval` | **清** | 检查间隔，设置项可改 |
| `SUSkippedVersion` | **清** | 用户「跳过此版本」的结果 |
| `SUSkippedMajorVersion` | **清** | 同上，Sparkle 另存的大版本跳过记录 |
| `SUSkippedMajorSubreleaseVersion` | **清** | 同上 |
| `SUSendProfileInfo` | **清** | 用户可见的「发送系统信息」同意标记 |
| `SULastCheckTime` | **不清** | 内部状态，清掉会立刻触发一次检查 |
| `SUHasLaunchedBefore` | **不清** | 内部状态，清掉会重放首次启动流程 |
| `SUUpdateGroupIdentifier` | **不清** | 内部状态，分组更新用的随机标识 |

后三个不清的理由都是「清掉会造成一次用户没要求的行为」：多余的检查、重放的
首次启动提示、丢失的分组状态。

**「自动检查」只存一处。** 以 Sparkle 的属性为准：设置项直接双向绑定
`updater.automaticallyChecksForUpdates`，PaneSpace **不再**镜像写
`automaticallyCheckForUpdates`。从 NERE-19 键迁移的规则：

1. 首次启动，若 `SUEnableAutomaticChecks` **不存在**而
   `automaticallyCheckForUpdates` 存在，则把后者的值写进前者，然后删除
   `automaticallyCheckForUpdates`。
2. 两个都存在时，以 `SUEnableAutomaticChecks` 为准，删除 `automaticallyCheckForUpdates`。
3. 迁移只做一次，由一个 `hasMigratedUpdatePreferences` 标记保护，避免每次启动
   都在两个键之间来回覆盖。

### 决定 4：appcast 由 release workflow 生成，作为 Release 资产

理由：`generate_appcast` 生成的 `edSignature` 和 `minimumSystemVersion` /
`hardwareRequirements` 不该由我们手写维护。工具接受 stdin 传私钥，
和现有的 secret 传递方式一致。

**不使用 `releases/latest/download/` 作为 feed URL**（虽然实测可用），
因为 `latest` 不含 prerelease，与 Beta 通道冲突。固定 URL 的载体见决定 3。

feed 放在公开的固定 URL 上，所以**对 feed 本身也签名**：
`SURequireSignedFeed=true` 和 `SUVerifyUpdateBeforeExtraction=true` 已经在
`build-app.sh` 里写入 Info.plist。否则通道标签和 `minimumSystemVersion`
可以被改而不动更新本身的签名。

### 决定 5：宿主启用 hardened runtime，并只带 `disable-library-validation`

**2026-10-10 修订**：本条原为「宿主不启用 hardened runtime」，依据是 §2b 的实测。
实测本身没错，错的是从「library validation 必然失败」推到「所以不用 runtime」——
两者之间隔着一项可以单独关闭的检查。第四轮按 CR 复测改为本条。

PaneSpace 不做公证，宿主和 Sparkle.framework 没有共同 Team ID，
`com.apple.security.cs.disable-library-validation` 是让 library validation 能通过
（准确说是被跳过）的最小授权。带上它之后 runtime 的其余部分照常生效：注入、
JIT、匿名可执行内存仍然一律拒绝，实测见 §2b 与 §7b。“拒绝未签名代码”这项的准确
含义见 §2b：它拦的是无效或被篡改的签名，不是 ad-hoc 签名的库，路径上的把关由
rpath 只指向 bundle 内部来完成。

脚本对这个组合做双向断言：宿主必须有 runtime 标志，且 entitlements 必须与写死在
脚本里的授权清单 `PaneSpaceENTITLEMENTS_KEYS` 一致——这个文件必须逐字符合该清单，
签名又必须逐字符合这个文件，多一项也算失败。**理由见 §2b
第三行：只验签的检查放行了一个根本启动不了的构建，所以 CI 里还要真的启动一次。**

嵌套产物不受这条约束（它们不链接 `Sparkle.framework`，只加载系统框架），
因此保留上游的 runtime 标志和自己的 entitlements，不挂宿主这一份。

**将来改用 Developer ID 签名时，本条要重新评估**：那时 Team ID 存在，
library validation 可以直接通过，`disable-library-validation` 应当删掉。

### 决定 6：不在本阶段处理 TCC 授权的端到端验证

理由：受 SIP 保护，无法在无人值守的 CI 或 agent 环境里可靠构造授权记录。
DR 相同 + 无 quarantine 是必要条件，已验证。真实点击授权需要 Rowan 在
正常桌面会话里做一次。

### 决定 7：不生成 delta 增量更新包，老版本下载完整包

**Rowan 于 2026-10-04 在 NERE-23（评论 `01a1072b-9303`）确认这个取舍。**
本条取代前两轮关于 delta 的说法：决定 3 原写「生成时必须把上一版 `appcast.xml`
作为输入，否则历史条目和 delta 会丢」，§8 原写 `generate_appcast` 会自动生成
delta、小版本升级下载量很小。两处都作废。

**规则：release workflow 的 `generate_appcast` 输入目录里只放本次发布的归档，
不放任何历史归档。** 历史条目由上一版 `appcast.xml` 承载，各版本自己的下载 URL
和 `edSignature` 逐字保留。

**事实修正（2026-10-10，NERE-51 P3）。** 上一段「历史条目由上一版 appcast.xml 承载」
字面成立，但读起来像「feed 会无限保留全部历史」，那不是 `generate_appcast` 的默认行为：
它默认 `--maximum-versions 3`，**每个分支只保留最新 3 个版本**
（`generate_appcast/Appcast.swift:145`），并且一个已被 default 通道超越的 beta 分支
只保留 1 条（`Appcast.swift:150-165`）。用固定的 2.10.0 生成器实测：

| 输入 | 生成结果 |
| --- | --- |
| 5 个签名归档，无历史 appcast | 3 条（`Moved 2 old update files to old_updates`） |
| 历史 appcast（3 条）+ 只有本次归档，即本条规则描述的布局 | 3 条，最旧的一条被移除 |
| 同上，加 `--maximum-versions 0` | 4 条，全部保留 |

本条规则本身不受影响——**被留下的条目依然逐字保留 URL 和签名**，只是更早的条目会随
发布自然老化出 feed。想保留全部条目可以传 `--maximum-versions 0`，代价是 feed 无界增长，
这是产品取舍而不是缺陷，因此当前不传。

**为什么不能两者兼得。** `generate_appcast` 在按 feed 分组**之前**就把
`downloadUrlPrefix` 赋给输入目录里的每一个归档
（`generate_appcast/Appcast.swift:40-43`）：

```swift
// Apply download and release notes prefixes
for update in allUpdates {
    update.downloadUrlPrefix = downloadURLPrefix
    update.releaseNotesURLPrefix = releaseNotesURLPrefix
}
```

而 delta 只能在新旧两份归档都在输入目录时生成。两者同时满足的条件互斥。

**实测（Sparkle 2.10.0 的 SwiftPM 产物，两 tag 0.1.0 → 0.2.0，独立 Ed25519
密钥，两份归档均由 `build-app.sh` 按发布方式构建、带 `SUPublicEDKey` 和
`SURequireSignedFeed`）**：

| 输入 | 0.1.0 条目的 URL | 0.1.0 的 `edSignature` | delta |
| --- | --- | --- | --- |
| A：只有 0.2.0 + `--download-url-prefix` | 保持 `.../v0.1.0/PaneSpace-0.1.0-macos-arm64.zip` | 逐字未变 | 无 |
| B：两份归档 + `--download-url-prefix` | **被改写成 `.../v0.2.0/PaneSpace-0.1.0-macos-arm64.zip`（404）** | 重算 | 有，1,682 B |
| C：只有 0.2.0，不带 prefix | 保持正确 | 逐字未变 | 无；新条目 URL 落到 feed 同目录，同样 404 |

方案 B 的 delta 是 1,682 B，同版本完整包是 3,197,877 B——差约 1900 倍。
**用一次必然 404 的旧版本下载，换一个 1.7 K 的包，不成立。** 方案 A 让老用户
下载完整包，这是可接受的代价；Sparkle 拿到一份正确的完整包就正常更新。

> 注：实测时工具会对 ad-hoc 签名的两份归档打印一行
> `Warning: found mismatch code signing identity`。这只在两份归档的签名身份不同时
> 出现，真实发布链里两个版本都由同一发布证书签名，不会触发。实测同时确认了
> 无论是否出现该警告，delta 都照常生成——它不是被跳过，而是场景 B 独有的产物。

**已知影响。** 每次更新都是完整下载，当前每个完整包约 3.2 M。这个体积在
PaneSpace 的量级下已由 Rowan 接受。若将来完整包显著变大（例如嵌入更多框架
或本地化资源），本条需要重新评估。

**什么情况下可以重新引入 delta。** 三个前提同时成立才有意义：

1. `generate_appcast` 能对不同归档指定不同前缀——要么上游支持按归档设置
   `downloadUrlPrefix`，要么 PaneSpace 改为不给 `--download-url-prefix`、在
   生成后自行补全每个条目的 URL 并重新签名整个 feed。后者是工具之外的一层
   后处理，引入前要先算清维护成本。
2. 旧版本的归档仍能从某个稳定位置取到（delta 需要它，且 appcast 的 delta
   条目也必须指向一个真实存在的 URL）。
3. 完整包的体积已经大到值得为此增加一层复杂度。

在此之前，`release.yml` 里「如果生成了 delta 就一并上传」的分支保留着
（appcast 指向的资产必须存在，否则客户端会整个更新失败），但当前输入方式下
它不会被触发。

## 影响与后续

**正面：**

- 首个第三方依赖。`Package.resolved` 会新增一个条目。
- `build-app.sh` 需要长期维护框架嵌入和内层签名逻辑，`Makefile` 的 `app` 目标
  会变慢（SPM 需要先拉取框架产物）。
- 应用体积 +3.0 M。

**需要 Rowan 或后续任务处理：**

1. ~~**确认引入 Sparkle**~~ —— **已完成：Rowan 2026-10-03 批准**，本文档状态
   改为 `accepted`。
2. ~~**确认 delta 与历史条目如何取舍**~~ —— **已完成：Rowan 2026-10-04 确认
   暂不提供 delta**，见决定 7。
3. 发行说明和 README 里附带 Sparkle 的 MIT 版权声明。
4. release workflow 增加 `generate_appcast` 步骤，确定 feed 的固定 URL 载体
   （专用分支 / Pages / 固定 tag 的资产，三选一）。
5. NERE-20（横幅、菜单、设置）按决定 2 改成基于 Sparkle：
   gentle reminders 接管展示，`UpdateModel` 降级为状态适配层。
6. 实现 `PaneSpacePreferences.allKeys` 的 Sparkle 键集合与一次性迁移，
   规则见决定 3（哪些清、哪些不清、为什么）。
7. **在真实用户会话里验证一次 TCC 授权跨升级保持**（桌面/文稿/下载）。
8. 首次安装仍需「仍要打开」（未公证），这是既定限制，不因本 ADR 改变。
9. **如果将来改用 Developer ID + 公证，重新评估 §2b 与决定 5**：那时 Team ID 存在，
   library validation 可以通过，`com.apple.security.cs.disable-library-validation`
   应当从 `scripts/PaneSpace.entitlements` 里删掉，而不是留着当默认。
10. **如果完整包体积显著变大，重新评估决定 7 的 delta 取舍。**

**已知可优化项（不阻断，不在本 ADR 承诺）：**

- `XPCServices/` 占 408 K。CR 复核指出非沙盒应用默认不会用到 XPC services，
  只有设置了 `SUEnableInstallerLauncherService` / `SUEnableDownloaderService`
  才启用。实现时可以验证后删掉这一目录，能省 408 K，也少四处要签名的产物。
  **本 ADR 修正了原 checkpoint 的说法**：「Sparkle 会自动检测 XPC service 是否可用」
  是不准确的，实际上这些 service 是显式开关控制的。
- 框架是 arm64+x86_64 通用二进制，`LSMinimumSystemVersion` 是 26.0，
  可以用 `lipo` 裁成只剩 arm64。

## 备选方案：自研更新（未采用，保留要点）

如果因为体积、许可合规或不想引入依赖而否决 Sparkle，自研方案需要覆盖：

**验签。** CryptoKit 的 `Curve25519.Signing.PublicKey.isValidSignature(_:for:)`
足以替代 EdDSA，`scripts/ed25519.swift` 已经是这个实现，密钥格式可以复用。
Sparkle 额外提供的版本比较、回退到完整包，这些自研都要么放弃要么自己写。
delta 按决定 7 本来就不做，所以自研方案在这一项上不比采用 Sparkle 少做什么。

**替换与重启。** 关键难点是**必须等主进程完全退出后才能替换**。一个辅助进程
（`Autoupdate` 那种 launchd 一次性任务）等待 PID 退出，替换 `.app`，再拉起新版本。
需要自己处理：

- 只读安装位置（`/Applications`）需要提权，且要走 `AuthorizationExecuteWithPrivileges`
  已被弃用的替代路径（`SMJobBless` / launchd job）；
- 替换时的原子性（新目录 + 原子 rename），失败要能回滚到旧版本；
- 崩溃恢复：更新中途断电或被杀时不能留下半个 app。

**这套东西正是 Sparkle 已经跑了十年的部分。** 自研的维护成本和出错风险都显著更高，
所以本 ADR 建议采用 Sparkle。这里的要点记录下来，是为了在将来有人问「为什么不自己写」
时有据可依。

## 安全

- 临时自签名证书、Ed25519 私钥和临时 keychain 全部生成在仓库外的 scratch 目录，
  **未进入仓库，未推送到任何地方**，spike 结束后已删除。两次运行用的是不同证书：
  第一版 `93CE188B…3A33CF`，CR 修订复验时新生成 `9EADA0E4…FFE810`（同样是
  仓库外生成、用完即删）。
- `security set-key-partition-list` 按 workflow 的做法执行；自签名证书不需要
  `add-trusted-cert`，用 SHA-1 就能签。
- Ed25519 私钥只经环境变量 / stdin 传递，不进 argv。
- 本地 appcast 服务只监听 `127.0.0.1`，spike 结束后已停止。
- **`build-app.sh` 现在会拒绝不安全的 feed 配置**：设置了 `PANESPACE_ED_PUBLIC_KEY`
  就必须同时给出 `PANESPACE_APPCAST_URL`，且必须是 `https://`。这样就不会出现
  「带了公钥但 feed 指向 `127.0.0.1`」的构建——那种构建在用户机器上只会一直
  检查失败。三个分支都实测过：缺 URL 报错、`http://` 报错、两者都不设时
  正常构建且不写 `SUFeedURL`。

## 参考

- Sparkle 2.10.0：`Documentation/Security.md`、`Documentation/Installation.md`、
  <https://sparkle-project.org/documentation/gentle-reminders>
- `SPUStandardUpdaterController.h`、`SPUUpdater.h`、`SPUUpdaterSettings.h`
- `SPUUpdaterDelegate.h`（`allowedChannelsForUpdater:` — 空集 = 只看 default 通道）
- `SPUStandardUserDriverDelegate.h`（`supportsGentleScheduledUpdateReminders`、
  `standardUserDriverShouldHandleShowingScheduledUpdate:andInImmediateFocus:`）
- `SPUUserUpdateState.h`（`SPUUserUpdateChoiceSkip`）、`SPUUserDriver.h`
- `SUSignatures.m`（EdDSA 签名解析与校验）
- `generate_appcast/Appcast.swift`（`downloadUrlPrefix` 施加于全部分组前的所有归档，
  决定 7 的依据）、`generate_appcast/ArchiveItem.swift`（`SURequireSignedFeed`
  决定 feed 是否签名——所以不设 `SUPublicEDKey` 的本地构建生成的 feed 不会签名）
- 阶段 1：NERE-18、`docs/adr/` 无（合入为 `0d2535b`）、`docs/RELEASING.md`
- 阶段 2：NERE-19（`UpdateModel`、`GitHubReleaseFeed`）
