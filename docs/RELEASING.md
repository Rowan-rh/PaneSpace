# 发布流程

本文说明 PaneSpace 的签名与发布流程。签名使用**免费的自签名代码签名证书**，不购买 Apple Developer Program，也不做公证。

## 一次性准备

### 1. 生成签名材料

在自己的 Mac 上运行（不要在 CI 或共享机器上运行）：

```bash
./scripts/generate-signing-identity.sh ~/PaneSpace-signing
```

脚本会在指定目录生成（目录权限 700，文件权限 600）：

| 文件 | 内容 | 去向 |
| --- | --- | --- |
| `panespace-signing.p12` | 10 年期自签名代码签名证书 | secret `PANESPACE_CERT_P12_BASE64` |
| `panespace-signing-pass.txt` | 随机生成的 .p12 密码 | secret `PANESPACE_CERT_P12_PASSWORD` |
| `ed25519-private-key.txt` | Ed25519 私钥（32 字节 seed，base64） | secret `PANESPACE_ED25519_PRIVATE_KEY` |
| `ed25519-public-key.txt` | Ed25519 公钥（32 字节，base64） | 提交到 `scripts/update-public-ed25519.txt` |

证书的关键参数：`CN=PaneSpace Self-Signed`、`extendedKeyUsage=codeSigning`、`keyUsage=digitalSignature`、有效期 10 年。生成脚本会校验这些扩展，并实际调用 `security import` 确认 .p12 可用。

**私钥不会进入仓库，也不会进入任何 agent 的工作目录。** 脚本拒绝写入仓库内部。

### 2. 创建仓库 secrets

生成脚本结束时会打印现成的命令，直接把文件管道给 `gh`，secret 不会进入 shell 历史或剪贴板：

```bash
gh secret set PANESPACE_CERT_P12_BASE64 --repo Rowan-rh/PaneSpace \
  < <(base64 -i ~/PaneSpace-signing/panespace-signing.p12 | tr -d '\n')
gh secret set PANESPACE_CERT_P12_PASSWORD --repo Rowan-rh/PaneSpace \
  < ~/PaneSpace-signing/panespace-signing-pass.txt
gh secret set PANESPACE_ED25519_PRIVATE_KEY --repo Rowan-rh/PaneSpace \
  < ~/PaneSpace-signing/ed25519-private-key.txt
gh secret set PANESPACE_APPCAST_URL --repo Rowan-rh/PaneSpace \
  --body "https://raw.githubusercontent.com/Rowan-rh/PaneSpace/appcast/appcast.xml"
```

前三个来自上一步生成的目录；**第四个不是**，它是一个固定 URL：

```text
https://raw.githubusercontent.com/Rowan-rh/PaneSpace/appcast/appcast.xml
```

它指向 `appcast` 分支上的 `appcast.xml`——那是 `publish-appcast` job 写入的唯一一份
feed，也是 `publish` job 作为 Release 附件上传的同一份文件。首次发布时这个分支
还不存在，URL 先填好即可；分支建立之前任何一次检查更新都会失败，发布流程不会走到
那一步。写成 secret 而不是常量是因为 URL 将来可能换载体（Pages、固定 tag 的资产），
而换载体不应该需要改代码；发布 workflow 要求它以 `https://` 开头。

注意 `base64 -i` 的参数是**文件名**，不能写成 `base64 -i < file`（那样会报 `option requires an argument -- i`）。

### 3. 提交公钥

公钥是公开值，提交到 `scripts/update-public-ed25519.txt`（仓库内当前是占位符）：

```bash
cat ~/PaneSpace-signing/ed25519-public-key.txt > scripts/update-public-ed25519.txt
```

这个公钥会被写入应用包 Info.plist 的 `SUPublicEDKey`，应用内更新时用它验签。**公钥一旦提交就不能再改**：改了之后，旧版本应用无法验证新版本的签名。

提交后确认 workflows 显示检查通过（`actionlint` 见下）：

```bash
actionlint .github/workflows/*.yml
```

### 4. 清理本地材料

```bash
rm -rf ~/PaneSpace-signing
```

## 每次发布

