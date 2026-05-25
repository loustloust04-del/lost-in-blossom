# 贴纸系统 — 待修复 & 待实现

> 当前状态：macOS 能贴贴纸到画布，能导入图片抠图。但交互体验粗糙，很多功能空壳。

---

## P0：必须修的 Bug

### 1. 缩放/旋转手势没有视觉反馈
MagnifyGesture + RotateGesture 代码写了，但用户看不到效果。
可能原因：
- MagnifyGesture 返回的是 magnification（相对值），直接赋给 scale 不对——应该乘以初始值
- RotateGesture 返回的是 rotation（相对值），直接赋给 rotation 不对——应该加上初始值
- 手势之间可能冲突（simultaneously 不一定同时生效）
**修法**：用 `@GestureState` 追踪手势增量，叠加到初始值上。并且给编辑中的贴纸加可见的控制手柄（角上的缩放点、旋转指示器）。

### 2. 便签在贴纸栏不显示
Gallery 只显示 `StickerAsset`（图片贴纸库资产）。便签直接创建的是 `PlacedSticker`（画布实例），没有对应的 StickerAsset。
**修法**：Gallery 底部加一个"已贴便签"区域，显示当前对话的便签列表。或者便签也先存为 StickerAsset（便签模板），贴的时候创建 PlacedSticker。

---

## P1：体验缺失

### 3. 贴纸模式工具栏（学 FigJam）
进入编辑模式后，底部 ChatInputBar 应该替换为贴纸工具栏：
- 选择工具（箭头）
- 便签工具（点击画布创建便签）
- 手势提示（双指缩放/旋转）
- 颜色/描边快速切换
- 删除按钮

### 4. 右键菜单（学 FigJam）
贴纸右键菜单应该有：
- **删除** ⌫
- **复制** ⌘C / **粘贴** ⌘V
- **导出为 PNG** ⇧⌘C
- 分隔线
- **置于最前** Bring to front `]`
- **置于最后** Send to back `[`
- 分隔线
- **锁定/解锁** ⇧⌘L
- **修改描边**（子菜单）

### 5. 编辑模式视觉反馈
- 选中的贴纸应该有明显的选框（蓝色虚线框 + 4 角控制点）
- 未选中的贴纸应该有淡淡的轮廓提示"这里有贴纸可编辑"
- 编辑模式下背景应该微暗（overlay 半透明遮罩），让贴纸更突出

### 6. 缩放/旋转控制手柄
不只靠手势——还要有可视的控制点：
- 四角拖拽 = 等比缩放
- 顶部旋转手柄 = 旋转
- 类似 Figma/FigJam 的选框 UI

---

## P2：功能补全

### 7. 便签双击编辑
贴上去的便签，双击弹出编辑浮窗，可修改内容和样式。

### 8. 图层管理
- 右键 → 置于最前/最后
- 快捷键 `]` / `[`
- 在编辑模式下可以看到图层列表？

### 9. 贴纸复制/粘贴
- 选中贴纸 ⌘C → ⌘V 复制一份（偏移 20pt）
- 或者 Option+拖拽 = 复制

### 10. 导出贴纸为 PNG
右键 → Copy as PNG，把贴纸图片复制到剪贴板。

### 11. 锁定贴纸
锁定后不可拖动/缩放/删除，防止误操作。PlacedSticker 加 `isLocked: Bool` 字段。

### 12. 描边预览
修改描边时应该有实时预览，而不是盲选。弹出一个 sheet 显示各种描边效果的对比。

### 13. 描边渲染后 Gallery 缩略图不刷新
updateBorder 改了文件但 StickerThumbnailView 的 @State thumbnailImage 不会自动更新。需要触发重新加载。

---

## P3：iOS 适配

### 14. iOS 导入用 PhotosPicker
`StickerImportSheet` 的 `pickImages()` 只有 macOS 分支。iOS 需要 `PhotosPicker`。

### 15. iOS 贴纸放置交互
macOS 是 drag & drop（onDrag → onDrop）。iOS 没有跨区域拖拽。
方案：学 Telegram——点击 Gallery 里的贴纸 → 自动贴到当前滚动位置中央。或者长按 Gallery 贴纸进入"放置模式"，然后点画布放下。

### 16. iOS 贴纸面板
学 Telegram：底栏贴纸面板替代键盘。按一下按钮键盘变成贴纸栏。

---

## 实施顺序建议

