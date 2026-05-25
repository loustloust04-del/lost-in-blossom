# Research: iOS 输入框重设计 — Liquid Glass 浮板 + 键盘交互修复

> 2026-04-12

## 问题

1. **输入框样式丑陋** — 当前是自定义 `RoundedRectangle` + `stroke`，与 iOS 26 Liquid Glass 风格格格不入
2. **页面指示器小圆点仍然显示** — `indexDisplayMode: .never` 没有完全压制 TabView 的 page dots
3. **键盘弹出不灵敏** — 可能与 `.ignoresSafeArea` 和输入框布局方式有关

## 现状代码分析

### 输入框 (`CardFlowView.swift` — `ChatInputBar`)

```swift
// 当前结构
VStack(spacing: 6) {
    HStack(alignment: .bottom, spacing: 0) {
        TextField(placeholder, text: $inputText, axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(1...6)
            .focused($isFocused)
        Button(action: send) { /* 发送按钮 */ }
    }
    .background(RoundedRectangle(cornerRadius: 18).fill(Theme.sidebarBg))
    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.accent, lineWidth: 1))
    
    // 模型选择器（键盘弹出时已隐藏）
    if !isFocused { modelSelectorButton }
}
.padding(.horizontal, 28)
.padding(.bottom, isFocused ? 4 : 12)
.background(Theme.mainBg)
```

**问题**：
- 手动画的圆角矩形 + 描边，不是系统组件
- `.background(Theme.mainBg)` 是纯色不透明背景
- 水平 padding 28pt 太大，压缩了输入区域
- 整个输入栏是 VStack 内的普通子 view，不是 `safeAreaBar`/`safeAreaInset`

### TabView 布局 (`ContentView.swift`)

```swift
TabView(selection: $iOSPage) {
    iOSListPage.tag(0)
    iOSChatPage.tag(1)
    iOSDashboardPage.tag(2)
}
.tabViewStyle(.page(indexDisplayMode: .never))
.ignoresSafeArea(.container, edges: [.top, .bottom])
```

**页面指示器问题**：
- `.page(indexDisplayMode: .never)` 应该隐藏 dots，但 iOS 26 行为可能变了
- Liquid Glass 设计系统下，TabView 的页面切换 UI 可能有新的默认行为
- 可能需要额外的 `.indexViewStyle(.page(backgroundDisplayMode: .never))` 或覆盖

### 键盘弹出不灵敏

**可能原因**：
1. `.ignoresSafeArea(.container, edges: .bottom)` 仍然影响了键盘动画的响应
2. ChatInputBar 不是通过 `safeAreaInset` 或 `safeAreaBar` 挂载的 — 它是 VStack 里的普通子 view
3. SwiftUI 的键盘避让动画需要 view 在安全区内才能正确响应

## iOS 26 新 API 调研

### 1. Liquid Glass (`glassEffect`)

**SwiftUI API**：
```swift
// 基础用法 — 默认 Capsule 形状
Text("Hello").padding().glassEffect()

// 自定义形状
Text("Hello").padding().glassEffect(in: .rect(cornerRadius: 16.0))

// 交互式 + 着色
Text("Hello").padding().glassEffect(.regular.tint(.orange).interactive())
```

**Glass 变体**：
- `.regular` — 标准玻璃效果
- `.clear` — 清透玻璃（UIKit: `UIGlassEffect.Style.clear`）
- `.interactive()` — 响应触摸/指针交互

**GlassEffectContainer** — 将多个玻璃形状合并为一个，可以互相变形动画：
```swift
GlassEffectContainer {
    button1.glassEffect()
    button2.glassEffect()
}
```

**适用于输入框**：用 `.glassEffect(in: .rect(cornerRadius: 20))` 替代手动 `RoundedRectangle` + `fill` + `stroke`。输入框背景变成半透明毛玻璃，跟 iOS 26 系统风格一致。

### 2. `safeAreaBar` (iOS 26 新 API)

```swift
func safeAreaBar(
    edge: VerticalEdge,
    alignment: HorizontalAlignment = .center,
    spacing: CGFloat? = nil,
    @ViewBuilder content: () -> some View
) -> some View
```

**作用**：把 content 作为自定义 bar 显示在 view 的上方或下方，自动调整 safe area + scroll edge effects。

**比 `safeAreaInset` 更好**：`safeAreaBar` 会扩展 scroll view 的 edge effect，让滚动到底部时内容不被 bar 遮挡。

