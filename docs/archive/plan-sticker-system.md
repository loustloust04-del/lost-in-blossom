# Plan: 贴纸系统 (Sticker System)

> 依赖: `docs/research-sticker-system.md`
> 分支: `feature/sticker-system`（基于 `feature/merge-import`）

---

## Phase 1: 数据层 + 文件存储

搭地基。没有 UI，纯模型和服务。

- [ ] **1.1** 新建 `Models/StickerAsset.swift` — 贴纸库资产模型（id, name, imagePath, thumbnailPath, borderStyle, borderWidth, tags, createdAt, profileId）
- [ ] **1.2** 新建 `Models/PlacedSticker.swift` — 画布贴纸实例模型（id, stickerAssetId?, conversationId, nearestMessageId?, positionX/Y, rotation, scale, zIndex, noteContent?, noteStyle?, placedAt, profileId）
- [ ] **1.3** `MemoryPalaceApp.swift` — ProfileManager.makeContainer Schema 注册 StickerAsset + PlacedSticker
- [ ] **1.4** 新建 `Services/StickerFileManager.swift` — 贴纸文件存储管理：
  - `stickerDirectory(profileId:)` → 返回 `~/Library/Application Support/MemoryPalace/stickers/{profileId}/`
  - `saveStickerImage(_:id:profileId:)` → 存 PNG + 生成缩略图
  - `loadStickerImage(path:)` → 读取
  - `deleteStickerFiles(id:profileId:)` → 删除
- [ ] **1.5** Build 验证

## Phase 2: 抠图 + 描边引擎

核心图像处理。可以用单元测试或临时 UI 验证。

- [ ] **2.1** 新建 `Services/SubjectLifter.swift` — Apple Vision 抠图封装：
  - `liftSubject(from: NSImage) async throws -> NSImage` — 后台线程执行 VNGenerateForegroundInstanceMaskRequest
  - 返回透明背景的 NSImage
- [ ] **2.2** 新建 `Services/StickerBorderRenderer.swift` — 描边渲染引擎：
  - `enum BorderStyle: String, CaseIterable, Codable` — none, solid_white, solid_black, gradient_rainbow, laser, lace, glitter, neon
  - `renderBorder(on image: NSImage, style: BorderStyle, width: CGFloat) -> NSImage` — CoreImage alpha 膨胀 + 样式填充
  - 先实现 none + solid_white + solid_black + gradient_rainbow 四种，其余 stub
- [ ] **2.3** Build 验证

## Phase 3: 贴纸导入流程

用户选图片 → 抠图 → 选描边 → 保存到贴纸库。

- [ ] **3.1** 新建 `Views/StickerImportSheet.swift` — 导入浮窗：
  - NSOpenPanel 选图（支持多选）
  - 自动抠图（显示 ProgressView）
  - 默认描边 solid_white
  - 预览结果
  - 保存为 StickerAsset + 文件落盘
- [ ] **3.2** 新建 `ViewModels/StickerViewModel.swift` — 贴纸状态管理：
  - `stickerAssets: [StickerAsset]` — 当前楼层贴纸库
  - `placedStickers: [PlacedSticker]` — 当前对话已贴的贴纸
  - `loadLibrary(profileId:context:)`
  - `loadPlacedStickers(conversationId:context:)`
  - `importImages(urls:profileId:context:)` async
  - `deleteAsset(_:context:)`
- [ ] **3.3** Build 验证

## Phase 4: 右栏贴纸库 Gallery

Gallery 面板 + 飘入动画。

- [ ] **4.1** `MemoryPanelView.swift` — RightPanelTab 加 `.sticker` case，tab 按钮加一个 🎨 贴纸
- [ ] **4.2** 新建 `Views/StickerLibraryView.swift` — Gallery 面板：
  - 网格布局（LazyVGrid，3 列）
  - 每个贴纸缩略图 + 微旋转（±5°随机）
  - 飘入动画：从随机位置 + 旋转 ±30° → 目标位置 + 微旋转，spring，delay 0.03s/个
  - 底部"导入贴纸"按钮
  - 贴纸库内搜索（按 name + tags）
  - 右键菜单：改描边 / 改名 / 删除
