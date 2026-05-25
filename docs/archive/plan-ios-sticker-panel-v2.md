# Plan: iOS 贴纸面板 v2

---

- [ ] **1** StickerKeyboardPanel 精简：去掉搜索栏，只留便签/画画按钮 + 键盘切换 + 纯贴纸网格
- [ ] **2** 网格贴纸加 `.onDrag`（NSItemProvider，跟 macOS Gallery 一样）
- [ ] **3** CardFlowView 的 `.onDrop` 去掉 `#if os(macOS)` 限制，iOS 也支持拖放
- [ ] **4** StickerLibraryView（右栏）contextMenu 加"添加到对话"选项
- [ ] **5** Build iOS + macOS 双平台验证
- [ ] **6** commit push
