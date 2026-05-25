# Research: 锁定贴纸

## 现状

PlacedSticker 模型没有 `isLocked` 字段。所有手势（拖拽/缩放/旋转）和操作（删除/编辑便签）都不做锁定检查。

## 需要改的文件

### 1. PlacedSticker.swift — 模型

加 `var isLocked: Bool = false`。SwiftData 会自动迁移（新增 Bool 有默认值）。

### 2. StickerViewModel.swift — 状态管理

- 加 `toggleLock(_ sticker:, context:)` 方法
- `removePlacedSticker()` 加锁定 guard

### 3. StickerGestureOverlay.swift — iOS 手势

六个手势处理器中需要加锁定 guard 的：
- `handlePan` (.began 阶段) — 阻止拖拽
- `handlePinch` (.began 阶段) — 阻止缩放
- `handleRotate` (.began 阶段) — 阻止旋转
- `handleDoubleTap` — 阻止编辑便签

不需要 guard 的：
- `handleSingleTap` — 锁定的贴纸仍然可以选中（否则无法解锁）
- `handleTwoFingerDoubleTap` — undo 是全局的，不受锁定影响

Context menu 加"锁定/解锁"按钮。

### 4. StickerCanvasLayer.swift — macOS

- `stickerContextMenu()` 加"锁定/解锁"按钮
- macOS 拖拽 DragGesture 加锁定 guard
- 键盘 ⌫ 删除加锁定 guard
- `StickerSelectionOverlay`：锁定时边框变灰 + 隐藏把手 + 隐藏删除按钮

### 5. 不需要改的

- StickerLibraryView — 锁定是 per-placed-sticker，库里没有
- StickerView — 纯渲染，锁定贴纸外观不变
- NoteExportView — 导出不受锁定影响

## 锁定策略

**阻止：** 移动、缩放、旋转、删除、编辑便签内容
**允许：** 选中、复制、粘贴、层级调整、导出、undo

锁定状态不进 undo 栈（用户不需要撤回锁定操作）。

## 视觉反馈

- 选中框边框颜色从绿色变灰色
- macOS 把手（缩放/旋转/删除）隐藏
- 右键菜单显示"🔒 解锁"或"锁定"
