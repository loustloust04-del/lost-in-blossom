# Plan: 贴纸搜索 + 重名处理

---

- [ ] **1** 导入去重命名：`StickerViewModel.importImages()` 检查现有同名贴纸，自动加序号"名称 (2)"
- [ ] **2** `SearchService` 加 `searchPlacedStickers(keyword:profileId:container:)` — 搜 asset name + noteContent，返回带 conversationId 的结果
- [ ] **3** `SidebarView` 新增 `StickerMatchRow`（缩略图 + 贴纸名 + 对话标题）
- [ ] **4** `SidebarView.triggerSearch()` 追加贴纸搜索，结果拼在消息结果下方
- [ ] **5** 搜索 FilterChip 加"贴纸"——只看贴纸搜索结果
- [ ] **6** 点击贴纸结果 → 跳转到对话 + 滚动到 nearestMessageId
- [ ] **7** Build + commit push