**适用于输入框**：用 `.safeAreaBar(edge: .bottom)` 把 ChatInputBar 挂在聊天 ScrollView 底部。这样：
- 输入框自动跟随键盘上浮
- ScrollView 自动给输入框让出空间
- 不需要手动处理 `.ignoresSafeArea` 的键盘冲突

### 3. `GlassButtonStyle` — 玻璃按钮

```swift
Button("Send") { ... }.buttonStyle(.glass)
Button("Send") { ... }.buttonStyle(.glassProminent)
```

发送按钮可以用 `.glass` 或 `.glassProminent` 样式。

## 设计方案

### 目标效果（参考粟粟提供的截图）

- 输入框是一个干净的浮板，紧贴键盘上方
- 玻璃质感/半透明背景
- 只有文本输入区域 + 发送按钮，没有多余元素
- 键盘弹出时没有 toolbar、没有 page dots、没有模型选择器

### 架构改动

**核心改动：把 ChatInputBar 从 VStack 子 view 改为 `safeAreaBar`**

```
// 之前
VStack {
    ScrollView { ... }      // 聊天内容
    ChatInputBar(...)        // 输入框作为 VStack 子 view
}

// 之后
ScrollView { ... }          // 聊天内容
    .safeAreaBar(edge: .bottom) {
        ChatInputBar(...)    // 输入框作为 safe area bar
    }
```

这样做的好处：
1. 键盘弹出时输入框自动上浮（由 safe area 系统管理）
2. ScrollView 的 scroll edge effect 自动适配
3. 不需要手动控制 `.ignoresSafeArea` 的 keyboard region

**输入框样式改动**：

```swift
// 之前
HStack { TextField... Button... }
    .background(RoundedRectangle(cornerRadius: 18).fill(Theme.sidebarBg))
    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.accent, lineWidth: 1))

// 之后
HStack { TextField... Button... }
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
    .glassEffect(in: .capsule)  // 或 .rect(cornerRadius: 20)
```

### 页面指示器修复方案

三种思路，按优先级：

1. **方案 A：覆盖 `indexViewStyle`**
   ```swift
   TabView { ... }
       .tabViewStyle(.page(indexDisplayMode: .never))
       .indexViewStyle(.page(backgroundDisplayMode: .never))  // 双重保险
   ```

2. **方案 B：用 `scrollTargetLayout` 替代 TabView paging**
   iOS 26 的 ScrollView 支持 paging behavior，可能比 TabView 更可控：
   ```swift
   ScrollView(.horizontal) {
       LazyHStack { pages }
           .scrollTargetLayout()
   }
   .scrollTargetBehavior(.paging)
   ```
   这样完全没有 page indicator 的问题，但改动更大。

3. **方案 C：给 ChatInputBar 的背景延伸到底部覆盖 dots**
   最简单但最 hack：让输入框的不透明背景向下延伸，盖住 dots。

**推荐**：先试方案 A，不行再试方案 B。方案 C 是兜底。

### 键盘灵敏度

改用 `safeAreaBar` 后应该自动解决，因为键盘避让由 safe area 系统原生处理，不再依赖手动的 `.ignoresSafeArea(.container)` 配置。

如果仍然不灵敏，可能需要检查：
- TabView 的 `.ignoresSafeArea(.container, edges: .bottom)` 是否阻断了 keyboard safe area 传递
- 是否需要把 `.ignoresSafeArea` 只应用到 `.top`

## 风险点

1. **`safeAreaBar` 是 iOS 26 新 API** — macOS 14 不一定有，需要 `#if os(iOS)` + `@available` 保护
2. **`glassEffect` 需要 iOS 26+** — 我们最低支持 iOS 26（project.yml 里 deploymentTarget 确认）
3. **TabView paging 行为变化** — iOS 26 的 Liquid Glass 可能改变了 TabView 的默认 UI，需要实测
4. **模型选择器入口** — 键盘收起后需要有地方能切模型，当前方案是隐藏/显示，需确认体验

## 已确认

- iOS deploymentTarget = 26.0，可以直接用新 API，不需要 `@available` fallback
- macOS deploymentTarget = 14.0，`glassEffect`/`safeAreaBar` 不可用，macOS 保持现有布局
- 模型选择器：保留当前大小和青色配色，改成 Liquid Glass 悬浮按钮，键盘弹出时隐藏
- 页面指示器：打字时**必须**消失，硬性要求，不是"尝试隐藏"
