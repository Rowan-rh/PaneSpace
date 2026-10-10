## Purpose

让分栏视图的左方向键和访达一致，只把焦点移回上一列，保留用户逐列建立的浏览上下文。

## ADDED Requirements

### Requirement: 左方向键返回上一列时保留分栏

分栏视图中，当前列不是首列时按左方向键，系统 SHALL 把选择和焦点移到上一列中打开当前列的那个文件夹。上一列及其左侧的所有列 SHALL 保持显示；当前列 SHALL 继续显示该文件夹的内容，但清除其中的选择；当前列之后的列 SHALL 被移除。此操作 SHALL 不重新加载任何目录。

#### Scenario: 从第三列返回第二列

- **WHEN** 分栏显示 Left → Alpha → Beta 三列，焦点在 Beta 列且其中选中了 Gamma，用户按左方向键
- **THEN** Left、Alpha、Beta 三列仍然显示，焦点在 Alpha 列且 Beta 被选中，Beta 列中没有选中项，Gamma 列（如有）被移除

#### Scenario: 连续返回直到首列

- **WHEN** 用户在上述状态下再按一次左方向键
- **THEN** Left 和 Alpha 两列仍然显示，焦点在 Left 列且 Alpha 被选中

#### Scenario: 返回后再按右方向键

- **WHEN** 用户按左方向键回到上一列后，立即按右方向键
- **THEN** 焦点重新进入刚才的列并选中其中第一项，不新增重复的列
