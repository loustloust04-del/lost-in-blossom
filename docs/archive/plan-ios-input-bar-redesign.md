# Plan: iOS 输入框重设计 — Liquid Glass 浮板 + 键盘交互修复

> 2026-04-12
> 依赖：`docs/research-ios-input-bar-redesign.md`

## 目标

打字时只有一个干净的玻璃浮板紧贴键盘，没有任何多余元素。键盘收起后模型选择器以玻璃悬浮按钮出现。

## Checklist

### 1. 输入框改为 Liquid Glass 浮板

文件：`CardFlowView.swift` — `ChatInputBar`

- [x] **1a** 删除手动样式：移除 `.background(RoundedRectangle...)` 和 `.overlay(RoundedRectangle...stroke...)`
- [x] **1b** 加 `#if os(iOS)` 的 `.glassEffect(in: .rect(cornerRadius: 20))`，macOS 保持现有样式
- [x] **1c** 调整 padding：水平 padding 从 28pt 缩到 16pt（iOS），给输入区域更多空间
- [x] **1d** 输入框内部 padding 微调，确保文字和发送按钮的视觉间距舒适
- [x] **1e** build + 真机截图确认玻璃质感效果

### 2. 输入框改用 `safeAreaBar` 挂载

文件：`CardFlowView.swift` — `body`

- [x] **2a** 把 ChatInputBar 从 VStack 子 view 改为 `.safeAreaBar(edge: .bottom)` 挂在 ScrollViewReader 上（仅 iOS）
- [x] **2b** macOS 保持现有 VStack 布局不变（`#if os(macOS)` / `#else`）
- [x] **2c** 移除 ContentView.swift 中 `.ignoresSafeArea(.container, edges: .bottom)` 的 `.bottom`，只保留 `.top`
  - 或者：如果只改 `.top` 导致 home indicator 区域出问题，保持 `.container` 但确认 keyboard region 不被忽略
- [x] **2d** build + 真机测试键盘弹出：
  - 输入框是否紧贴键盘上方？
  - 键盘弹出/收起动画是否灵敏流畅？
  - ScrollView 内容是否自动避让输入框？

### 3. 页面指示器打字时消失

文件：`ContentView.swift`

- [x] **3a** 先试方案 A：加 `.indexViewStyle(.page(backgroundDisplayMode: .never))` 到 TabView
- [x] **3b** 真机测试 — 如果 dots 仍然存在，转方案 B
- [x] **3c** 方案 B：监听键盘状态，在键盘弹出时用 `.tabViewStyle(.page(indexDisplayMode: .never))` 动态切换，或用 overlay 覆盖 dots 区域
  - 需要一个 `@State private var isKeyboardVisible: Bool`
  - 用 `NotificationCenter` 监听 `UIResponder.keyboardWillShowNotification` / `keyboardWillHideNotification`
- [x] **3d** 如果方案 A/B 都不行，方案 C：用 ScrollView + `.scrollTargetBehavior(.paging)` 替代 TabView（改动最大，最后手段）
- [x] **3e** 真机确认：打字时 dots 完全不可见，收起键盘后（如果本来有 dots）恢复正常

### 4. 模型选择器改为玻璃悬浮按钮

文件：`CardFlowView.swift` — `ChatInputBar`

- [x] **4a** 保留现有大小和青色配色（`Theme.accent.opacity(0.3)` capsule 背景）
- [x] **4b** 加 `#if os(iOS)` 的 `.glassEffect(.regular.tint(Theme.accent))` 替代手动 `Capsule().fill(...)`
- [x] **4c** macOS 保持现有样式
- [x] **4d** 键盘弹出时隐藏（已实现 `if !isFocused`）
- [x] **4e** 键盘收起时以玻璃悬浮按钮出现，位置不变（输入框下方右对齐）
- [x] **4f** build + 真机确认视觉效果

### 5. 验证

- [x] **5a** macOS build 通过，输入框行为与改动前一致
- [x] **5b** iOS build 通过
- [x] **5c** 真机测试完整流程：
  1. 打开对话 → 输入框是玻璃浮板，下方有玻璃模型选择器
  2. 点击输入框 → 键盘弹出，输入框灵敏上浮紧贴键盘，模型选择器消失，page dots 消失
  3. 打字 → 看得到自己打的字，输入框不被遮挡
  4. 滑动聊天内容 → 键盘立即收起（`.scrollDismissesKeyboard(.immediately)` 已有）
  5. 键盘收起 → 输入框回到底部，模型选择器重新出现
- [x] **5d** git commit + push

## 文件改动范围

| 文件 | 改动 |
|------|------|
| `CardFlowView.swift` | ChatInputBar 样式 → glassEffect；body 布局 → safeAreaBar；模型选择器 → glass 悬浮 |
| `ContentView.swift` | `.ignoresSafeArea` 调整；`.indexViewStyle` 加上 |

只动 2 个文件，不涉及 model/service 层。
