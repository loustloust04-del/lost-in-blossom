# 任务：双击消息弹出文本选取视图

读 CLAUDE.md。不引入 regression。

## 问题

当前消息气泡上的长按手势已被上下文菜单占用，导致 `.textSelection(.enabled)` 无法正常触发文本选择。用户无法部分选取消息文本进行复制。

## 方案

双击消息气泡 → 弹出一个半屏 Sheet，显示消息的完整文本（含思考链）。在这个 Sheet 里文本可以自由长按选取、拖拽选区、复制。

## 实现

### Step 1: 创建 TextSelectSheet

新建 `MemoryPalace/Views/Components/TextSelectSheet.swift`：

```swift
import SwiftUI

struct TextSelectSheet: View {
    let text: String
    let thinkingText: String? // 思考链内容（如果有）
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 思考链（如果有）
                    if let thinking = thinkingText, !thinking.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("思考过程")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(thinking)
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    
                    // 正文
                    Text(text)
                        .font(.system(size: 16))
                        .textSelection(.enabled)
                }
                .padding()
            }
            .navigationTitle("选取文本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        UIPasteboard.general.string = text
                        // 震动反馈
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } label: {
                        Label("复制全部", systemImage: "doc.on.doc")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
```

### Step 2: 在消息气泡上加双击手势

文件：`MemoryPalace/Views/CardFlowView.swift`

找到助手消息气泡的 View（渲染 AI 回复的部分）。加 state 和手势：

```swift
@State private var textSelectNode: MessageNode? = nil
```

在消息气泡的 View 上加：
```swift
.onTapGesture(count: 2) {
    textSelectNode = node // node 是当前消息
}
.sheet(item: $textSelectNode) { node in
    TextSelectSheet(
        text: node.text,
        thinkingText: node.thinkingText
    )
}
```

注意：`.onTapGesture(count: 2)` 是双击手势。它和单击手势可以共存（SwiftUI 会自动区分）。不会跟长按手势冲突。

### Step 3: 如果 MarkdownUI 组件不支持 textSelection

如果消息用了 MarkdownUI 渲染，MarkdownUI 可能不支持 `.textSelection(.enabled)`。在 TextSelectSheet 里用纯 Text 显示即可（不需要 Markdown 渲染，因为这个 sheet 的目的就是让用户选取文本）。

如果想保留 Markdown 格式，可以用 `AttributedString(markdown:)` 配合 Text 显示。

---

一个 commit：`feat: double-tap message to open text selection sheet`