- [ ] **4.3** Gallery 里贴纸支持 `.onDrag` — 返回 NSItemProvider (sticker asset id)
- [ ] **4.4** Build 验证 + 视觉检查

## Phase 5: 画布贴纸层 + 拖放

贴纸贴到对话画布上。

- [ ] **5.1** 新建 `Views/StickerView.swift` — 单个贴纸渲染：
  - 从文件加载图片
  - 纸质感：noise overlay (opacity 0.03) + shadow + 边角微翘 rotation3DEffect
  - 贴上动画：spring scale + rotation 抖动
  - 撕掉动画：rotation3DEffect 翻转 + opacity 渐出
- [ ] **5.2** 新建 `Views/StickerCanvasLayer.swift` — 画布叠加层：
  - ForEach placedStickers，每个用 StickerView + `.position(x:y:)`
  - 默认 `allowsHitTesting(false)` — 不拦截消息点击
  - 长按进入编辑模式 → 贴纸可拖动/双指缩放/旋转
  - 编辑模式下：贴纸边框高亮 + 删除按钮（撕掉动画）
- [ ] **5.3** `CardFlowView.swift` — ScrollView 内加 ZStack，叠加 StickerCanvasLayer
  - 需要 GeometryReader 测量内容高度
  - `.onDrop(of:)` 接收从 Gallery 拖来的贴纸
  - drop 坐标转换：视口坐标 → ScrollView content 坐标
- [ ] **5.4** 放置时自动计算 nearestMessageId — 遍历 currentPath，找 Y 坐标最近的消息
- [ ] **5.5** Build 验证 + 拖放测试

## Phase 6: 便签贴纸

便签编辑浮窗 + 便签渲染。

- [ ] **6.1** 新建 `Views/NoteStickerEditor.swift` — 便签编辑浮窗：
  - 样式选择：黄色方块、粉色圆角、毛玻璃、撕边白纸条
  - 文本编辑区（极简模式：纯文本框 + 确认）
  - 手写字体选择 + 颜色笔选择（进阶模式）
  - 确认后创建 PlacedSticker（noteContent + noteStyle）
- [ ] **6.2** StickerView 支持便签渲染 — 根据 noteStyle 切换样式：
  - yellow_square: 黄色背景 + 微阴影
  - pink_rounded: 粉色圆角
  - glass: 毛玻璃 `.ultraThinMaterial`
  - torn_paper: 白色 + 撕边效果（不规则 clipShape）
- [ ] **6.3** Gallery 里加"新建便签"入口
- [ ] **6.4** Build 验证

## Phase 7: 搜索集成

搜索结果里展示贴纸。

- [ ] **7.1** `SearchService.swift` — 加 `searchStickers(keyword:profileId:container:) async -> [StickerAsset]`：按 name + tags 搜索
- [ ] **7.2** `SidebarView.swift` — 搜索结果如果 nearestMessageId 匹配，显示贴纸缩略图（带旋转角度）
- [ ] **7.3** `SidebarView.swift` — 图层筛选 UI：FilterChip 加"便签""图片贴纸""按对话"
- [ ] **7.4** Build 验证

## Phase 8: 描边样式补全 + 修改描边

补齐剩余描边样式，支持事后修改。

- [ ] **8.1** StickerBorderRenderer — 实现 laser（hueRotation 渐变）、lace（虚线 pattern）、glitter（噪波）、neon（外发光）
- [ ] **8.2** 贴纸库右键"修改描边" → 弹出描边选择器 → 重新渲染 PNG → 更新文件和模型
- [ ] **8.3** Build 验证

---

## 实施顺序和边界

- Phase 1-3 是地基，不涉及现有 UI 改动，风险最低
- Phase 4 第一次动现有文件（RightPanelTab），但只加一个 enum case + 一个 tab 按钮
- Phase 5 改 CardFlowView，是最核心也最敏感的改动——小心不要影响消息渲染性能
- Phase 6-7 都是增量
- Phase 8 纯图像处理，不影响已有功能
- 每个 Phase 结束都 build + commit + push
