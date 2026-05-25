# Plan: 搜索集成 + 设置贴纸 Tab + 导入导出

> 依赖: `docs/research-search-settings-export.md`

---

## Task 1: 设置贴纸 Tab

- [ ] **1.1** `SettingsView.swift` — SettingsTab enum 加 `case sticker = "贴纸"`
- [ ] **1.2** body 的 tab 内容 switch 加 `case .sticker: stickerSettingsTab`
- [ ] **1.3** `stickerSettingsTab` 视图：贴纸库统计 + 默认描边样式 + 导出/导入按钮
- [ ] **1.4** Build

## Task 2: 导出贴纸包（资产 + 画布布局）

- [ ] **2.1** `Services/StickerPackExporter.swift`：
  - 查所有 StickerAsset → 序列化 JSON（assets.json）
  - 查所有 PlacedSticker → 序列化 JSON（placements.json）— 含 conversationId/position/rotation/scale/zIndex/noteContent/noteStyle
  - 收集所有 PNG 文件
  - 临时目录 → 复制 JSON + PNG → zip 打包为 `.stickerpack`
  - NSSavePanel 选保存位置
- [ ] **2.2** 设置 Tab 里"导出贴纸包"按钮
- [ ] **2.3** Build

## Task 3: 导入贴纸包（资产 + 画布归位）

- [ ] **3.1** `Services/StickerPackImporter.swift`：
  - NSOpenPanel 选 `.stickerpack`
  - 解压 → 读 assets.json + placements.json
  - 创建 StickerAsset（ID 映射：旧 UUID → 新 UUID，防冲突）
  - 复制 PNG 到贴纸目录（文件名用新 UUID）
  - 创建 PlacedSticker（stickerAssetId 用映射后的新 UUID，位置/旋转/缩放原样恢复）
  - save
- [ ] **3.2** 设置 Tab 里"导入贴纸包"按钮
- [ ] **3.3** Build

## Task 4: 搜索结果显示贴纸缩略图

- [ ] **4.1** `SidebarView.swift` — triggerSearch 后额外查 PlacedSticker（按 nearestMessageId）
- [ ] **4.2** ContentMatchRow 右侧加贴纸小缩略图（如果该消息有关联贴纸）
- [ ] **4.3** Build

## Task 5: commit push
