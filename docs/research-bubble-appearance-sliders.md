# Research: 气泡外观自定义 slider/toggle

> 2026-04-22 · cc
> 分支：`codex/theme-kelivo-settings`
> 起因：粟粟说聊天页"太死板"，想给外观加几个滑条/开关

## 目标

外观设置里**新增一组控件**（平时折叠），控制气泡视觉：

**Sliders**：
1. 气泡圆角（bubbleCornerRadius）
2. 气泡内边距（bubblePadding）
3. 气泡间距（bubbleSpacing / LazyVStack spacing）
4. 字号（已有 `fontScale`，复用）
5. 行间距（lineSpacingScale）
6. 分段间距（paragraphSpacingScale）

**Toggles**：
7. 隐藏时间戳
8. 隐藏用户/助手名
9. 隐藏底下小按钮行（编辑/复制/收藏/pin/删除）

**交互**：这组控件默认**折叠**（用 DisclosureGroup 或单独"高级"子页），不影响日常体验。

---

## 当前状态清点（每个控制点的源码位置）

### 1. 气泡圆角
- 定义：`MemoryPalace/Utils/Theme.swift:32` — `static let bubbleCornerRadius: CGFloat = 16`
- 使用：`CardFlowView.swift:1215, 1219, 1224`（background + 2 overlay RoundedRectangle）

### 2. 气泡内边距
- 定义：`Theme.swift:33` — `static let bubblePadding: CGFloat = 14`
- 使用：`CardFlowView.swift:1212` — `.padding(.horizontal, Theme.bubblePadding)`
- ⚠️ 还有 `.padding(.vertical, 10)` 硬编码在 L1213（**不是**走 Theme.bubblePadding）

### 3. 气泡间距
- 定义：无常量。`CardFlowView.swift:185` — `LazyVStack(spacing: 22)` 硬编码
- Theme 里有 `static let bubbleSpacing: CGFloat = 6` 但**没被 CardFlowView 用**（SidebarView 等用）

### 4. 字号
- 定义：`@AppStorage("fontScale") var fontScale = 1.0`（已有）
- 使用：
  - `CardFlowView.swift:1119, 1151` — TextField / Text 用户侧 `FontManager.font(size: 13.5)`
  - `CardFlowView.swift:1154` — `.lineSpacing(4 * fontScale)`（用户侧）
  - `CardFlowView.swift:1186` — `.markdownTheme(.memoryPalace(..., scale: fontScale))`
  - `MarkdownTheme.swift:13` — `FontSize(13.5 * scale)`
  - `AppearanceSettingsTab.swift:97, 254` — 已有 slider（0.5...2.0, step 0.05）

### 5. 行间距
- **用户侧**：`CardFlowView.swift:1154` — `.lineSpacing(4 * fontScale)` 硬编码 4pt × fontScale
- **助手侧 Markdown**：`MarkdownTheme.swift:69` — `.relativeLineSpacing(.em(0.42))` 硬编码

两处源头，需要统一一个 scale 变量。

### 6. 分段间距
- 只对 markdown paragraph 生效（user text 没有多段）：
- `MarkdownTheme.swift:70` — `.markdownMargin(top: 0, bottom: 12)` 硬编码 12pt

### 7. 时间戳显示
- `CardFlowView.swift:1099-1103` — `if let time = node.createTime { Text(time.formatted(...)) }`

### 8. 用户/助手名显示
- `CardFlowView.swift:1096-1098` — `Text(isUser ? userName : assistantName)`
  - 注意：用户/助手名本身的 text 来自 `@AppStorage("userName") / "assistantName"`（GeneralSettingsTab 配置）
  - 这个开关控制是否**显示整个 Text**

### 9. 小按钮行（HoverButtons）
- `CardFlowView.swift:1282-1301` — `HoverButtons(...)` mount
- `CardFlowView.swift:1314-1384` — struct 定义
- macOS：`#if os(macOS) .opacity(isHovered ? 1 : 0)` — hover 才显示
- iOS：永远 opacity 1（HoverButtons 没 iOS 隐藏开关，always visible）
- 这个 toggle 控制是否 render 整个 HoverButtons

### 外观 tab 位置
- `MemoryPalace/Views/AppearanceSettingsTab.swift` — 两份实现：
  - macOS `AppearanceSettingsTab`（VStack-based，L6-187）
  - iOS `IOSAppearancePage`（List+Section-based，L192-312）
- 现有 section 顺序：字体 / 聊天字号 / 消息显示（展开全文 + 边缘模糊）
- 新增的这组控件要加一个 section，用 DisclosureGroup 平时折叠

---

## 新增 @AppStorage 键（提议）

| 键 | 默认值 | 类型 | 范围 | step |
|---|---|---|---|---|
| `bubbleCornerRadius` | 16 | Double | 0...28 | 1 |
| `bubblePaddingH` | 14 | Double | 8...24 | 1 |
| `bubblePaddingV` | 10 | Double | 4...20 | 1 |
| `bubbleSpacing` | 22 | Double | 8...40 | 1 |
| `lineSpacingScale` | 1.0 | Double | 0.5...2.0 | 0.05 |
| `paragraphSpacingScale` | 1.0 | Double | 0.5...2.0 | 0.05 |
| `hideTimestamp` | false | Bool | — | — |
| `hideRoleName` | false | Bool | — | — |
| `hideActionBar` | false | Bool | — | — |

