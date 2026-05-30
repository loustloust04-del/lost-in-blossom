# 任务：照片发送功能 + 标签删除按钮

## Task 1: 照片发送功能

`AddToChatSheet.swift` 的 PhotosPicker 选中照片后目前只有 TODO 注释。需要补全完整流程。

### 1a. 照片选择 → 数据提取

在 `onChange(of: photoPickerItems)` 回调中：

```swift
.onChange(of: photoPickerItems) { _, newItems in
    guard let item = newItems.first else { return }
    Task {
        if let data = try? await item.loadTransferable(type: Data.self) {
            // 压缩到合理大小（最大 1MB）
            if let uiImage = UIImage(data: data),
               let compressed = uiImage.jpegData(compressionQuality: 0.7) {
                // 传递给输入框
                pendingImageData = compressed
            }
        }
        photoPickerItems = []
        dismiss()
    }
}
```

### 1b. 图片传递给 ChatInputBar

需要一个机制把选中的图片数据传到 ChatInputBar：

- 方案：在 CardFlowView 中加一个 `@State var pendingImageData: Data?`
- AddToChatSheet 通过 Binding 写入
- ChatInputBar 读取这个 Binding，非 nil 时在输入框上方显示缩略图预览
- 预览区有一个 X 按钮可以移除图片

### 1c. 输入框图片预览

在 ChatInputBar 的输入框上方（TextField 之上）：

```
┌──────────────────────────────────┐
│ [缩略图 60x60]  photo.jpg  [X]  │  ← 图片预览条
├──────────────────────────────────┤
│ 输入框                      [发送] │
└──────────────────────────────────┘
```

- 缩略图：60x60，圆角 8，从 pendingImageData 生成 UIImage
- 文件名：固定显示 "photo.jpg"
- X 按钮：点击清空 pendingImageData

### 1d. 发送时构建多模态消息

在发送消息的逻辑中（找到构建 API 请求 messages 数组的位置）：

如果 pendingImageData 非 nil：
- 将用户消息的 content 从纯文本字符串改为 content blocks 数组：

```json
[
  {
    "type": "image",
    "source": {
      "type": "base64",
      "media_type": "image/jpeg",
      "data": "<base64 encoded>"
    }
  },
  {
    "type": "text",
    "text": "用户输入的文字"
  }
]
```

- 发送后清空 pendingImageData
- MessageNode 的 contentType 设为 "multimodal_text"

### 1e. 聊天气泡中渲染图片

在消息渲染视图中，如果 contentType == "multimodal_text"：
- 解析 content 中的 base64 图片数据
- 在文字上方显示图片（宽度最大 200pt，保持宽高比）
- 图片可以点击放大查看（用 fullScreenCover 或 sheet 显示原图）

**注意**：图片数据可能很大。考虑把 base64 存在 MessageNode 的 content 字段中，或者用 @Attribute(.externalStorage) 另存。先用简单方案（存在 content 里），后续优化。

---

## Task 2: 标签删除按钮

`SidebarView.swift` 已有 `deleteTag(id:)` 函数（约 line 1096），但前端没有删除按钮。

在 SidebarView 的标签列表中，每个标签旁边添加删除功能：

- 方案 A（推荐）：标签支持 swipe-to-delete（`.swipeActions { Button(role: .destructive) { deleteTag(id: id) } label: { Label("删除", systemImage: "trash") } }`）
- 方案 B：长按标签弹出 context menu，包含「删除」选项

两种方案选一个实现即可。目标是让用户可以删除错误添加的标签（比如一个叫"啊啊啊"的测试标签）。

---

两个 task 一个 commit：`feat: photo send in chat + tag delete button`

读 CLAUDE.md 的蠢事大全。
