# Research: 底部渐进模糊 — 为什么到不了底

> 2026-04-13

## 问题

顶部渐进模糊正常（overlay 在 ScrollView 上 + `.ignoresSafeArea(.all, edges: .top)`）。
底部模糊到不了屏幕最底部（home indicator 区域），试了多种 `.ignoresSafeArea` 都不行。

## 根因

底部模糊放在 `safeAreaInset(edge: .bottom)` 的 content 里。safeAreaInset 的 content 受两层约束：

1. **safeAreaInset 本身**：content 被锚定在 ScrollView 底部，高度由 content 自身决定
2. **容器安全区**：home indicator 区域（约 34pt）在容器安全区外，safeAreaInset content 默认不延伸到那里

在 safeAreaInset content 内部加 `.ignoresSafeArea(.container, edges: .bottom)` 无效 —— safeAreaInset 已经定义了 content 的布局边界，内部的 ignoresSafeArea 无法突破这个边界。

## 已尝试的方案

| 方案 | 结果 |
|------|------|
| blur overlay 在 ScrollView 上 `.overlay(alignment: .bottom)` | 被 safeAreaInset 推上去，离底部很远 |
| blur 在外层 VStack 上 `.overlay(alignment: .bottom)` | 还是到不了底 + 遮住输入框 |
| blur 在 safeAreaInset 的 ZStack 里 + `.ignoresSafeArea(.container, edges: .bottom)` 在 blur 上 | 镂空依旧 |
| blur 在 safeAreaInset 的 ZStack 里 + `.ignoresSafeArea` 在 ZStack 上 | 没试过 |

## 正确方案

**用 `.background` + `.offset` 延伸到底部。**

不把 blur 放在 ZStack 子元素里，而是作为 ChatInputBar 的 `.background`，用 `offset(y:)` 向下推到覆盖 home indicator 区域：

```swift
.safeAreaInset(edge: .bottom, spacing: 0) {
    if let pm = providerManager {
        ChatInputBar(...)
            .background(alignment: .bottom) {
                ProgressiveBlurOverlay(edge: .bottom, height: 200)
                    .offset(y: 40)  // 向下推 40pt 覆盖 home indicator
            }
    }
}
```

原理：
- `.background` 不影响 view 的 size（不会让 safeAreaInset 预留更多空间）
- `.background` 可以通过 offset 超出 view 的 bounds
- offset 40pt 足以覆盖 home indicator 区域（~34pt）
- 模糊高度 200pt 从 ChatInputBar 底部向上延伸，覆盖 ChatInputBar 区域 + 上方的聊天内容
- ChatInputBar 本身（含 glassEffect）在 background 上层，不会被模糊遮挡

## 键盘弹出时的行为

- safeAreaInset content（ChatInputBar + 模糊背景）跟着键盘上移
- 模糊跟着走，"遮到哪算哪"（粟粟确认不需要特殊处理）
- 顶部模糊不受影响

## 改动

只改 `CardFlowView.swift` 一个文件：
1. 恢复 stash 中的 ProgressiveBlurOverlay 组件
2. 顶部模糊：保持现有的 `.overlay(alignment: .top)` on ScrollView
3. 底部模糊：ChatInputBar 的 `.background(alignment: .bottom)` + `offset(y: 40)`