1. 确认 `develop` 已合入 `main` 且 CI 通过。
2. 打 tag（**tag 是版本的唯一来源**）：

   ```bash
   git tag v0.2.0
   git push origin v0.2.0
   ```

3. `push` tag 触发 `.github/workflows/release.yml`：跑测试 → 从 tag 派生版本 → 在临时 keychain 中导入证书 → 签名构建 → 校验签名 → 打包 → 生成 `.sha256` 和 `.sig` 并验签 → 上传到对应 Release。Release 不存在时创建 **draft**，tag 含 `-` 时标记为 prerelease。已有的 draft 或正式 Release 会**追加**（覆盖同名）资产，所以同一个 tag 重跑不会产生重复 draft。appcast.xml 也作为附件上传到 Release，供第 4 步取用。
4. 在 GitHub 上检查 draft Release 的发行说明，**手动点击发布**。

   点击发布的同时，GitHub 触发 `release: published` 事件，同一个 workflow 再跑一次，只执行 `publish-appcast` job：它从刚公开的 Release 上取回 appcast.xml，确认 appcast 里这个 tag 的每个下载地址（zip 和 delta）都能匿名访问并返回 HTTP 200，然后才提交到 `appcast` 分支。

   **appcast 只在 Release 公开之后才发布。** draft 的附件对匿名访问返回 404，如果在打 tag 的那一次运行里就提交 appcast，从建 draft 到你点发布之间，所有已安装的用户都会看到更新横幅、点下去却下载失败；如果这个 draft 最后不发，appcast 还会一直推荐一个永远下不到的版本。draft 本身仍然挡住了自动发版：坏 tag 到不了这一步，必须有人先读过发行说明。

   **appcast 在 tag 推送时就生成好了，几天后才提交。** 为了让提交方知道这份快照是不是已经过期，build 会把它当时读到的 `appcast` 分支提交记到 `appcast-base.txt`（分支还不存在时记 `none`），一起作为附件上传。`publish-appcast` fetch 之后会比对：分支 HEAD 与记录不一致就报错退出，不会写入。场景是有两个 draft 同时挂着，先发布 B 再发布先打的 A，A 的快照里没有 B 的条目，整份覆盖就会把 B 从 feed 里抹掉。

   如果 `publish-appcast` job 失败，`appcast` 分支保持原样，旧版本用户继续正常更新，不会看到一个坏掉的新版本。

   **重跑前先读这一条。** Actions 上的 Re-run 会重新构建并重新上传资产，而上传用的是
   `gh release upload --clobber`——也就是用新构建的 zip / sha256 / sig **替换** Release 上
   已经公开的那一份。Release 已经公开、用户已经下载过的话，重跑会让他们手里的文件和
   之前下载的静默对不上。确认新旧一致再重跑。

   按错误信息恢复：

   | 报错 | 恢复步骤 |
   | --- | --- |
   | `The appcast branch is now at …, but this appcast was built on …` | 快照已过期。在 Actions 上找到这个 tag 的那次运行，Re-run all jobs（会按当前分支 HEAD 重新生成 appcast.xml 和 appcast-base.txt 并覆盖上传），再到 `release: published` 那次运行上 Re-run 这个 job。 |
   | `The appcast branch does not exist, but this appcast was built on …` | 分支被删了。同样先 Re-run 这个 tag 的构建，再重跑发布 job。 |
   | `carries no appcast-base.txt` | 这个 Release 是旧版 workflow 建的，没有 base 附件。同样先 Re-run 这个 tag 的构建，再重跑发布 job。 |
   | `answered HTTP 404` | 刚公开时 CDN 可能短暂返回 404。重跑这个 job 即可；持续失败说明 Release 上的附件确实缺失，回上一条处理。 |
   | 在 Actions 页面上看到这次运行显示为取消 | 所有发布运行共用一个 concurrency 组，GitHub 在同一组里最多保留 1 个排队中的运行，排在 build 后面的发布运行可能被后来的运行顶掉。重跑这次发布运行即可。 |
   | 重跑入口不见了（运行超过 30 天） | 用 workflow 的 **Run workflow** 手动补跑，见下。

   ### 超过 30 天后的补跑入口

   GitHub 只允许重跑 30 天内的工作流运行，更早的连 Re-run 按钮都没有。为此
   `.github/workflows/release.yml` 开了 `workflow_dispatch`，**它只是上面这些恢复步骤的手动
   入口，不新增任何自动发布路径**——只有人在 Actions 页面上点「Run workflow」才会触发，
   跑的内容与对应的事件触发运行完全一样。

   在 Actions 里打开 Release workflow → Run workflow，填两个输入：

   | 输入 | 说明 |
   | --- | --- |
   | `job` | `build` 重新签名、打包并上传资产（`publish` job 会跟着跑）；`publish-appcast` 只重新提交 feed |
   | `tag` | 要补跑的 tag，例如 `v0.2.0`，必须与 Release 上现有的 tag 完全一致 |

   选 `job: build` 等价于当年的 Re-run all jobs，**同样带 `--clobber`**，先读上面那条警告
   再决定。选 `job: publish-appcast` 是补跑那半边：重新检查 Release 是否已公开、重新下载
   它携带的 appcast 和 base，再提交到 `appcast` 分支。

   手动补跑不绕过任何检查：Release 必须是公开状态，feed 里这个 tag 的每个下载地址必须
   当场返回 200，且 feed 的基线提交必须与 `appcast` 分支当前 HEAD 一致，否则照样报错退出。