**命名约定**：沿用现有 `fontScale` / `expandAllMessages` / `blurRadius` 的驼峰下划线混合风格。

---

## 改动面分析

### 改 Theme.swift 吗？
**不建议**。`Theme.bubbleCornerRadius` 等是 `static let`，改成 computed 读 UserDefaults 不会触发 SwiftUI 重绘（AppStorage 才有这个魔法）。

**方案**：保留 Theme.swift 常量作为"默认值"，在 BubbleView / CardFlowView 里直接读 `@AppStorage`，替换掉 `Theme.bubbleCornerRadius` 的引用。Theme 常量仍可供未跟外观设置联动的场景用（sidebar、sticker 等）。

### BubbleView 改动
- 加 9 个 `@AppStorage` 字段
- L1096-1098（roleName）、L1099-1103（time）套 `if !hideRoleName / !hideTimestamp`
- L1154 `.lineSpacing(4 * fontScale)` → `.lineSpacing(4 * fontScale * lineSpacingScale)`
- L1212-1213 `.padding(.horizontal, bubblePaddingH).padding(.vertical, bubblePaddingV)`
- L1215, 1219, 1224 `cornerRadius: bubbleCornerRadius` 替换 3 处
- L1282-1301 `if !hideActionBar { HoverButtons(...) }`

### CardFlowView.makeBubbleView / LazyVStack 改动
- L185 `LazyVStack(spacing: 22)` → `LazyVStack(spacing: bubbleSpacing)` — 需要在 CardFlowView 顶层加 `@AppStorage("bubbleSpacing")`

### MarkdownTheme 改动
- `memoryPalace(fontName:scale:)` 签名加两个参数：`lineSpacingScale`, `paragraphSpacingScale`
- L69 `.relativeLineSpacing(.em(0.42 * lineSpacingScale))`
- L70 `.markdownMargin(bottom: 12 * paragraphSpacingScale)`

### 调用处改动
- `CardFlowView.swift:1186` — 传新参数：
  ```swift
  .markdownTheme(.memoryPalace(
      fontName: selectedFont,
      scale: fontScale > 0 ? fontScale : 1.0,
      lineSpacingScale: lineSpacingScale,
      paragraphSpacingScale: paragraphSpacingScale
  ))
  ```

### AppearanceSettingsTab 改动
- 两份都要改（macOS + iOS）
- 新增 section "气泡外观（高级）"，DisclosureGroup 包起来
- 每个 slider 用现有 AppearanceSettingsTab 里的 Slider 样式（`.tint(Theme.branchIndicator)`）
- 每项带"重置默认"按钮（和现有 fontScale 一致）

---

## 开放问题（粟粟答后写 plan）

### Q1. 折叠方式
- A. `DisclosureGroup("气泡外观")` 在现有外观 tab 里展开收起（最简）
- B. 独立子页（iOS 多一级 navigation，macOS 另开 section 按钮）
- C. 放最底部，默认 ScrollView 滚不到看不见（软折叠）

### Q2. 气泡内边距是一个 slider 还是分水平/垂直两个？
- A. 两个（bubblePaddingH=14, bubblePaddingV=10 各自可调）— 粒度细
- B. 一个（padding = 所有边都一样）— 简单但丢了 14/10 的非对称美感

### Q3. 每个 slider 的 min/max 范围合理吗？
看表里提议，你觉得哪个要放宽 / 收窄。

### Q4. Per-profile 还是 Global？
- `@AppStorage` 是 UserDefaults 全局，所有楼层共用
- 若按楼层隔离，要搬到 `Profile` 模型里 + ProfileManager 读写
- 现有 `userName / assistantName / fontScale` 都是 Global，**建议也 Global**（一致）

### Q5. 行间距 / 分段间距 的区间用 scale（0.5...2.0）还是绝对值？
- Scale 直观（100% = 默认）
- 绝对值（比如 lineSpacing 0...12pt）精确但不直观
- 我建议 scale（和 fontScale 一致）

### Q6. "隐藏小按钮行" 在 macOS 生效吗？
- macOS 现有行为：hover 才显示 HoverButtons。`hideActionBar = true` 时 **完全不 render**（hover 也不出）
- 我建议统一行为：hideActionBar = true 则 iOS/macOS 都不 render

### Q7. 重置按钮做一个"全部重置"还是每个 slider 自己一个？
- 每个自己一个（和现有 fontScale 行为一致）— 推荐
- 加一个"全部重置"总按钮（省事）

### Q8. 字号 slider 的位置
- 现在字号 slider 已经在 section "聊天字号" 里，新 section 里要不要**复制一份**（放进"气泡外观"一组方便集中调）？
- 还是保持现状（字号在独立 section，其他在气泡外观 section）？
- 我建议保持现状（避免两份同源 slider 互相错位）

---

## 下一步

粟粟答完 Q1-Q8，开 `docs/plan-bubble-appearance-sliders.md` 写 task checklist。
