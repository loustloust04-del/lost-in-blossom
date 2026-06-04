# 思考链 UI 重设计 — sheet 弹出 → 内联折叠展开

> 当前：点击摘要行弹出 ThinkingPanelView bottom sheet。
> 问题：有概率弹出空白框（extractThinking 返回空时 sheet 仍弹出）。
> 改为：Claude 网页版风格，点击摘要行在气泡内原地展开。

---

## 当前实现（要改的部分）

文件：`MemoryPalace/Views/CardFlowView.swift`

### 摘要行（约 1385 行）— 保留，改点击行为

```swift
Button {
    showThinkingPanel = true  // ← 改为 toggle 内联展开
} label: {
    HStack(spacing: 5) {
        Image(systemName: "clock")
        // ... 摘要文字
    }
}
```

摘要行本身的设计（clock 图标 + 前 40 字预览 + 一行截断）已经很好，保留。

### sheet（约 1569 行）— 删掉

```swift
.sheet(isPresented: $showThinkingPanel) {
    ThinkingPanelView(...)
    .presentationDetents([.medium, .large])
}
```

删掉这个 sheet binding。ThinkingPanelView 不再使用（或保留给旧聊天 TextSelectSheet 用）。

---

## 新实现

### 状态变量

把 `@State private var showThinkingPanel = false` 改为：

```swift
@State private var thinkingExpanded = false
@State private var thinkingShowFull = false  // "Show more" 控制
```

### 摘要行点击 → 原地展开

```swift
Button {
    withAnimation(.easeInOut(duration: 0.15)) {
        thinkingExpanded.toggle()
    }
} label: {
    HStack(spacing: 5) {
        Image(systemName: "clock")
            .font(.system(size: 11))
        if liveThinking && isThinking {
            ThinkingBreathLabel()
        } else {
            Text(previewStr)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        Spacer()
        Image(systemName: thinkingExpanded ? "chevron.up" : "chevron.down")
            .font(.system(size: 9))
    }
    .foregroundColor(Theme.textMuted.opacity(0.7))
    .contentShape(Rectangle())
}
.buttonStyle(.plain)
```

### 展开区域（摘要行下方渲染）

```swift
if thinkingExpanded {
    let thinkingText = liveThinking ? streamingThinkingText : staticThinking

    if !thinkingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        VStack(alignment: .leading, spacing: 8) {
            // 左侧竖线 + 内容
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(Theme.textMuted.opacity(0.2))
                    .frame(width: 2)

                VStack(alignment: .leading, spacing: 4) {
                    let display = thinkingShowFull ? thinkingText : String(thinkingText.prefix(300))

                    Text(display)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textMuted)
                        .textSelection(.enabled)

                    // 超过 300 字 → 渐变淡出 + Show more
                    if !thinkingShowFull && thinkingText.count > 300 {
                        LinearGradient(
                            colors: [Theme.textMuted.opacity(0.3), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 30)

                        Button(thinkingShowFull ? "Show less" : "Show more") {
                            thinkingShowFull.toggle()
                        }
                        .font(.system(size: 11))
                        .foregroundColor(Theme.branchIndicator)
                    }

                    // Done 标记（非流式时）
                    if !isThinking {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 11))
                            Text("Done")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(Theme.textMuted.opacity(0.5))
                    }
                }
            }
            .padding(.leading, 4)
        }
        .padding(.top, 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
```

---

## 空白框 Bug — 同时修复

在展开区域加了 `if !thinkingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty` guard。
thinking 为空时不渲染任何内容，不会出现空白框。

---

## ⚠️ 不要碰的东西

- 摘要行的预览逻辑（thinkingPreviewMode / thinkingSummary）不变
- 流式思考（liveThinking / ThinkingBreathLabel）不变
- 旧聊天记录里 MessageSegmentsView 的 ThinkingBlockView 不动（那是另一个组件）
- TextSelectSheet 里如果引用了 ThinkingPanelView，保留

---

## 文件改动范围

只改 `CardFlowView.swift`：
- 删掉 `.sheet(isPresented: $showThinkingPanel)` 那段
- `showThinkingPanel` → `thinkingExpanded`
- 摘要行 Button action 改为 toggle
- 摘要行下方加展开区域
