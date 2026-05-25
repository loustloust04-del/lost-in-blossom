# Research: 贴纸右键菜单

## 现状

贴纸在画布上没有右键菜单。编辑模式下只有：
- 长按进入编辑
- 拖拽移动
- 角手柄缩放
- 旋转手柄
- × 删除按钮

## 需求

参考 FigJam 右键菜单，适配贴纸场景：

| 功能 | 快捷键 | 说明 |
|------|--------|------|
| 复制 | ⌘C | 复制选中贴纸到剪贴板（内部格式） |
| 粘贴 | ⌘V | 在鼠标位置粘贴（偏移 20pt 防重叠） |
| 删除 | ⌫ | 撕掉动画 |
| — | — | 分隔线 |
| 重命名 | — | 弹出小输入框改 name |
| — | — | 分隔线 |
| 置于最前 | ] | zIndex 设为当前最大+1 |
| 置于最后 | [ | zIndex 设为当前最小-1 |
| — | — | 分隔线 |
| 修改描边 | — | 子菜单，列出 8 种描边样式（仅图片贴纸） |

## 实现位置

右键菜单应该加在 StickerCanvasLayer 的 `stickerItem()` 上，用 `.contextMenu {}`。

当前 stickerItem 的代码结构：
```swift
StickerView(...)
    .position(...)
    .zIndex(...)
    .onLongPressGesture { ... }
    .gesture(...)
    .onTapGesture { ... }
```

在 `.position()` 后加 `.contextMenu {}`。

## 复制粘贴实现

贴纸不是文本，不能用系统剪贴板的文本类型。方案：
- 用 StickerViewModel 内部状态：`copiedSticker: PlacedSticker?` 存复制的贴纸快照
- ⌘C → 记录当前选中贴纸的所有属性
- ⌘V → 用快照属性创建新 PlacedSticker，position 偏移 20pt
- 这是应用内剪贴板，不是系统剪贴板（够用）

## 重命名实现

便签贴纸：改 StickerAsset.name 或 PlacedSticker 上没有 name 字段
图片贴纸：改 StickerAsset.name

需要通过 stickerAssetId 找到对应的 StickerAsset。弹一个小 alert 输入框。

## 图层操作

PlacedSticker 有 `zIndex: Int`。
- 置于最前：`sticker.zIndex = (placedStickers.map(\.zIndex).max() ?? 0) + 1`
- 置于最后：`sticker.zIndex = (placedStickers.map(\.zIndex).min() ?? 0) - 1`
