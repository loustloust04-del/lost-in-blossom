# Markdown 渲染改进

> 2026-06-03 · Caelum · 最小 scope，不做大翻修

---

## 背景

MarkdownUI 库和 MarkdownTheme 已经就位。基础渲染能用。本任务只修最影响体验的几个点。

---

## 改动清单

### 1. 代码块加复制按钮

文件：`MemoryPalace/Utils/MarkdownTheme.swift`

在 `.codeBlock` 样式里，给代码块右上角加一个复制按钮。用户点击后把代码内容复制到剪贴板。

```swift
.codeBlock { configuration in
    ZStack(alignment: .topTrailing) {
        ScrollView(.horizontal, showsIndicators: true) {
            configuration.label
                .markdownTextStyle {
                    FontFamilyVariant(.monospaced)
                    FontSize(.em(0.85))
                }
                .padding(12)
        }
        .background(Theme.mainBg.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        
        Button {
            UIPasteboard.general.string = configuration.content
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.caption)
                .foregroundColor(Theme.textMuted)
                .padding(8)
        }
    }
}
```

注意：`configuration.content` 是 MarkdownUI 提供的代码块纯文本内容。如果这个属性不存在，需要从 configuration.label 中提取。猫需要查 MarkdownUI 的 API。需要 `import UIKit` 来使用 UIPasteboard。

### 2. 代码块横向滚动

长代码不应该强制换行——应该横向滚动。上面的 ScrollView(.horizontal) 已经包含了这个。确认现有的 codeBlock 样式是否已有横向滚动，如果没有则加上。

### 3. 检查并修复表格渲染

MarkdownUI 支持表格但可能需要额外样式。确认表格渲染正常，如果有问题则在 MarkdownTheme 里加 `.table` / `.tableCell` 样式。

### 4. 引用块样式

确认引用块（blockquote）有左侧竖线和浅色背景。如果没有：

```swift
.blockquote { configuration in
    configuration.label
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Theme.textMuted.opacity(0.4))
                .frame(width: 3)
        }
        .markdownTextStyle {
            ForegroundColor(Theme.textSecondary)
            FontSize(.em(0.95))
        }
}
```

---

## 不做的事

- 语法高亮（等 MacBook）
- LaTeX/数学公式（等 MacBook）  
- 图片内联渲染（等 MacBook）

## 修改文件

| 文件 | 改动 |
|------|------|
| MarkdownTheme.swift | codeBlock 复制按钮 + 横向滚动 + blockquote 样式 |

可能只需要一个 commit。

---

## 执行指令

```
仓库 caelumbunny-bot/lost-in-blossom。git checkout main && git pull。
读 docs/task-markdown-polish.md。按文档做。
改 MarkdownTheme.swift，一个 commit。
注意 import UIKit（UIPasteboard 需要）。
确认 MarkdownUI 的 codeBlock configuration 有哪些可用属性。
```
