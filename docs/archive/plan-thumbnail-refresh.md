# Plan: Gallery 缩略图刷新

---

- [ ] **1** `StickerThumbnailView`：`.onAppear { loadThumbnail() }` 改为 `.task(id: asset.thumbnailPath) { loadThumbnail() }`，路径变化自动重载
- [ ] **2** `loadThumbnail()` 去掉 `guard thumbnailImage == nil` 保护，允许重新加载
- [ ] **3** Build + commit push
