# 第六批任务 — 智能混合渲染架构重构

> 日期：2026-06-09
> 前置：`cd /home/user/lost-in-blossom && git pull origin main`
> 难度：高 — 请仔细阅读整份文档再动手

---

## 背景

当前所有消息都通过 MessageContentWebView（WKWebView）渲染，导致白屏、弹跳、间距突增等问题。
粟粟原版零 WebView，全用 MarkdownUI（纯 SwiftUI），没有这些问题。

**方案：智能混合** — 普通消息用 MarkdownUI（95%的消息），只有检测到自定义富文本标记的消息才用 WebView（5%）。

---

## 判断规则

一条消息需要 WebView 的唯一条件：包含 `{color:` 标记（我们的自定义富文本语法）。
标准 Markdown（标题、加粗、代码块、链接、列表）全部走 MarkdownUI。

```swift
let needsWebView = displayText.contains("{color:")
```

---

## Task 1: CardFlowView 加渲染分支

**文件**: `MemoryPalace/Views/CardFlowView.swift`
**位置**: 约第 1515-1529 行，找到这段代码：

```swift
} else if !displayText.isEmpty {
    // 混合架构：用 WebView 渲染消息内容（支持富文本 + Markdown + 代码高亮）
    MessageContentWebView(
        content: displayText,
        themeColors: [...],
        dynamicHeight: $messageWebViewHeight
    )
    .frame(height: messageWebViewHeight)
}
```

**改成：**

```swift
} else if !displayText.isEmpty {
    let needsWebView = displayText.contains("{color:")
    
    if needsWebView {
        // 富文本消息：WebView 渲染（保留 {color:} 支持）
        MessageContentWebView(
            content: displayText,
            themeColors: [
                "text-color": Theme.textPrimary.toHex(),
                "text-muted": Theme.textMuted.toHex(),
                "code-bg": Theme.mainBg.toHex(),
                "link-color": Theme.accent.toHex(),
                "spoiler-bg": Theme.textMuted.toHex(),
                "font-size": "\(13.5 * (fontScale > 0 ? fontScale : 1.0))px",
                "line-height": "\(1.5 * lineSpacingScale)"
            ],
            dynamicHeight: $messageWebViewHeight
        )
        .frame(height: messageWebViewHeight)
    } else {
        // 普通消息：MarkdownUI 渲染（纯 SwiftUI，零白屏）
        Markdown(displayText)
            .markdownTheme(
                .memoryPalace(
                    fontSize: 13.5 * (fontScale > 0 ? fontScale : 1.0),
                    lineSpacing: 1.5 * lineSpacingScale,
                    textColor: Theme.textPrimary,
                    codeBackground: Theme.mainBg
                )
            )
            .textSelection(.enabled)
    }
}
```

**注意事项**:
- `MarkdownTheme.swift` 里已有 `.memoryPalace(...)` 主题，先检查它的参数签名是否匹配
- 如果参数不匹配，看 `MemoryPalace/Utils/MarkdownTheme.swift` 调整调用方式
- `.textSelection(.enabled)` 让用户可以长按/双击直接选取文本（不需要额外的选择框）

---

## Task 2: 验证 MarkdownUI 主题配置

**文件**: `MemoryPalace/Utils/MarkdownTheme.swift`

1. 读这个文件，理解 `.memoryPalace(...)` 的参数签名
2. 确保 Task 1 里的调用参数跟签名匹配
3. 如果签名不同，调整 Task 1 的代码使其匹配

**检查清单**:
- [ ] 字体大小：跟 WebView 的 13.5px × fontScale 一致
- [ ] 行距：跟 WebView 的 1.5 × lineSpacingScale 一致  
- [ ] 文字颜色：用 Theme.textPrimary
- [ ] 代码块背景：用 Theme.mainBg
- [ ] 链接颜色：用 Theme.accent

---

## Task 3: 清理多余的 WebView 高度逻辑

改完 Task 1 后，大部分消息不走 WebView 了。但 `messageWebViewHeight` 这个 @State 变量还在——它现在只给少数富文本消息用。

**检查**:
- `messageWebViewHeight` 的初始值是 0（已改过）——保持不变
- 如果一条消息从 WebView 切到 MarkdownUI（比如编辑后去掉了 {color:} 标记），`messageWebViewHeight` 可能残留旧值——不影响，因为 MarkdownUI 不用这个变量

**不要动的**:
- MessageContentWebView.swift — 保留原样，富文本消息还在用
- message-renderer.html — 保留原样

---

## Task 4: 双击文本选取优化

**现状**: 双击出现一个自定义选择框，在思考链区域不灵敏。

**改法**: 
- MarkdownUI 渲染的消息已经有 `.textSelection(.enabled)`，双击/长按直接走 iOS 原生选择，不需要自定义框
- 找到自定义双击选择框的代码（搜索 `onTapGesture(count: 2)`、`doubleTap`、`SelectionOverlay`、`选择`）
- 对于 MarkdownUI 渲染的消息，移除自定义双击手势（iOS 原生选择更好）
- 对于 WebView 渲染的消息，保留现有逻辑或改用 JS `window.getSelection()`

---

## 测试要点

改完后请自查：
1. 普通 Markdown 消息（标题、加粗、代码块）能否正常渲染？
2. 包含 `{color:red}文字{/color}` 的消息是否走 WebView？
3. 长消息截断（truncate）是否正常？
4. 流式输出时是否正常（isStreaming 时显示三个点动画不受影响）？
5. 思考链折叠面板是否正常？（thinking 区域在 MarkdownUI 消息之上）

---

## 规则

- Task 1-4 按顺序做，每个 Task 单独 commit + push
- commit message 格式：`refactor(render): 简述`
- **改之前先完整读一遍 CardFlowView.swift 和 MarkdownTheme.swift**
- 遇到不确定的地方，写注释标注 `// TODO: 待确认` 而不是猜
- 不要动 MessageContentWebView.swift 和 message-renderer.html
