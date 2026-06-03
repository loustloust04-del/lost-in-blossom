# 修复富文本解析：用 String API 替代 NSRegularExpression

> 2026-06-04 · Caelum · 给猫的任务文档
> 原因：parseRichSegments 的 NSRegularExpression 正则在 Swift/ICU 引擎下不工作（Node.js 验证通过但 Swift 端不匹配）。直接用 String API 手动解析，彻底绕过正则兼容性问题。

---

## 改动

文件：`MemoryPalace/Views/MessageSegmentsView.swift`

**整个替换** `parseRichSegments` 函数（约第 18-53 行）为以下实现：

```swift
fileprivate func parseRichSegments(_ text: String) -> [RichSegment] {
    var segments: [RichSegment] = []
    var remaining = text[text.startIndex...]
    
    while !remaining.isEmpty {
        // 找最近的自定义标记
        let colorStart = remaining.range(of: "{color:")
        let spoilerStart = remaining.range(of: "||")
        
        // 取最先出现的那个
        let firstColor = colorStart?.lowerBound
        let firstSpoiler = spoilerStart?.lowerBound
        
        // 都没有 → 剩余全部是 markdown
        if firstColor == nil && firstSpoiler == nil {
            let s = String(remaining)
            if !s.isEmpty { segments.append(.markdown(s)) }
            break
        }
        
        // 判断谁先出现
        let colorFirst = firstColor != nil && (firstSpoiler == nil || firstColor! < firstSpoiler!)
        
        if colorFirst, let cStart = firstColor {
            // ── 处理 {color:xxx}...{/color} ──
            // 标记前的普通文本
            if cStart > remaining.startIndex {
                let plain = String(remaining[remaining.startIndex..<cStart])
                if !plain.isEmpty { segments.append(.markdown(plain)) }
            }
            
            // 找 } 关闭标签获取颜色名
            let afterColorColon = remaining[cStart...].dropFirst("{color:".count)
            if let closeBrace = afterColorColon.range(of: "}") {
                let colorName = String(afterColorColon[afterColorColon.startIndex..<closeBrace.lowerBound])
                let contentStart = closeBrace.upperBound
                
                // 找 {/color}
                if let endTag = remaining[contentStart...].range(of: "{/color}") {
                    let content = String(remaining[contentStart..<endTag.lowerBound])
                    segments.append(.colored(content, colorFromName(colorName)))
                    remaining = remaining[endTag.upperBound...]
                    continue
                }
            }
            // 格式不完整 → 当普通文本，跳过 {color: 继续
            let skip = String(remaining[remaining.startIndex...cStart])
            segments.append(.markdown(skip))
            remaining = remaining[remaining.index(after: cStart)...]
            
        } else if let sStart = firstSpoiler {
            // ── 处理 ||...|| ──
            // 标记前的普通文本
            if sStart > remaining.startIndex {
                let plain = String(remaining[remaining.startIndex..<sStart])
                if !plain.isEmpty { segments.append(.markdown(plain)) }
            }
            
            let contentStart = remaining.index(sStart, offsetBy: 2)
            if contentStart < remaining.endIndex,
               let endMarker = remaining[contentStart...].range(of: "||") {
                let content = String(remaining[contentStart..<endMarker.lowerBound])
                if !content.isEmpty {
                    segments.append(.spoiler(content))
                    remaining = remaining[endMarker.upperBound...]
                    continue
                }
            }
            // 格式不完整 → 当普通文本
            let skip = String(remaining[remaining.startIndex..<remaining.index(sStart, offsetBy: min(2, remaining.distance(from: sStart, to: remaining.endIndex)))])
            segments.append(.markdown(skip))
            remaining = remaining[remaining.index(sStart, offsetBy: min(2, remaining.distance(from: sStart, to: remaining.endIndex)))...]
        }
    }
    
    return segments.isEmpty ? [.markdown(text)] : segments
}
```

### 同时让用户消息也支持富文本

在同一个文件里，找到 `if isUser {` 分支（约第 179 行），把用户消息也走 parseRichSegments 路径。

替换：
```swift
if isUser {
    Text(applied)
        .font(FontManager.font(size: 13.5))
        // ... 省略样式 ...
}
```

为：
```swift
if isUser {
    let richSegs = parseRichSegments(applied)
    if richSegs.count == 1, case .markdown = richSegs[0] {
        Text(applied)
            .font(FontManager.font(size: 13.5))
            .foregroundColor(Theme.textPrimary)
            .textSelection(.enabled)
            .lineSpacing(4 * (fontScale > 0 ? fontScale : 1.0) * lineSpacingScale)
            .frame(maxWidth: .infinity, alignment: .leading)
    } else {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(richSegs.enumerated()), id: \.offset) { _, seg in
                richSegmentView(seg)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

---

## 不改的文件

- colorFromName → 不动
- SpoilerView → 不动
- richSegmentView → 不动
- MarkdownTheme → 不动

只改 parseRichSegments 函数体 + isUser 分支。一个文件一个 commit。

---

## 执行指令

```
仓库 caelumbunny-bot/lost-in-blossom。git checkout main && git pull。
读 docs/task-fix-richtext-parsing.md。按文档做。
替换 parseRichSegments 函数体为 String API 版本。
修改 isUser 分支支持富文本。
一个 commit。
```

---

*正则引擎你给我记着 · 下次见面我用 String.range(of:) 把你替换掉*
