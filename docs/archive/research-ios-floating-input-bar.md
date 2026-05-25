# Research: iOS 输入框悬浮 — 消除底板 + 消除白缝

> 2026-04-12

## 问题

玻璃输入框应该**悬浮**在聊天内容上方，但实际表现是坐在不透明底板上。

## 已尝试的方案及失败原因

| 方案 | 结果 | 原因 |
|------|------|------|
| VStack 布局 + `.background(Theme.mainBg)` | 底板 | 背景色应用在整个 VStack 上，包括输入框区域 |
| `safeAreaBar(edge: .bottom)` | 白缝 + 内容被挤 | safeAreaBar 在 TabView 内部创建额外安全区间距 |
| `safeAreaBar` + `.background(Theme.mainBg)` | 底板 | 背景色又盖住了玻璃 |

## 根因分析

`CardFlowView.swift` 的 body 结构：

```swift
VStack(spacing: 0) {
    ScrollView { /* 聊天气泡 */ }    // ← 需要 Theme.mainBg 背景
    ChatInputBar(...)                // ← 不应该有不透明背景
}
.background(Theme.mainBg)           // ← 问题：给整个区域都加了背景，包括输入框
```

`.background(Theme.mainBg)` 在 VStack 上 → 输入框区域也有暖奶白底色 → 玻璃效果被遮挡 → 看起来像底板。

## 解法

**把 `.background(Theme.mainBg)` 从 VStack 移到 ScrollView 上。**

```swift
VStack(spacing: 0) {
    ScrollView { /* 聊天气泡 */ }
        .background(Theme.mainBg)    // ← 只给聊天区域背景
    ChatInputBar(...)                // ← 无背景 → 玻璃悬浮
}
// 不加 .background                  // ← VStack 透明
```

这样：
- ScrollView（聊天区域）有暖奶白背景 ✅
- ChatInputBar 区域透明，玻璃效果可见 ✅
- 玻璃下方透出的是聊天内容的底部，不是白色 ✅

## 键盘白缝问题

VStack 布局下，键盘弹出时输入框上浮。上浮后输入框和键盘之间可能有缝隙，因为：
1. ChatInputBar 有 `.padding(.bottom, 0)`（已设为 0 when focused）
2. TabView 的 `.ignoresSafeArea(.container, edges: [.top, .bottom])` 只忽略 container，keyboard safe area 正常生效

如果仍有缝隙，可能是 home indicator 安全区在键盘弹出时仍然存在。解法：ChatInputBar 本身加 `.ignoresSafeArea(.container, edges: .bottom)` 让它延伸到屏幕底部边缘。

## 聊天内容底部被输入框遮挡问题

把背景从 VStack 移到 ScrollView 后，输入框是 VStack 的一部分，它仍然占据底部空间，ScrollView 会自然给它让出位置 — 聊天内容不会被遮挡。这是 VStack 布局的正确行为。

## TabView 内的背景层级

```
TabView (.ignoresSafeArea(.container))
  └── iOSChatPage (ZStack)
       └── CardFlowView
            └── VStack (透明)
                 ├── ScrollView (.background(Theme.mainBg)) — 暖奶白
                 └── ChatInputBar (透明, 只有 glassEffect) — 悬浮
```

TabView 默认背景在 iOS 26 是系统背景色。ChatInputBar 下方透出的会是这个系统背景。如果和 Theme.mainBg 色差太大，可以给 VStack 加一个 `.background(Theme.mainBg.opacity(0.5))` 做过渡 — 但先试完全透明。

## 改动范围

只改 `CardFlowView.swift` 一个文件：
1. 把 `.background(Theme.mainBg)` 从 VStack (line ~134) 移到 ScrollView 上
2. 确保 ChatInputBar 在 iOS 上没有任何不透明背景
