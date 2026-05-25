# Plan: 描边预览 + 贴纸滤镜

---

- [ ] **1** StickerAsset 加 `filterStyle: String = "none"` 字段
- [ ] **2** 新建 `Services/StickerFilterRenderer.swift` — 4 种滤镜：vintage / holographic / pixel / comic（CIFilter）
- [ ] **3** 导入流程加滤镜步骤：抠图 → 滤镜(默认 none) → 描边 → 存 PNG
- [ ] **4** 新建 `Views/StickerStyleSheet.swift` — 描边+滤镜预览 sheet：
  - 上半区：描边网格（8 种，缩略图预览）
  - 下半区：滤镜网格（5 种，缩略图预览）
  - 选中高亮，底部"应用"按钮
- [ ] **5** Gallery 右键"修改样式" → 弹 StickerStyleSheet（替代原来的描边子菜单）
- [ ] **6** 应用后重新渲染 PNG + 刷新 Gallery 缩略图
- [ ] **7** Build + commit push