发布过程全在 CI 上完成，本机不生成 keychain，也不需要本地清理。

## 版本与构建号

`scripts/version-from-tag.sh` 从 tag 派生 `CFBundleShortVersionString` 和 `CFBundleVersion`：

```text
MAJOR * 1000000 + MINOR * 10000 + PATCH * 100 + channel
```

Sparkle 按 `CFBundleVersion` 的**各段数值**比较新旧（不是按字符串字典序），所以最后一段 `channel` 负责给预发布通道排序。每个通道占一段独立区间，互不重叠：

| 通道 | channel 取值 |
| --- | --- |
| `alpha.1` – `alpha.29` | +1 – +29 |
| `beta.1` – `beta.29` | +30 – +58 |
| `rc.1` – `rc.38` | +60 – +97 |
| 正式版 | +99 |

| tag | CFBundleShortVersionString | CFBundleVersion |
| --- | --- | --- |
| `v0.2.0-alpha.1` | `0.2.0-alpha.1` | `20001` |
| `v0.2.0-alpha.29` | `0.2.0-alpha.29` | `20029` |
| `v0.2.0-beta.1` | `0.2.0-beta.1` | `20030` |
| `v0.2.0-beta.29` | `0.2.0-beta.29` | `20058` |
| `v0.2.0-rc.1` | `0.2.0-rc.1` | `20060` |
| `v0.2.0-rc.38` | `0.2.0-rc.38` | `20097` |
| `v0.2.0` | `0.2.0` | `20099` |

即 `alpha.29 < beta.1 < beta.29 < rc.1 < rc.38 < 正式版`，装了 beta.2 的用户一定能收到 rc.1。59 和 98 是刻意留空的分隔位，避免误打的 tag 落在已发布过的构建号上。

以下 tag 直接失败，不会产生错误版本的应用：

- `MINOR` 或 `PATCH` ≥ 100（如 `v0.1.100`、`v0.99.100`）——会溢出到下一段，与其他版本撞号。
- `0.0.x`（如 `v0.0.0`）——语义上低于已发布的 0.1.2，不允许发布。
- 预发布号超出所属区间（如 `v0.2.0-alpha.30`、`v0.2.0-beta.30`、`v0.2.0-rc.39`）。
- 标识不符合 `<alpha|beta|rc>.<N>`（如 `v0.2.0-beta`、`v0.2.0-preview.1`、`v0.2.0-rc.0`）。
- 版本段数不对（`v0.2`、`v0.2.0.1`）、缺 `v` 前缀（`0.2.0`）或有前导零（`v01.2.0`）。

## 本地构建

本地开发流程不变。`make app` / `scripts/build-app.sh` 不设置任何环境变量时行为与之前完全一致：版本 0.1.2、构建号 3、ad-hoc 签名。

需要手工验证签名构建时（身份可用证书 SHA-1 代替名字，自签名证书无需额外信任设置）：

