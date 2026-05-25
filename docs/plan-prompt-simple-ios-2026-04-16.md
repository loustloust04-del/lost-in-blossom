# Plan: 设置 / Prompt / 简单 页面（iOS）

日期：2026-04-16

基于：

- [docs/research-prompt-simple-ios-2026-04-16.md](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/docs/research-prompt-simple-ios-2026-04-16.md)
- [docs/research-prompt-simple-page-2026-04-16.md](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/docs/research-prompt-simple-page-2026-04-16.md)（mac 想法挂起，不进入本轮）

---

## 目标

把 **iOS 的 `设置 → Prompt → 简单`** 做到下面这组明确行为：

1. 输入框初始高度小而自然。
2. 内容变多时，输入框跟着长高。
3. 长到上限后停止继续撑高，改为输入框内部滚动。
4. 删除内容后，输入框实时缩回。
5. 保留当前页面的外层结构和全屏编辑入口。
6. 不破坏 `iOSGeneralPage` 的间距节奏，也不顺手改 macOS。

---

## 范围

### 本轮会做

- 只改 iOS 路径
- 只改 Prompt 子页面的“简单”模式
- 引入一个 iOS 专用的多行输入组件，负责真实的高度/滚动控制
- 把当前 `iOSSimpleField` 接到新组件上
- 保留现有的 slot 保存逻辑和全屏编辑按钮

### 本轮不做

- 不改 macOS Prompt 简单模式
- 不统一整个设置页的 spacing system
- 不重做 Prompt 页面整体视觉结构
- 不改 `iOSGeneralPage`
- 不改 `SettingsTextField`
- 不改 `Theme.optionRowVerticalPadding` / `Theme.optionRowSpacing`

---

## 第一性原理判断

这个问题的核心不是“modifier 怎么凑”，而是：

**当前 iOS 需要一个真正的多行文本编辑控件，而不是继续赌 `TextField(axis: .vertical)`。**

因此本轮计划采用：

**`UITextView` + `UIViewRepresentable` 的小组件方案。**

组件边界只到“编辑器本体”，不吞掉 label、section、按钮、页面间距的控制权。

---

## 实施方案

### Step 1：新增 iOS 专用多行输入组件

新建一个小文件，例如：

- `MemoryPalace/Views/IOSPromptTextView.swift`

职责只包含：

- `@Binding var text`
- `placeholder`
- `minHeight`
- `maxHeight`
- 内部真实测量内容高度
- 小于上限时自适应高度
- 超过上限时固定高度并打开内部滚动
- 删除内容后重新测量并缩回

实现要求：

- 用 `#if os(iOS)` 隔离
- 基于 `UITextView`，不要再走 `TextField(axis: .vertical)`
- 组件内部维护稳定的 UIKit 实例，避免每次输入重建
- 需要有 Coordinator，处理：
  - text 同步
  - 高度变化回传
  - placeholder 显隐
  - 编辑过程稳定性

为什么单独文件而不是继续塞进 `SettingsView.swift`：

- 这次问题已经是一个独立控件行为问题
- 单独文件更方便审查和回退
- `project.yml` 目标 sources 直接收整个 `MemoryPalace/` 目录，新文件可以被收录；后续 build 前仍然会执行 `xcodegen generate`

### Step 2：保留 Prompt 页外层结构，只替换编辑器内核

文件：

- `MemoryPalace/Views/SettingsView.swift`

保留这些现有结构不动：

- `Section`
- 简单模式外层 `VStack`
- 单字段的 label + 全屏按钮 `HStack`
- preset / mode picker / 说明文字
- slotId 对应的绑定写回

只替换这一层：

- `iOSSimpleField` 里的 `TextField(axis: .vertical)`

替换后：

- `iOSSimpleField` 仍然负责外层排版
- 新组件只负责多行编辑行为

这样可以保证：

- 不影响 `iOSGeneralPage`
- 不把 spacing 决策塞进组件
- 页面结构改动尽量小

### Step 3：保持当前视觉语言，但把输入框行为做对

视觉上坚持“小步迭代”，不大改样式。

具体原则：

- 继续保留当前的中文 label
- 继续保留右侧全屏按钮
- 继续使用当前字体和暖奶白配色体系
- 输入框仍然是卡片样式，不引入 debug 感样式

这一步只允许做与行为直接相关的最小视觉调整：

- editor 内边距
- placeholder 位置
- 圆角与背景填充一致性
- 到达 maxHeight 后滚动条的可用性

### Step 4：间距策略保持局部，不动共享 token

这一轮不去“顺手统一所有设置页 spacing”。

具体策略：

- `iOSGeneralPage` 保持原样
- `SettingsTextField` 保持原样
- `Theme.optionRowVerticalPadding` 保持原样
- `Theme.optionRowSpacing` 保持原样

Prompt 简单模式的 spacing 只做局部校正：

- 如果当前 `20 / 6 / 10` 明显不协调，可以在 `SettingsView.swift` 内做小幅收敛
- 但不把这次改动上升为全局设计系统改造

原因：

- 这轮主任务是让输入框行为正确
- 共享 token 一旦改动，影响面会扩大到 `iOSGeneralPage` / `IOSAppearancePage`
- 这和你当前“先把 iOS 能用”的优先级不一致

