# Research: iOS 贴纸面板材质 + 底部安全区

## 问题

1. 面板底部不覆盖 home indicator 区域（"镂空"）
2. 工具栏和面板的材质要用 Liquid Glass（不是 ultraThinMaterial）

## 核心发现：safe area 延伸的正确方法

`.ignoresSafeArea()` 在 `.safeAreaInset` 内部的行为：

| 用法 | 效果 |
|------|------|
| 外层 VStack 加 `.ignoresSafeArea()` | **不生效**，safeAreaInset 无视它 |
| `.background(Color.red)` (ShapeStyle 重载) | **自动延伸**，默认 `ignoresSafeAreaEdges: .all` |
| `.background { Color.red }` (View 闭包) | **不延伸**，尊重安全区 |
| `.background { Color.red.ignoresSafeArea() }` | **延伸！** background 闭包里的子 view 可以突破 |
| overlay + ignoresSafeArea | **不生效**，overlay 尺寸跟随父 view |

**正确模式：**
```swift
.safeAreaInset(edge: .bottom, spacing: 0) {
    VStack { /* 内容 */ }
        .background {
            Color.accentColor.ignoresSafeArea(.container, edges: .bottom)
        }
}
```

内容留在安全区内，背景延伸到屏幕底边。

## glassEffect 的处理

`.glassEffect()` 不是 ShapeStyle，不能用 `.background(.glassEffect)` 的 ShapeStyle 重载。
需要在 `.background {}` 闭包里放一个透明 view，加 `.glassEffect()` 再加 `.ignoresSafeArea()`：

```swift
.background {
    Color.clear
        .glassEffect(.regular.tint(Color.black.opacity(0.01)).interactive(),
                     in: .rect(cornerRadii: .init(topLeading: 16, topTrailing: 16)))
        .ignoresSafeArea(.container, edges: .bottom)
}
```

## 输入框用什么

```swift
// CardFlowView.swift line 486
.glassEffect(.regular.tint(Color.black.opacity(0.01)).interactive(), in: .rect(cornerRadius: 20))
```

## 原生 sheet 方案：不可行

`.sheet()` 的 drag session 被锁在 sheet 内部，不能跨 sheet 拖拽。保留自定义面板。

## 改动方案

1. 回到 safeAreaInset（不用 overlay），面板放回 safeAreaInset
2. 面板卡片去掉直接的 `.glassEffect()`
3. 改用 `.background { Color.clear.glassEffect(...).ignoresSafeArea(.container, edges: .bottom) }`
4. 工具栏保持独立 glassEffect（在安全区内，不需要延伸）
