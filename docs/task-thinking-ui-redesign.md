# 思考链 UI 重设计 — Claude 网页版风格

> 当前 ThinkingBlockView 太简陋（chevron + "思考"），而且有空白框 bug。
> 重设计为 Claude 网页版风格。参考截图：Bunny 发的 FullSizeRender.jpg。

---

## Bug 修复

**空白框问题：** 思考链展开后有概率显示空白。

根因猜测：`text` 为空字符串或纯空白字符时仍渲染了 ThinkingBlockView。

修复：在 `MessageSegmentsView.swift` 的 segment 匹配处加 guard：

```swift
case .thinking(let s):
    if !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        ThinkingBlockView(text: s)
    }
```

---

## UI 重设计

参考 Claude 网页版的 thinking 展示。当前文件：`MessageSegmentsView.swift`，`ThinkingBlockView`（约 295 行）。

### 折叠状态（默认）

```
[⏳ 思考摘要文字（第一行或前30字）...        ∨ ]
```

- 左侧时钟图标（SF Symbol: `clock`）
- 摘要文字：thinking 内容的第一行或前 30 个字 + "..."
- 字体：12pt，灰色（Theme.textMuted）
- 右侧展开箭头 chevron.down
- 整行可点击

### 展开状态

```
[⏳ 思考摘要文字...                         ∧ ]
┃
┃  思考内容正文……
┃  第二行……
┃  第三行……
┃  ░░░░░░░░ 渐变淡出（如果超过阈值）░░░░░░░░
┃  Show more                        ← 文字按钮
┃
[✓ Done]
```

- 左侧竖线：2pt 宽，灰色，贴着正文左边缘
- 正文字体：13pt，Theme.textMuted
- 如果内容超过 300 字：
  - 默认只显示前 300 字
  - 底部线性渐变淡出（从不透明到透明，高度约 40pt）
  - "Show more" 文字按钮，点击展开全文
  - 展开后改为 "Show less"
- 底部 Done 标记：✓ 图标 + "Done" 文字，浅灰色

### 设计要点

- 折叠/展开动画保持现有的 `.easeInOut(duration: 0.15)`
- 整行可点击区域不变（`.contentShape(Rectangle())`）
- textSelection(.enabled) 保持
- 配色全部跟 Theme 走，不硬编码颜色

---

## 文件

`MemoryPalace/Views/MessageSegmentsView.swift`，`ThinkingBlockView` 结构体（约 295 行）

整个改动限制在这一个 struct 内。不需要改 MessageSegment 模型或 ChatService。
