# Plan: iOS 贴纸键盘面板

> 依赖: `docs/research-ios-sticker-keyboard.md`

---

- [ ] **1** 新建 `Views/StickerKeyboardPanel.swift`（iOS only）：
  - 高度 ~300pt 面板
  - 顶部工具栏（选择/贴纸库/便签/画画/完成）
  - 下方内嵌 Gallery 网格（3列，可滚动）
  - 点击贴纸 → 放到当前对话画布

- [ ] **2** `ChatInputBar` 左侧加贴纸按钮（iOS only）：
  - 🎨 图标按钮
  - 点击 → toggle showStickerPanel + 收起键盘

- [ ] **3** `CardFlowView` iOS safeAreaInset 加条件判断：
  - showStickerPanel ? StickerKeyboardPanel : ChatInputBar
  - 切换动画

- [ ] **4** Build iOS + macOS 双平台验证
- [ ] **5** commit push
