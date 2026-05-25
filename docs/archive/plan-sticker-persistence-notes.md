# Plan: 贴纸持久化 + 便签流程

> 依赖: `docs/research-sticker-persistence-notes.md`

---

## Task 1: 持久化修复（5 分钟）

- [ ] **1.1** `StickerViewModel.placeSticker()` 末尾加 `try? context.save()`
- [ ] **1.2** `StickerViewModel.placeNote()` 末尾加 `try? context.save()`
- [ ] **1.3** `StickerViewModel.removePlacedSticker()` 末尾加 `try? context.save()`
- [ ] **1.4** `StickerViewModel.deleteAsset()` 末尾加 `try? context.save()`
- [ ] **1.5** Build 验证

## Task 2: StickerAsset 支持便签类型

- [ ] **2.1** `Models/StickerAsset.swift` 加三个字段：
  ```swift
  var assetType: String = "image"    // "image" | "note"
  var noteContent: String?           // 便签文字
  var noteStyle: String?             // 便签样式
  ```
- [ ] **2.2** 加一个便签构造器：
  ```swift
  init(noteContent: String, noteStyle: String, profileId: String)
  ```
- [ ] **2.3** Build 验证

## Task 3: 新建便签 → 存入贴纸库

- [ ] **3.1** `StickerViewModel` 加 `createNoteAsset(content:style:profileId:context:)` 方法：创建便签类型的 StickerAsset，insert + save + 加到 stickerAssets 数组
- [ ] **3.2** `StickerLibraryView` 的 NoteStickerEditor 回调改为调用 `createNoteAsset`（不再调 `placeNote`）
- [ ] **3.3** Build 验证

## Task 4: Gallery 显示便签

- [ ] **4.1** `StickerLibraryView` 的 Gallery 区分 assetType：
  - "image" → 现有 StickerThumbnailView（图片缩略图）
  - "note" → 新的 NoteThumbnailView（便签预览小卡片：样式背景 + 文字截取）
- [ ] **4.2** 便签缩略图也支持 `.onDrag`（导出 asset id）
- [ ] **4.3** Build 验证

## Task 5: 拖放便签到画布

- [ ] **5.1** `CardFlowView.handleStickerDrop` 里，检查 asset 类型。如果是便签，PlacedSticker 的 noteContent/noteStyle 从 StickerAsset 复制过来
- [ ] **5.2** `StickerView` 渲染时：如果 `sticker.isNote`，用 PlacedSticker 的 noteContent/noteStyle。如果没有（旧数据兼容），也检查 StickerAsset 的
- [ ] **5.3** Build + 端到端测试：新建便签 → 出现在库 → 拖到画布 → 显示便签内容
- [ ] **5.4** Commit + push
