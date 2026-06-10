# 文本选取：长按菜单"选取文本" → 气泡原地可选取

> 日期：2026-06-10
> 优先级：P1（体验优化，不影响核心功能）
> 前置：`cd /home/user/lost-in-blossom && git pull origin main`

---

## 问题描述

MarkdownUI 的 `.textSelection(.enabled)` 不支持双击选词——它渲染的不是原生 Text，系统手势识别器挂不上去。长按被 `.contextMenu`（气泡菜单）拦截，所以用户无法在气泡里选取部分文本，只能通过菜单里的"复制文本"复制整条消息。

## 方案

在长按菜单里加"选取文本"按钮。点击后在气泡上覆盖一个 `UITextView`（只读+可选取），用户用原生手势选取文本，点外面退出。不弹框，不离开当前界面。

---

## Task 1: 新建 SelectableTextOverlay 组件

**新建文件**: `MemoryPalace/Views/SelectableTextOverlay.swift`

```swift
import SwiftUI
import UIKit

/// 覆盖在气泡上的可选取文本层。
/// 用 UITextView 实现原生文本选择（双击选词、长按自由选取、拖动手柄）。
struct SelectableTextOverlay: UIViewRepresentable {
    let text: String
    let font: UIFont
    let textColor: UIColor
    @Binding var isActive: Bool

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = true
        tv.showsVerticalScrollIndicator = false
        tv.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.95)
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        tv.font = font
        tv.textColor = textColor
        tv.layer.cornerRadius = 16
        tv.layer.borderWidth = 1.5
        tv.layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.3).cgColor
        // 出现时自动全选第一个词（给用户视觉反馈"现在可以选了"）
        tv.text = text
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        tv.text = text
    }
}
```

**commit**: `feat(ui): add SelectableTextOverlay component`

---

## Task 2: BubbleView 加选取状态和覆盖层

**文件**: `MemoryPalace/Views/CardFlowView.swift`

**步骤**:

1. 在 BubbleView 的 @State 区域（约第 1298 行附近）加：
```swift
@State private var isSelectingText = false
```

2. 在 `.contextMenu` 里的"复制文本"按钮**后面**加"选取文本"按钮（约第 1635 行后）：
```swift
Button(action: {
    isSelectingText = true
}) {
    Label("选取文本", systemImage: "text.cursor")
}
```

3. 在气泡内容区域（MarkdownUI / WebView 渲染的那个 block）外面套一个 ZStack，`isSelectingText` 为 true 时显示覆盖层（约第 1509-1540 行区域）：

在整个消息内容渲染完成后、`}` 闭合前，加一个 overlay：
```swift
.overlay {
    if isSelectingText {
        SelectableTextOverlay(
            text: ContentCleaner.clean(node.content, cacheKey: node.id),
            font: .systemFont(ofSize: 13.5 * CGFloat(fontScale > 0 ? fontScale : 1.0)),
            textColor: UIColor(Theme.textPrimary),
            isActive: $isSelectingText
        )
        .transition(.opacity)
    }
}
```

4. 点击覆盖层外面退出选取模式——在 BubbleView 最外层加：
```swift
.onChange(of: isSelectingText) { newValue in
    // 3 秒后如果还没手动关闭，也不自动关（让用户自己选完）
}
```

退出方式：在覆盖层右上角加一个小 ✕ 按钮，或者监听 `.onTapGesture` 在覆盖层外面关闭。

**更简单的退出方式**：用 `.sheet` 或 `.fullScreenCover` 的思路——直接用 `.overlay` + 半透明背景 + 点击背景关闭：

```swift
// 在 BubbleView 最外层 body 的 return 之前
if isSelectingText {
    Color.black.opacity(0.01)  // 透明点击捕获层
        .onTapGesture { isSelectingText = false }
        .ignoresSafeArea()
}
```

（这个放在 ScrollView 外面会比较复杂，更实际的做法是在覆盖层本身加一个"完成"按钮）

**推荐做法**：覆盖层顶部加一个 HStack，左边"选取文本"标题，右边"完成"按钮：

```swift
.overlay {
    if isSelectingText {
        VStack(spacing: 0) {
            HStack {
                Text("选取文本")
                    .font(.caption)
                    .foregroundColor(Theme.textMuted)
                Spacer()
                Button("完成") { isSelectingText = false }
                    .font(.caption.bold())
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            SelectableTextOverlay(
                text: ContentCleaner.clean(node.content, cacheKey: node.id),
                font: .systemFont(ofSize: 13.5 * CGFloat(fontScale > 0 ? fontScale : 1.0)),
                textColor: UIColor(Theme.textPrimary),
                isActive: $isSelectingText
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.systemBackground).opacity(0.97))
                .shadow(radius: 4)
        )
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .animation(.easeOut(duration: 0.2), value: isSelectingText)
    }
}
```

**commit**: `feat(ui): text selection mode via context menu overlay`

---

## 规则

- 按 Task 1-2 顺序做，每个单独 commit + push
- 不动 `.textSelection(.enabled)`（留着无害，删了可能影响 macOS）
- 不动 `.contextMenu` 现有按钮的顺序
- 不动 MarkdownUI 渲染逻辑
- 禁触文件清单：`MessageContentWebView.swift`, `ConversationViewModel.swift`, `ChatService.swift`

---

## 验证清单

- [ ] build 通过
- [ ] 长按助手消息气泡 → 菜单里出现"选取文本"按钮
- [ ] 点"选取文本" → 气泡上出现覆盖层，文本可选取（双击选词、长按拖选都行）
- [ ] 选取文本后点"拷贝" → 剪贴板里是选中的部分（不是整条消息）
- [ ] 点"完成" → 覆盖层消失，回到正常气泡
- [ ] 用户消息同样可以长按→选取文本
- [ ] 覆盖层内滚动正常（长消息）
- [ ] 暗色模式下覆盖层颜色正常