**第一轮**（让 macOS 基本可用）：
1. 修缩放/旋转手势 (#1)
2. 贴纸右键菜单 — 删除 + 置前/置后 (#4, #8)
3. 便签在 Gallery 显示 (#2)

**第二轮**（体验打磨）：
4. 编辑模式选框 + 控制手柄 (#5, #6)
5. 贴纸模式工具栏 (#3)
6. 便签双击编辑 (#7)

**第三轮**（功能补全）：
7. 复制/粘贴 (#9)
8. 导出 PNG (#10)
9. 锁定 (#11)
10. 描边预览 (#12, #13)

**第四轮**（iOS）：
11. #14, #15, #16

---

## 复盘（2026-04-13）

### 已完成

| # | 项目 | 状态 | commit |
|---|------|------|--------|
| — | 数据层：StickerAsset + PlacedSticker 模型 | ✅ | 62b149b |
| — | 抠图引擎：SubjectLifter (Apple Vision) | ✅ | 62b149b |
| — | 描边引擎：8 种样式（4 种实渲染，4 种基础） | ✅ | 62b149b |
| — | 文件存储：StickerFileManager（PNG + 缩略图） | ✅ | 62b149b |
| — | 导入流程：选图 → 抠图 → 描边 → 保存 | ✅ | 62b149b |
| — | 右栏贴纸 Tab（日历/记忆/贴纸） | ✅ | 62b149b |
| — | Gallery 网格 + 飘入动画 + 搜索 | ✅ | 62b149b |
| — | 画布贴纸层（ScrollView 内 ZStack） | ✅ | 62b149b |
| — | 拖放：Gallery → 画布 (macOS onDrag/onDrop) | ✅ | 62b149b |
| — | 贴上动画（弹性 scale）+ 撕掉动画（翻转渐出） | ✅ | 62b149b |
| — | SearchService 贴纸搜索方法 | ✅ | 62b149b |
| — | ViewModel 共享修复 | ✅ | 40fe23a |
| — | 编辑模式：长按进入 + 完成按钮退出 + 防抖 | ✅ | 907ed78 |
| #1 | 选框 + 缩放手柄 + 旋转手柄（Figma 风格） | ✅ | 63bb2dc |
| — | 旋转改用 PS/Figma atan2 逻辑 | ✅ | d25aeab |
| — | 选框跟随旋转 + 紧贴内容尺寸 | ✅ | f445876 |
| — | 手柄热区扩大（等比缩放不需精确瞄角） | ✅ | 2381667 |
| — | 持久化：四处加 context.save() | ✅ | c827186 |
| #2 | 便签流程重做：新建→贴纸库→Gallery→拖放画布 | ✅ | 0675df2 |

### 已知问题（未修）

1. **选框尺寸回报不稳定** — GeometryReader task(id:) 有时没触发，选框可能比内容大。需要继续调试或换测量方式。
2. **描边效果实际偏淡** — 8pt 在高分屏上可能还是不够明显，需要实际导入图片测试调整。
3. **Gallery 缩略图刷新** — 修改描边后缩略图不更新（#13）。
4. **搜索 UI 未接入** — SearchService 方法写了但 SidebarView 没改（#7 的 UI 部分）。
5. **iOS 完全不可用** — 导入、拖放、手势全断（#14-16）。

### 代码质量注意

- StickerCanvasLayer.swift 越来越大（~240 行），包含 overlay 逻辑。后续可拆出 StickerSelectionOverlay 到独立文件。
- StickerView 的 onSizeChanged callback 链条复杂（View → ViewModel dictionary → Overlay 读取），不够可靠。考虑换成 Overlay 内部直接用 PreferenceKey 或在 StickerView 上用 anchorPreference。

---

## 下一步规划

### 近期（macOS 体验打磨）

**第一优先：右键菜单 (#4)**
贴纸右键菜单是最高频交互。最小可用版：
- 删除
- 置于最前 / 置于最后
- 修改描边（图片贴纸）

**第二优先：便签双击编辑 (#7)**
贴上去的便签改不了内容，用户体验断裂。

**第三优先：贴纸模式工具栏 (#3)**
编辑模式下底栏换成画布工具条，这是"无限画布感"的关键视觉。

### 中期

- 复制/粘贴 (#9)
- 锁定 (#11)
- 描边预览 (#12)
- 搜索 UI 集成

### 远期

- iOS 适配（#14-16）
- 选框尺寸精确测量
- 性能优化（大量贴纸场景）
- **AI 贴贴纸** — 小雾聊天时自动在旁边贴表情/便签。PlacedSticker 加 `placedBy: String`（"user"/"assistant"），AI 侧通过 tool call 或 post-processing 触发
- **贴纸物理效果** — 小丑牌质感：纸张弯曲、翘角、撕边、折痕、光泽反射（随鼠标/陀螺仪）。需要 Metal shader 或 SceneKit。远期
