## 1. 选择逻辑

- [x] 1.1 新增 `ItemSelection` 值类型：单击、Command 切换、Shift 范围、键盘移动/扩展、全选；锚点与当前项在外部改变选择后能自动重新推断。
- [x] 1.2 `BrowserPaneModel` 接入列表键盘选择和分栏修饰键点按；多选时截断子列，只剩一个文件夹时重新展开。
- [x] 1.3 单元测试覆盖范围选择、切换、扩展/收缩、全选、搜索过滤与分栏多选。

## 2. 界面

- [x] 2.1 列表视图处理上下、Shift+上下和 Command-A，并滚动到当前项。
- [x] 2.2 分栏视图行点按读取修饰键；Shift+上下与 Command-A 作用于活动列；多选行高亮。

## 3. 验证

- [x] 3.1 `swift test`、`make app`、签名检查、`openspec validate multi-item-selection --strict`。
- [x] 3.2 在 macOS 上实测列表与分栏视图、单面板与双面板。

验证记录：`swift test -Xswiftc -warnings-as-errors` 共 91 项通过；`make app` 与严格签名检查通过；`openspec validate --strict` 通过。在隔离配置的开发版中实测：列表视图 Shift 点按、Command 点按、上下键、Shift+上下键扩展与收缩、Command-A；分栏视图 Shift 点按范围（子列自动收起）、Command 点按取消、Shift+上下键与 Command-A；双面板和单面板布局均检查。
