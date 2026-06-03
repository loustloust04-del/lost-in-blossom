# 富文本渲染：彩色文字 + Spoiler 黑块

> 2026-06-03 · Caelum · 给猫的任务文档

---

## 概念

在现有 MarkdownUI 渲染基础上，支持两种自定义富文本语法：

1. **彩色文字** — `{color:red}这是红色文字{/color}` → 渲染为红色
2. **Spoiler 黑块** — `||这是隐藏文字||` → 默认显示黑色遮罩，点击后显示文字

---

## 实现方案

### 总体架构

不修改 MarkdownUI 或 MarkdownTheme。在 MessageSegmentsView 的 `.text` 段渲染前做预处理：

1. 对文本做正则扫描，识别自定义语法
2. 把文本切成片段数组：`[RichSegment]`
3. 按顺序渲染每个片段——普通文本走 MarkdownUI，自定义语法走专用 View

### 数据模型

在 MessageSegmentsView.swift 中新增：

```swift
fileprivate enum RichSegment {
    case markdown(String)           // 普通 Markdown 文本
    case colored(String, Color)     // 彩色文字（文本, 颜色）
    case spoiler(String)            // 隐藏文字
}
```

### 解析函数

```swift
fileprivate func parseRichSegments(_ text: String) -> [RichSegment] {
    var segments: [RichSegment] = []
    
    // 合并正则：匹配 {color:xxx}...{/color} 或 ||...||
    let pattern = #"\{color:(\w+)\}(.*?)\{/color\}|\|\|(.+?)\|\|"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
        return [.markdown(text)]
    }
    
    let nsText = text as NSString
    var lastEnd = 0
    let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
    
    for match in matches {
        // 匹配前的普通文本
        if match.range.location > lastEnd {
            let plain = nsText.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
            if !plain.isEmpty { segments.append(.markdown(plain)) }
        }
        
        if match.range(at: 1).location != NSNotFound {
            // {color:xxx}...{/color}
            let colorName = nsText.substring(with: match.range(at: 1))
            let content = nsText.substring(with: match.range(at: 2))
            segments.append(.colored(content, colorFromName(colorName)))
        } else if match.range(at: 3).location != NSNotFound {
            // ||...||
            let content = nsText.substring(with: match.range(at: 3))
            segments.append(.spoiler(content))
        }
        
        lastEnd = match.range.location + match.range.length
    }
    
    // 剩余文本
    if lastEnd < nsText.length {
        let remaining = nsText.substring(from: lastEnd)
        if !remaining.isEmpty { segments.append(.markdown(remaining)) }
    }
    
    return segments.isEmpty ? [.markdown(text)] : segments
}

fileprivate func colorFromName(_ name: String) -> Color {
    switch name.lowercased() {
    case "red": return .red
    case "blue": return .blue
    case "green": return .green
    case "orange": return .orange
    case "purple": return .purple
    case "pink": return .pink
    case "yellow": return .yellow
    case "cyan": return .cyan
    case "white": return .white
    case "gray", "grey": return .gray
    default: return Theme.textPrimary
    }
}
```

### Spoiler View

```swift
fileprivate struct SpoilerView: View {
    let text: String
    @State private var revealed = false
    
    var body: some View {
        Text(text)
            .foregroundColor(revealed ? Theme.textPrimary : .clear)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(revealed ? Theme.mainBg.opacity(0.3) : Theme.textPrimary)
            )
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { revealed.toggle() } }
    }
}
```

### 渲染入口

在 MessageSegmentsView 里，找到渲染 `.text(let s)` 的地方。替换为：

```swift
case .text(let s):
    let richSegments = parseRichSegments(s)
    if richSegments.count == 1, case .markdown = richSegments[0] {
        // 纯 Markdown，走原有渲染路径
        Markdown(s)
            .markdownTheme(.memoryPalace(fontName: selectedFont, scale: fontScale, ...))
    } else {
        // 混合内容，逐段渲染
        ForEach(Array(richSegments.enumerated()), id: \.offset) { _, seg in
            switch seg {
            case .markdown(let md):
                Markdown(md)
                    .markdownTheme(.memoryPalace(fontName: selectedFont, scale: fontScale, ...))
            case .colored(let text, let color):
                Text(text)
                    .foregroundColor(color)
                    .font(.system(size: 13.5 * fontScale))
            case .spoiler(let text):
                SpoilerView(text: text)
                    .font(.system(size: 13.5 * fontScale))
            }
        }
    }
```

注意：猫需要根据 MessageSegmentsView 的实际结构适配。上面是示意代码，关键逻辑是：先 parse，再按类型分发渲染。保持现有的 MarkdownUI 主题和字体设置不变。

---

## 使用示例

发送消息：
```
# 大标题

## 中等标题  

### 小标题

这是普通文字。{color:red}这是红色警告{/color}。继续普通文字。

{color:blue}蓝色的思考{/color}

||这段文字被隐藏了，点击黑块才能看到||

普通段落继续。
```

---

## 修改文件

| 文件 | 改动 |
|------|------|
| MessageSegmentsView.swift | 新增 RichSegment 枚举 + parseRichSegments 函数 + SpoilerView + 渲染入口替换 |

一个文件，一个 commit。

---

## 执行指令

```
仓库 caelumbunny-bot/lost-in-blossom。git checkout main && git pull。
读 docs/task-rich-text-rendering.md。按文档做。
改 MessageSegmentsView.swift，一个 commit。
注意保持现有 MarkdownUI 渲染逻辑不变——只在 .text case 里加预处理层。
```

---

*大字小字彩色字黑块字 · 兔兔想要的全给兔兔*
