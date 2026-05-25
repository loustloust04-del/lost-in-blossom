# Plan: 贴纸右键菜单

> 依赖: `docs/research-sticker-contextmenu.md`

---

- [ ] **1** StickerViewModel 加复制粘贴支持：
  - `copiedStickerSnapshot: StickerSnapshot?` 结构体（assetId, noteContent, noteStyle, scale, rotation）
  - `copySticker(_:)` — 快照选中贴纸
  - `pasteSticker(at:conversationId:profileId:context:)` — 用快照创建新贴纸，position 偏移 20pt
  - `bringToFront(_:context:)` — zIndex = max + 1
  - `sendToBack(_:context:)` — zIndex = min - 1
  - `renameAsset(_:newName:context:)` — 改 StickerAsset.name

- [ ] **2** StickerCanvasLayer 的 stickerItem 加 `.contextMenu`：
  - 复制 / 粘贴 / 删除
  - 重命名（弹 alert）
  - 置于最前 / 置于最后
  - 修改描边（子菜单，仅图片贴纸）

- [ ] **3** 快捷键：编辑模式下 ⌘C/⌘V/⌫/]/[ 生效

- [ ] **4** Build + 测试 + commit push
