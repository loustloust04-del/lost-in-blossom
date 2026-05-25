# Research: 便签导出 PNG

## 目标

编辑模式下右键/长按便签 → "导出为图片" → 渲染成 PNG ��存/分享。

## 现有基础设施

### 便签渲染（StickerView.swift:73-112）

```swift
private var noteStickerContent: some View {
    let style = sticker.noteStyle ?? "yellow_square"
    return Text(sticker.noteContent ?? "")
        .font(.system(size: 12))
        .foregroundColor(noteTextColor(style))
        .padding(10)
        .frame(minWidth: 80, maxWidth: 160, minHeight: 40)
        .background(noteBackground(style))
        .clipShape(RoundedRectangle(cornerRadius: noteCornerRadius(style)))
}
```

4 种样式：yellow_square / pink_rounded / glass / torn_paper。

### ImageRenderer 已有用例（DrawingBoardSheet.swift:361-388）

```swift
let renderer = ImageRenderer(content: drawingView)
renderer.scale = 2.0
guard let cgImage = renderer.cgImage else { return }
#if os(macOS)
let rep = NSBitmapImageRep(cgImage: cgImage)
guard let pngData = rep.representation(using: .png, properties: [:]) else { return }
#else
let uiImage = UIImage(cgImage: cgImage)
guard let pngData = uiImage.pngData() else { return }
#endif
```

### 剪贴板（CardFlowView / SettingsView）

```swift
#if os(macOS)
NSPasteboard.general.clearContents()
NSPasteboard.general.setString(content, forType: .string)
#else
UIPasteboard.general.string = content
#endif
```

### 菜单位置

- **macOS**：StickerCanvasLayer `stickerContextMenu()` — SwiftUI .contextMenu
- **iOS 编辑模式**：StickerGestureOverlay `contextMenuInteraction` — UIContextMenuInteraction
- **贴纸库**：StickerLibraryView `.contextMenu` — 库里也可以加

## 技术方案

1. **渲染**：用 `ImageRenderer` 渲染便签的 SwiftUI View → CGImage → PNG Data
2. **导出方式**：
   - macOS：`NSSavePanel` 保存文件 + 可选复制到剪贴板
   - iOS：`UIActivityViewController` 分享（保存到相册/AirDrop/复制等）
3. **触发点**：在三处菜单���便签条件分支里加"导出为图片"

## 注意事项

- 便签渲染时用的 12pt 字体太小，导出时应该放大（scale = 3.0 或更高）
- glass 样式是半透明的，需要考虑是否加不透明背景
- `ImageRenderer` 要在 @MainActor 上调用
- 便签有 scale 和 rotation，导出时应该用原始尺寸（不带画布上的缩放/旋转）
