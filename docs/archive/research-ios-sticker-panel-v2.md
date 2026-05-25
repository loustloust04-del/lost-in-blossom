# Research: iOS 贴纸面板 v2

## 上版问题

1. 面板塞了搜索栏——太重，这是快速选贴纸的地方
2. 点击就贴——不对，应该拖出去
3. 卡卡的——Gallery 加载太重

## 正确交互（学 Telegram）

### 贴纸面板
- 纯贴纸网格（4列），可滚动
- 顶部只有：便签/画画两个小按钮 + 键盘切换按钮
- **没有搜索栏**（搜索在右栏贴纸库做）
- 网格里贴纸**可以拖出去**到对话区域

### 放置方式 A：从面板拖拽到对话
- 长按贴纸 → 拖起来 → 拖到上面的对话区域 → 松手放下
- iOS 原生 drag & drop（`.onDrag` + `.onDrop`）
- 面板在底部，对话在上面，跨区域拖拽

### 放置方式 B：右栏长按添加
- 右栏贴纸库（RightPanelView）里的贴纸
- 长按弹出菜单 → "添加到对话"
- 自动贴到当前可视区域中央

### 两种方式共存

## 技术要点

### iOS 拖拽
`.onDrag` 在 iOS 上支持（iPad 原生支持，iPhone 上也能用但体验一般）。
但从 safeAreaInset 里的面板拖到 ScrollView 里——需要 `.onDrop` 在 ScrollView 上。

CardFlowView 的 `.onDrop` 目前只有 `#if os(macOS)`，需要 iOS 也加上。

### 性能优化
- Gallery 用 LazyVGrid + 异步缩略图加载
- 缩略图用小尺寸（200x200 已有）
- 减少面板内的 view 复杂度

## 改动清单

1. StickerKeyboardPanel 精简——去搜索栏，纯网格
2. 网格贴纸加 `.onDrag`
3. CardFlowView iOS 也加 `.onDrop`（复用 handleStickerDrop 逻辑）
4. 右栏 StickerLibraryView contextMenu 加"添加到对话"
