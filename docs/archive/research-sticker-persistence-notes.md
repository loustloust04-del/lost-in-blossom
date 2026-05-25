# Research: 贴纸持久化 + 便签流程

## 问题 1: 重启后贴纸消失

### 现状分析

**StickerAsset（贴纸库）：**
- `importImages()` 里 `context.insert(asset)` + `context.save()` ✅ 有保存
- 但 `loadLibrary()` 只在 `StickerLibraryView.onAppear` 调用
- 如果 app 重启后用户没切到贴纸 tab，库不会加载 → 不影响持久化本身

**PlacedSticker（画布贴纸）：**
- `placeSticker()` 和 `placeNote()` 里 `context.insert(sticker)` ✅ 插入了
- **BUG: 没有 `context.save()`！** insert 后没有显式保存。SwiftData 自动保存时机不确定，如果 app 在自动保存前退出，数据丢失。
- `removePlacedSticker()` 里 `context.delete(sticker)` 也没有 save

**缩放/旋转/拖动：**
- StickerCanvasLayer 的 `onEnded` 里有 `try? modelContext.save()` ✅

### 修复

所有写操作后加 `try? context.save()`：
- `placeSticker()` 末尾
- `placeNote()` 末尾
- `removePlacedSticker()` 末尾
- `deleteAsset()` 末尾

### 加载时机

- `loadLibrary()` 需要在贴纸 tab 打开时调用 — 已有 ✅
- `loadPlacedStickers()` 需要在对话切换时调用 — CardFlowView 的 `onChange(of: selectedConversation)` 已有 ✅
- 但 app 重启后首次打开对话，`onAppear` 里的 `loadStickersForConversation` 会调用 ✅

**结论：主要问题是 `placeSticker/placeNote/remove/delete` 缺少 `context.save()`。**

---

## 问题 2: 便签流程

### 当前流程（错误）

```
新建便签 → 直接创建 PlacedSticker（画布实例）→ 贴在画布固定位置
```

问题：
- 便签不在贴纸库里显示
- 没法在其他对话里复用同一张便签
- 跳过了"库 → 拖放到画布"的统一流程

### 期望流程

```
新建便签 → 创建 StickerAsset（便签类型）→ 出现在贴纸库 Gallery → 拖到画布创建 PlacedSticker
```

### 数据模型改动

**StickerAsset 扩展：**
当前 StickerAsset 只有图片字段。需要支持便签类型：
- 加 `assetType: String` — "image" | "note"
- 加 `noteContent: String?` — 便签文字
- 加 `noteStyle: String?` — 便签样式

便签类型的 StickerAsset 没有 imagePath，用 noteContent + noteStyle 渲染。

**PlacedSticker 简化：**
`noteContent` 和 `noteStyle` 移到 StickerAsset 上。PlacedSticker 只负责定位（position/rotation/scale/zIndex），通过 `stickerAssetId` 引用便签资产。

但这有个取舍：如果便签内容在 Asset 上，那同一个便签资产拖出去多次，每个实例的文字都一样。如果想每个实例可以有不同的文字，就需要 PlacedSticker 保留 `noteContent` 做覆盖。

**方案：PlacedSticker 保留 `noteContent` 作为覆盖字段。**
- 如果 `noteContent == nil`，用 StickerAsset 的 noteContent
- 如果 `noteContent != nil`，用 PlacedSticker 自己的（编辑过的内容）

### Gallery 渲染改动

StickerLibraryView 当前只渲染图片缩略图（StickerThumbnailView）。需要区分 assetType：
- "image": 显示缩略图（现有逻辑）
- "note": 渲染便签预览（noteContent + noteStyle 的小卡片）

### 新建便签流程改动

1. 点"新建便签" → 弹出 NoteStickerEditor
2. 选样式 + 打字 + 确认
3. 创建 StickerAsset（assetType: "note", noteContent: text, noteStyle: style）
4. StickerAsset 出现在 Gallery
5. 从 Gallery 拖到画布 → 创建 PlacedSticker（stickerAssetId 指向这个便签 Asset）
