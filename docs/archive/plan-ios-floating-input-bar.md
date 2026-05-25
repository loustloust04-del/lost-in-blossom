# Plan: iOS 输入框悬浮修复

> 2026-04-12
> 依赖：`docs/research-ios-floating-input-bar.md`

## Checklist

### 1. 背景色从 VStack 移到 ScrollView

文件：`CardFlowView.swift`

- [ ] **1a** 找到 VStack 上的 `.background(Theme.mainBg)`（约 line 134），仅 iOS 上移除
- [ ] **1b** 把 `.background(Theme.mainBg)` 加到 ScrollView 上（约 line 97，在 `.frame(maxWidth: .infinity)` 之后）
- [ ] **1c** macOS 保持现有行为不变（VStack 的背景保留给 macOS）

### 2. 确保 ChatInputBar 在 iOS 上无不透明背景

文件：`CardFlowView.swift`

- [ ] **2a** 确认 ChatInputBar 的 `#if os(iOS)` 路径中没有 `.background(Theme.mainBg)` 或其他不透明背景
- [ ] **2b** 唯一的视觉背景应该是 `.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))`

### 3. 键盘弹出时无白缝

- [ ] **3a** 确认 ChatInputBar 的 bottom padding 在 `isFocused` 时为 0
- [ ] **3b** 如果仍有缝隙，给 ChatInputBar 加 `.ignoresSafeArea(.container, edges: .bottom)` 让它延伸到屏幕底缘
- [ ] **3c** 不弹键盘时，输入框悬浮在 home indicator 上方，无白缝

### 4. 验证

- [ ] **4a** iOS build 通过
- [ ] **4b** macOS build 通过
- [ ] **4c** 真机验证：
  1. 不打字时：玻璃输入框悬浮，下方透出聊天内容，无底板
  2. 打字时：输入框紧贴键盘，无白缝，page dots 消失
  3. 滑动收键盘正常
  4. macOS 行为不变

## 文件改动

只改 `CardFlowView.swift`，约 2-3 行改动。
