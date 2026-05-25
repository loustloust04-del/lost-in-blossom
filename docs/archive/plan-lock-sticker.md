# Plan: 锁定贴纸

## 改动

### 1. 模型（PlacedSticker.swift）

加一个字段：
```swift
var isLocked: Bool = false
```

SwiftData 自动迁移，不需要手动 migration。

### 2. ViewModel（StickerViewModel.swift）

加方法：
```swift
func toggleLock(_ sticker: PlacedSticker, context: ModelContext) {
    sticker.isLocked.toggle()
    try? context.save()
}
```

`removePlacedSticker()` 加 guard：锁定的贴纸不能删。

### 3. iOS 手势层（StickerGestureOverlay.swift）

四个手势处理器加 `guard !(selectedSticker?.isLocked ?? false)` ：
- handlePan (.began)
- handlePinch (.began/.changed)
- handleRotate (.began/.changed)
- handleDoubleTap

Context menu 加"锁定/解锁"按钮（在"层级"前面）。

### 4. macOS 画布层（StickerCanvasLayer.swift）

- `stickerContextMenu()` 加"锁定/解锁"按钮
- macOS DragGesture 加 guard
- 键盘 ⌫ 加 guard
- `StickerSelectionOverlay`：锁定时边框变灰 + 隐藏所有把手

## 文件清单

| 文件 | 改动 |
|------|------|
| `Models/PlacedSticker.swift` | +isLocked 字段 |
| `ViewModels/StickerViewModel.swift` | +toggleLock(), removePlacedSticker guard |
| `Views/StickerGestureOverlay.swift` | 手势 guard + 菜单按钮 |
| `Views/StickerCanvasLayer.swift` | 菜单按钮 + DragGesture guard + 键盘 guard + 选中框样式 |

## Checklist

- [x] **1.** PlacedSticker 加 isLocked 字段
- [x] **2.** StickerViewModel 加 toggleLock + removePlacedSticker guard
- [x] **3.** iOS StickerGestureOverlay 手势 guard + 菜单
- [x] **4.** macOS StickerCanvasLayer 菜单 + 手势 guard + 选中框
- [x] **5.** Build 验证
