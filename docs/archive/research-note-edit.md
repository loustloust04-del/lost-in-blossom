# Research: 便签双击编辑

## 现状

便签贴到画布后无法修改内容。PlacedSticker 有 `noteContent` 和 `noteStyle` 字段，但没有编辑入口。

## 需求

双击画布上的便签 → 弹出编辑浮窗 → 修改文字/样式 → 确认 → 便签更新。

## 实现点

### 触发方式
- 编辑模式下**双击**便签 → 弹出 NoteStickerEditor（复用现有组件）
- 或者右键菜单加"编辑内容"选项

### 数据流
1. 双击 → 记录当前编辑的 PlacedSticker id
2. 弹出 NoteStickerEditor，预填现有 content + style
3. 确认 → 更新 PlacedSticker.noteContent 和 noteStyle
4. save

### NoteStickerEditor 改动
当前 NoteStickerEditor 只有 `onConfirm: (String, NoteStyle) -> Void`，创建模式。
需要支持编辑模式：传入初始 text + style，按钮文字改为"更新"。

### StickerCanvasLayer 改动
- 便签 item 加 `.onTapGesture(count: 2)` 双击手势
- 加 `@State editingNoteId: UUID?` 和 `.sheet` 绑定
- 或者用 stickerVM 管理编辑状态