```bash
PANESPACE_VERSION=0.2.0 \
PANESPACE_BUILD=20099 \
PANESPACE_SIGN_IDENTITY="PaneSpace Self-Signed" \
PANESPACE_ED_PUBLIC_KEY="$(cat scripts/update-public-ed25519.txt)" \
PANESPACE_APPCAST_URL="https://raw.githubusercontent.com/Rowan-rh/PaneSpace/appcast/appcast.xml" \
make app
```

`PANESPACE_APPCAST_URL` 不能省：**设了 `PANESPACE_ED_PUBLIC_KEY` 的构建必须同时给出
feed URL，否则 `scripts/build-app.sh` 直接报错退出。** 没有它就会产出一个带着公钥
却没有 feed 的包——那种包在用户机器上每次检查更新都会失败，而且失败得毫无道理。
本地想喂一个 `http://127.0.0.1` 的 appcast 做端到端验证时，可以额外设
`PANESPACE_APPCAST_ALLOW_LOCALHOST=1`；它只放行 `127.0.0.1`，脚本会打印两行警告，
而且**release workflow 明令禁止设置它**。

`PANESPACE_SIGN_KEYCHAIN` 可指定临时 keychain 路径；不设置时使用系统默认 keychain 搜索列表。

打完的 bundle 可以直接跑打包后启动冒烟测试（会启动应用 10 秒，检查 Sparkle 已加载、
无 dyld 报错、`DYLD_INSERT_LIBRARIES` 被忽略）：

```bash
./scripts/launch-smoke-test.sh
```

## 为什么需要自签名证书

ad-hoc 签名的 designated requirement 等于 cdhash，即**每次构建都变**。系统据此判定「这是一个新应用」，于是每次更新后桌面、文稿、下载、可移除卷等 TCC 授权都会失效，用户必须重新授权。用固定的证书签名后，designated requirement 变成：

```text
designated => identifier "org.panespace.app" and certificate leaf = H"..."
```

（自签名证书的叶子证书就是它自己的根，所以 `codesign` 给出的就是 `leaf` 这一种形式；
换成真正的 CA 签发的证书时，同一位置可能写成 `certificate root`，两种都表示「不是
按每次构建变化的 cdhash」。）

发布 workflow 会在 designated requirement 里出现 `cdhash` 时直接失败，防止回归到 ad-hoc 状态。

## 已知限制

- **未公证**：应用没有 Apple 公证票据。用户**首次安装**必须在「系统设置 › 隐私与安全性」中点「仍要打开」，或 Control-点按应用选择「打开」。这不是签名失效，是 Gatekeeper 的正常行为。
- **从 0.1.2 升级需重新授权一次**：0.1.2 是 ad-hoc 签名且没有更新器，升级到第一个证书签名的版本时会重置一次授权，之后的更新保持不变。
- **更换或过期证书需要重新授权**：所有已安装的 PaneSpace 都会失去信任，需要用户手动重新授权。因为签名用 `--timestamp=none`，签名没有可信时间戳，证书一旦过期签名就不再有效；10 年有效期到期前需要换发新证书并重新发布，**换证书本身就会让所有用户重新授权一次**。

## 安全注意事项

- 证书和私钥**不进入仓库**，只以 GitHub Actions secret 形式保存。
- workflow 日志不打印密钥、密码或本机绝对路径。Ed25519 私钥只经环境变量传给签名脚本，不进 argv。
- 发布 job 与构建 job 分离：上传 job 只有 `contents: write` 权限，看不到证书和私钥；上传前会重新验签并核对 SHA-256。
- 公开的 appcast 分支只在 Release 公开之后由 `publish-appcast` job 写入，写入前用不带凭据的请求确认该 Release 的下载地址全部返回 200，避免 feed 推荐一个下载不到的版本。
- 临时 keychain 使用随机密码，密码经 `::add-mask::` 屏蔽且**不写入** `$GITHUB_OUTPUT`；keychain 与中间文件按固定路径在 job 结束时无条件删除（`if: always()`），即使导入失败也能清理。
- 签名身份用证书 SHA-1 传入，**不调用 `security add-trusted-cert`**：自签名证书不写入任何 trust settings 域，因此不会在 runner 上留下无法清理的信任残留。
