# 任务：修复文本选取留白 + 文件选择器无法点击

> 两个 bug，一个任务文档。每个 bug 单独 commit。

---

## Bug 1：文本选取 UITextView 留白

### 问题
双击消息弹出的 TextSelectSheet 里，文字挤在上半部分，下半部分大片空白。

### 原因
UITextView 的 `isScrollEnabled` 默认为 true。启用滚动时 UITextView 不会向 SwiftUI 报告 intrinsicContentSize，导致 SwiftUI 用 `.frame(minHeight:)` 的固定值分配空间，文字和容器不匹配。

### 修复

**文件 1：`MemoryPalace/Views/Components/SelectableTextView.swift`**

在 `makeUIView` 里加一行：

```swift
func makeUIView(context: Context) -> UITextView {
    let tv = UITextView()
    tv.isEditable = false
    tv.isSelectable = true
    tv.isScrollEnabled = false          // ← 加这行！关闭滚动让 UITextView 自动撑开
    tv.font = font
    tv.textColor = textColor
    tv.backgroundColor = .clear
    tv.textContainerInset = .zero
    tv.textContainer.lineFragmentPadding = 0
    tv.dataDetectorTypes = [.link]
    tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return tv
}
```

**文件 2：`MemoryPalace/Views/Components/TextSelectSheet.swift`**

去掉两处固定高度：

- 把 `SelectableTextView(thinking...).frame(minHeight: 60)` 改成不加 `.frame(minHeight:)`
- 把 `SelectableTextView(text).frame(minHeight: 100)` 改成不加 `.frame(minHeight:)`

改后长这样：
```swift
if let thinking = thinkingText, !thinking.isEmpty {
    VStack(alignment: .leading, spacing: 4) {
        Text("思考过程")
            .font(.caption)
            .foregroundStyle(.secondary)
        SelectableTextView(
            thinking,
            font: .systemFont(ofSize: 15),
            textColor: .secondaryLabel
        )
        // 不要 .frame(minHeight: 60)
    }
    .padding()
    .background(Color(.systemGray6))
    .cornerRadius(12)
}

SelectableTextView(text)
// 不要 .frame(minHeight: 100)
```

### Commit
```
fix: text select sheet — disable UITextView scroll to fix whitespace
```

---

## Bug 2：文件选择器无法选取文件（根治）

### 问题
点"发送文件"弹出文件选择器，里面的文件全都点不动，无法选取。修了多次仍然不行。

### 根因
AddToChatSheet 本身是通过 `.sheet` 呈现的。在 sheet 内部再用 `.fullScreenCover` 弹出 UIDocumentPickerViewController = SwiftUI presentation 嵌套。UIDocumentPickerViewController 的触摸事件被 SwiftUI 的 hosting controller 层吃掉。

之前从 `.sheet` 改成 `.fullScreenCover` 只是换了嵌套方式，本质没变。在 sheet 里面用任何 SwiftUI presentation 弹 UIDocumentPickerViewController 都不行。

### 修复思路
跟 sticker 一样的模式：先 dismiss AddToChatSheet，然后在 CardFlowView 外层弹出文件选择器。文件选择器不在任何 sheet 内部。

### 修改步骤

**Step 1：AddToChatSheet 加回调，删掉内部的文件选择器**

文件：`MemoryPalace/Views/AddToChatSheet.swift`

1) 加一个回调属性（跟 onOpenSticker 并列）：
```swift
let onOpenFilePicker: () -> Void
```

2) 把"发送文件"按钮的 action 改成 dismiss + 回调：
```swift
// ── 行 1：文件 ──
Button {
    dismiss()
    onOpenFilePicker()
} label: {
    addToChatRow(
        icon: "doc.fill",
        iconColor: Color.red.opacity(0.8),
        title: "发送文件",
        trailing: nil
    )
}
.buttonStyle(.plain)
.rowEntrance(index: 1, appeared: appeared)
```

3) 删掉 AddToChatSheet 里所有文件选择器相关的东西：
- 删 `@State private var showFilePicker = false`
- 删 `@State private var fileErrorMessage: String?`
- 删整个 `.fullScreenCover(isPresented: $showFilePicker) { ... }` block
- 删整个 `.alert("文件添加失败" ...)` block

**Step 2：CardFlowView 在外层弹出文件选择器**

文件：`MemoryPalace/Views/CardFlowView.swift`

1) 加 state 变量（跟 showAddToChat 并列）：
```swift
@State private var showFilePicker = false
@State private var fileErrorMessage: String?
```

2) 修改 AddToChatSheet 的初始化，加上 onOpenFilePicker 回调：
```swift
.sheet(isPresented: $showAddToChat) {
    AddToChatSheet(
        onOpenSticker: {
            withAnimation(.easeInOut(duration: 0.25)) {
                showStickerPanel = true
                stickerVM.isEditingStickers = true
            }
        },
        onOpenFilePicker: {
            // 延迟 0.4 秒等 AddToChatSheet 完全 dismiss
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                showFilePicker = true
            }
        },
        pendingImageData: $pendingImageData,
        pendingFileData: $pendingFileData,
        pendingFileName: $pendingFileName
    )
}
```

3) 在 CardFlowView 的 body 里，跟 `.sheet(isPresented: $showAddToChat)` 同级，加上文件选择器的 sheet：
```swift
.sheet(isPresented: $showFilePicker) {
    DocumentPickerView(contentTypes: [.item]) { urls in
        showFilePicker = false
        guard let url = urls.first else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            if data.count > 10_485_760 {
                fileErrorMessage = "文件太大（超过 10MB）"
                return
            }
            pendingFileData = data
            pendingFileName = url.lastPathComponent
        } catch {
            fileErrorMessage = "读取文件失败: \(error.localizedDescription)"
        }
    } onCancel: {
        showFilePicker = false
    }
}
.alert("文件添加失败", isPresented: Binding(
    get: { fileErrorMessage != nil },
    set: { if !$0 { fileErrorMessage = nil } }
)) {
    Button("好的") { fileErrorMessage = nil }
} message: {
    Text(fileErrorMessage ?? "")
}
```

4) 确保 `import UniformTypeIdentifiers` 在 CardFlowView.swift 顶部（如果还没有的话）。

### 为什么这次能修好
文件选择器从 CardFlowView 层面弹出，不在任何 sheet 内部。UIDocumentPickerViewController 直接被 SwiftUI 的顶层 presentation 管理，触摸事件链完整，不会被嵌套的 hosting controller 吃掉。

跟 ImportView、PersonaSettingsTab 里正常工作的 DocumentPickerView 是同一个层级。

### Commit
```
fix: file picker — move out of nested sheet to fix touch events
```

---

## 测试清单
- [ ] 双击消息气泡 → 文本选取界面无留白，文字撑满容器
- [ ] 长文本也正常（ScrollView 负责滚动，不是 UITextView）
- [ ] 点"发送文件" → AddToChatSheet 关闭 → 文件选择器弹出
- [ ] 文件选择器里能正常点击、选取文件
- [ ] 选取后文件出现在输入栏
- [ ] 取消文件选择器回到聊天界面
- [ ] 文件超过 10MB 弹错误提示
- [ ] 照片选取仍然正常工作（没被改动影响）
