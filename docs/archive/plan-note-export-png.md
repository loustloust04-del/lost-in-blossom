# Plan: 便签导出 PNG

## 改动

### 1. 导出渲染函数（StickerViewModel）

加一个 `exportNoteAsPNG(sticker:)` 方法：
- 构造一个独立的便签 SwiftUI View（复用 StickerView 的样式逻辑，但不带 scale/rotation）
- `ImageRenderer` 渲染，`scale = 3.0`（高清导出）
- glass 样式加白色不透��底（否则导出的 PNG 背景透明看不清）
- 返��� `Data?`（PNG）

### 2. 分享逻辑（StickerViewModel）

加一个 `shareNotePNG(data:from:)` 方法，双平台分发：
- **macOS**：`NSSavePanel`，默认文件名 "便签.png"，保存到用户选的位置
- **iOS**：设 `exportedNotePNGData: Data?`，触发 SwiftUI `.sheet` 里的 `ShareLink` 或 `UIActivityViewController`

### 3. 菜单添加

三处加"导出为图片"按钮（仅 `sticker.isNote` 时显示）：

| 位置 | 文件 | 方式 |
|------|------|------|
| macOS ���键菜单 | StickerCanvasLayer `stickerContextMenu()` | SwiftUI Button |
| iOS 长按菜单 | StickerGestureOverlay `contextMenuInteraction` | UIAction |
| 贴纸库右键 | StickerLibraryView `.contextMenu` | SwiftUI Button |

放在"编辑内容"按钮��面、复制按钮上面。

## 文件清单

| 文件 | 改动 |
|------|------|
| `ViewModels/StickerViewModel.swift` | +exportNoteAsPNG(), +shareNotePNG(), +exportedNotePNGData |
| `Views/StickerCanvasLayer.swift` | stickerContextMenu 加"导出为图片" |
| `Views/StickerGestureOverlay.swift` | contextMenuInteraction 加"导出为图片" |
| `Views/StickerLibraryView.swift` | contextMenu 加"导出为图片" |
| `Views/CardFlowView.swift` | iOS: .sheet 展示分享面板 |

## Checklist

- [x] **1.** StickerViewModel 加渲染 + 导出方法
- [x] **2.** macOS 右键菜单加"导出为图片"
- [x] **3.** iOS 长按菜单加"导出为图片"
- [x] **4.** 贴纸库右键菜单加"导出为图片"
- [x] **5.** iOS 分享面板（UIActivityViewController）
- [x] **6.** Build 双���台验证
