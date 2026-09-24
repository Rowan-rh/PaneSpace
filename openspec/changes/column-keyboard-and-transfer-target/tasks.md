## 1. 分栏左方向键

- [x] 1.1 改写 `returnToPreviousColumnFromKeyboard`，原地截断列并移回选择；更新现有列导航测试，验证三列返回后仍保留左侧列、当前列无选择，再按右方向键回到同一列且不新增列。
- [x] 1.2 在 App 中实测 Left → Alpha → Beta → Gamma 连续按左、右方向键时的列与焦点。

## 2. 传输目标与权限提示

- [x] 2.1 新增 `transferDestinationURL` 并在 `AppModel.transfer` 中使用；用模型测试验证分栏中选中未打开的文件夹、子列选中文件和列表视图三种情况。
- [x] 2.2 在 `LocalTransferService.validate` 中增加可写检查、新错误及中文文案；用只读临时目录测试任务失败、源文件保留且目标中没有临时项。
- [x] 2.3 在 App 中实测：目标面板分栏选中文件夹时复制到上一级目录；复制到只读目录时显示明确提示。

## 3. 验证

- [x] 3.1 运行 `swift test`、`make app`、严格签名检查和 `openspec validate column-keyboard-and-transfer-target --strict`，全部通过且无新警告。

验证记录：`swift test` 共 66 项通过；`make app`、严格签名检查和 `openspec validate --strict` 通过。在当前构建中实测：Left → Alpha → Beta → Gamma 连续按左方向键时，左侧列保留，焦点逐列后退并自动滚动到可见位置，再按右方向键回到原列；目标面板分栏选中 Beta（未打开）时，“移动到下一个面板”把文件放进 Alpha；移动到只读的 Locked 时，传输栏显示“没有写入“Locked”的权限。”，源项保留且无临时项。实测中顺带修复了分栏空列标题被垂直居中的布局问题。“复制到下一个面板”的菜单和快捷键被测试工具当作剪贴板操作拦截，未能直接触发；它与移动共用同一目标逻辑，已由模型测试覆盖。
