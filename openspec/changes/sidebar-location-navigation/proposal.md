## Why

用户反馈，点击侧栏“个人收藏”中的位置没有反应。侧栏的每一行都是放在可选择列表里的纯文本样式按钮，只有点在文字或图标上才会触发；点在行内其他位置，只会改变列表的选中状态，而选中状态没有触发任何导航。

## What Changes

- 侧栏位置行改为普通的可选择标签，由列表选中触发在活动面板中打开该位置。
- 侧栏高亮与活动面板的当前位置同步：面板离开该位置时取消高亮，回到侧栏中的某个位置时自动高亮，这样再次点击同一位置仍能打开。

## Capabilities

### New Capabilities
- `sidebar-location-navigation`: 点击侧栏位置在活动面板中打开，并让高亮跟随当前位置。

### Modified Capabilities

## Impact

- `SidebarView` 去掉行内按钮，改为监听选择与当前位置。
- `AppModel` 新增 `openSidebarLocation` 与 `syncSidebarSelection`。
- 新增 `SidebarNavigationTests`。
