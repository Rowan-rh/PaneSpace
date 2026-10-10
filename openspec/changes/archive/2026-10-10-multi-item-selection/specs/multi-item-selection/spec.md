## Purpose

让用户像在访达中一样，用鼠标修饰键和键盘在列表与分栏视图中选择多个项目。

## ADDED Requirements

### Requirement: 连续范围选择

按住 Shift 点按项目时，系统 SHALL 选中从选择锚点到该项目之间（按当前显示顺序）的全部项目。锚点是最近一次不带 Shift 的点按或键盘移动所选中的项目。在分栏视图中，范围 SHALL 限定在同一列内。

#### Scenario: 列表中 Shift 点按

- **WHEN** 用户点按第 1 项，再按住 Shift 点按第 4 项
- **THEN** 第 1 至第 4 项被选中，其他项目不被选中

#### Scenario: 分栏中 Shift 点按

- **WHEN** 用户在分栏视图某列点按一项，再按住 Shift 点按同列的另一项
- **THEN** 两项之间（含两端）的项目都被选中，且不展开任何子列

### Requirement: 非连续选择

按住 Command 点按项目时，系统 SHALL 将该项目加入选择；若它已被选中，则取消选择，且不影响其他已选项目。

#### Scenario: Command 点按添加与取消

- **WHEN** 已选中第 1 项，用户按住 Command 依次点按第 3 项和第 1 项
- **THEN** 只有第 3 项保持选中

### Requirement: 键盘选择

文件内容获得键盘焦点时，上下方向键 SHALL 把选择移到上一项或下一项；Shift+上下方向键 SHALL 以锚点为基准扩展或收缩连续选择；Command-A SHALL 选中当前列表（分栏视图为当前列）的全部可见项目。文本输入框中的这些按键 SHALL 保持系统默认行为。

#### Scenario: Shift+下箭头扩展选择

- **WHEN** 选中第 2 项后连按两次 Shift+下箭头
- **THEN** 第 2 至第 4 项被选中

#### Scenario: 反向收缩

- **WHEN** 从第 2 项扩展到第 4 项后按 Shift+上箭头
- **THEN** 第 2 至第 3 项被选中

#### Scenario: 全选

- **WHEN** 文件列表获得焦点时按 Command-A
- **THEN** 所有可见项目被选中，被搜索过滤掉的项目不被选中
