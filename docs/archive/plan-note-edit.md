# Plan: 便签双击编辑

- [ ] **1** NoteStickerEditor 支持编辑模式：加 `initialText`/`initialStyle` 参数，按钮文字区分"保存到贴纸库"/"更新"
- [ ] **2** StickerViewModel 加 `editingNoteStickerId: UUID?`
- [ ] **3** StickerCanvasLayer：便签 item 双击 → 设 editingNoteStickerId → sheet 弹出 NoteStickerEditor（编辑模式）
- [ ] **4** 右键菜单加"编辑内容"（仅便签）
- [ ] **5** 确认后更新 PlacedSticker.noteContent/noteStyle + save
- [ ] **6** Build + commit push
