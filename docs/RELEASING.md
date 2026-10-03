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

在仓库 Settings → Secrets and variables → Actions 中新增三个 secret：

```bash
base64 -i < ~/PaneSpace-signing/panespace-signing.p12 | tr -d '\n'
cat ~/PaneSpace-signing/panespace-signing-pass.txt
cat ~/PaneSpace-signing/ed25519-private-key.txt
```

三个 secret 的名字分别是 `PANESPACE_CERT_P12_BASE64`、`PANESPACE_CERT_P12_PASSWORD`、`PANESPACE_ED25519_PRIVATE_KEY`。

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

3. `push` tag 触发 `.github/workflows/release.yml`：跑测试 → 从 tag 派生版本 → 在临时 keychain 中导入证书 → 签名构建 → 校验签名 → 打包 → 生成 `.sha256` 和 `.sig` 并验签 → 上传到对应 Release。Release 不存在时创建 **draft**，tag 含 `-` 时标记为 prerelease。
4. 在 GitHub 上检查 draft Release 的发行说明，**手动点击发布**。
5. （可选）删掉本机测试 keychain。

## 版本与构建号

`scripts/version-from-tag.sh` 从 tag 派生 `CFBundleShortVersionString` 和 `CFBundleVersion`：

```text
MAJOR * 1000000 + MINOR * 10000 + PATCH * 100 + (正式版 99 / 预发布序号 1–98)
```

| tag | CFBundleShortVersionString | CFBundleVersion |
| --- | --- | --- |
| `v0.2.0-beta.1` | `0.2.0-beta.1` | `20001` |
| `v0.2.0-beta.2` | `0.2.0-beta.2` | `20002` |
| `v0.2.0-rc.1` | `0.2.0-rc.1` | `20001` |
| `v0.2.0` | `0.2.0` | `20099` |

构建号确定且单调递增，正式版的 99 保证排在同一版本的全部预发布之后。预发布标识只接受 `<alpha|beta|rc>.<N>`（N 为 1–98），其余形式（如 `v0.2.0-beta`、`v0.2.0-preview.1`、`v0.2`）直接失败，不会产生错误版本的应用。

## 本地构建

本地开发流程不变。`make app` / `scripts/build-app.sh` 不设置任何环境变量时行为与之前完全一致：版本 0.1.2、构建号 3、ad-hoc 签名。

需要手工验证签名构建时：

```bash
PANESPACE_VERSION=0.2.0 \
PANESPACE_BUILD=20099 \
PANESPACE_SIGN_IDENTITY="PaneSpace Self-Signed" \
PANESPACE_ED_PUBLIC_KEY="$(cat ~/ed25519-public-key.txt)" \
make app
```

`PANESPACE_SIGN_KEYCHAIN` 可指定临时 keychain 路径；不设置时使用系统默认 keychain 搜索列表。

## 为什么需要自签名证书

ad-hoc 签名的 designated requirement 等于 cdhash，即**每次构建都变**。系统据此判定「这是一个新应用」，于是每次更新后桌面、文稿、下载、可移除卷等 TCC 授权都会失效，用户必须重新授权。用固定的证书签名后，designated requirement 变成：

```text
designated => identifier "org.panespace.app" and certificate root = H"..."
```

发布 workflow 会在 designated requirement 里出现 `cdhash` 时直接失败，防止回归到 ad-hoc 状态。

## 已知限制

- **未公证**：应用没有 Apple 公证票据。用户**首次安装**必须在「系统设置 › 隐私与安全性」中点「仍要打开」，或 Control-点按应用选择「打开」。这不是签名失效，是 Gatekeeper 的正常行为。
- **从 0.1.2 升级需重新授权一次**：0.1.2 是 ad-hoc 签名且没有更新器，升级到第一个证书签名的版本时会重置一次授权，之后的更新保持不变。
- **更换或过期证书需要重新授权**：所有已安装的 PaneSpace 都会失去信任，需要用户手动重新授权。10 年有效期就是为了避免这件事，但备份好证书仍然重要。
- **不做公证意味着没有时间戳**：签名时间以构建机器时间为准。发布前请确认 runner 时钟正确。
- **应用内更新尚未实现**：当前阶段只完成签名与发布自动化，检查更新与应用内更新是后续阶段的工作。

## 安全注意事项

- 证书和私钥**不进入仓库**，只以 GitHub Actions secret 形式保存。
- workflow 日志不打印密钥、密码或本机绝对路径。
- 发布 job 与构建 job 分离：上传 job 只有 `contents: write` 权限，看不到证书和私钥；上传前会重新验签并核对 SHA-256。
- 临时 keychain 使用随机密码，并在 job 结束时无条件删除（`if: always()`）。