### Step 5：同步保留全屏编辑作为兜底入口

当前全屏编辑入口已经存在，先不删。

要求：

- 原地输入和全屏输入要写回同一个 slot
- 从原地切到全屏，内容要同步
- 从全屏返回后，原地输入框状态正确

但注意：

- 全屏编辑不是主修复对象
- 它只是兜底体验，不能掩盖原地输入框本身不好用的问题

---

## 影响范围

### 直接影响文件

- `MemoryPalace/Views/SettingsView.swift`
- `MemoryPalace/Views/IOSPromptTextView.swift`（新文件，名称最终可微调）

### 间接验证文件

- `MemoryPalace/Views/GeneralSettingsTab.swift`
- `MemoryPalace/Views/AppearanceSettingsTab.swift`
- `MemoryPalace/Utils/Theme.swift`
- `project.yml`

### 明确不应产生行为变化的区域

- macOS 设置页
- iOS 通用页 `IOSGeneralPage`
- iOS 外观页 `IOSAppearancePage`
- Prompt 插槽模式 / JSON 模式 / 组装 / 请求页

---

## 关键风险与对应处理

### 风险 1：`List` 中可变高 cell 输入时抖动

处理：

- 让高度变化来自稳定的 UIKit 文本视图实例
- 避免每次文字变化都导致整个 field identity 变化
- 不在高度回调里做多余动画

### 风险 2：每次输入都会 `psm.save(p)`，导致光标跳动或中文输入法异常

处理：

- 组件层必须保证 `UITextView` 不被频繁重建
- `updateUIView` 只在文本真正不同步时回写
- 谨慎处理 first responder 和 selection

### 风险 3：超过上限后只会长大，不会缩回

处理：

- 高度计算每次文本变更都重新执行
- 当内容高度重新低于阈值时，关闭内部滚动并回落 frame 高度
- 把“删除后缩回”作为单独验证项，不视为自动成立

### 风险 4：为了修行为，误伤了页面间距

处理：

- 外层布局保留在 `SettingsView.swift`
- 新组件不内置 section / row 布局
- 不改 `iOSGeneralPage` / `SettingsTextField`

---

## 验证方案

### 构建验证

1. `xcodegen generate`
2. `xcodebuild -scheme MemoryPalaceIOS build`
3. `xcodebuild -scheme MemoryPalace build`

说明：

- 新文件加入后，先 regenerate project，再 build
- macOS 也要过一遍，确保 iOS-only 组件没有误伤另一端

### 交互验证

至少验证以下场景：

1. 在“系统指令”连续输入，输入框逐步长高。
2. 长到阈值后不再继续撑开，改为内部滚动。
3. 删除大量文本后，输入框逐步缩回初始高度。
4. 中文输入法连续输入时，光标和候选不乱跳。
5. 五个字段都能正常编辑，不只第一个有效。
6. 点击全屏按钮进入编辑，再返回，内容同步正常。
7. 切换到“插槽 / JSON / 组装 / 请求”再切回“简单”，内容仍同步。
8. `IOSGeneralPage` 的行距、按钮、输入框外观不变化。

---

## 实施顺序

1. 新建 iOS 多行输入组件文件。
2. 在组件内完成高度/滚动/placeholder 基础行为。
3. 接入 `iOSSimpleField`，替换当前 `TextField(axis: .vertical)`。
4. 小范围校正 Prompt 简单模式的局部 spacing 和样式。
5. 跑 iOS / macOS build。
6. 做交互验证，重点看“删除后缩回”和中文输入法稳定性。

---

## Todo

- [x] 新建 iOS 专用多行输入组件文件
- [x] 用 `UITextView + UIViewRepresentable` 实现动态长高 / 上限后内滚 / 删除后缩回
- [x] 实现 placeholder 显隐与稳定文本同步
- [x] 确保组件实例稳定，不因每次输入被重建
- [x] 在 `SettingsView.swift` 的 `iOSSimpleField` 中接入新组件
- [x] 保留现有 label / 全屏按钮 / slot 写回逻辑
- [ ] 只做 Prompt 简单模式局部 spacing 微调，不改共享 token
- [x] `xcodegen generate`
- [x] `xcodebuild -scheme MemoryPalaceIOS build`
- [x] `xcodebuild -scheme MemoryPalace build`
- [ ] 手动验证长高 / 封顶 / 内滚 / 缩回 / 全屏同步 / 中文输入

---

## 状态

已进入实现并完成代码改动与编译验证。

2026-04-16 追加修复：

- 简单模式已从“每个字符直接 `psm.save`”改为“页面本地草稿 + 延迟落盘”
- 切预设、切模式、离开页面、全屏完成都会先 flush 当前草稿
- 这一轮的目的就是压掉“回车被冲掉 / 输入框刚撑高又闪回去”这类刷新型问题
- 继续在 `UITextView` 组件内去掉高度变化的隐式动画，并补 caret 可见性维护，目标是压掉“长高缩回卡卡的 / 光标经常出去”

未完成项：

- Prompt 简单模式的局部 spacing 微调（当前保持原样）
- 手动交互验证（长高 / 封顶 / 内滚 / 缩回 / 中文输入 / 全屏同步）
