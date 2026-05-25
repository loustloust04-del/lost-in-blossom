# Research: 贴纸系统 (Sticker System)

> 基于 `feature/merge-import` 分支（45af8c0），包含记忆面板、AUDN、预设系统、ChatService、SearchService 等全部最新功能。

---

## 1. 现有架构

### 1.1 对话视图 (CardFlowView)

**文件**: `Views/CardFlowView.swift`

结构：VStack → InConversationSearchBar（可选）→ ScrollViewReader → ScrollView → LazyVStack

```swift
VStack(spacing: 0) {
    if showInConvSearch { InConversationSearchBar(...) }
    
    ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(spacing: 22) {
                ForEach(viewModel.currentPath) { node in
                    makeBubbleView(for: node).id(node.id)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
    }
    
    ChatInputBar(...)  // 底部输入栏
}
```

关键：
- macOS 内容最大宽 720pt，iOS 满宽 padding 16
- ChatInputBar 在底部（发消息 + 模型选择器）
- 已有 Cmd+F 对话内搜索
- BubbleView 有 contextMenu（复制/收藏/删除），hover 按钮独立状态

**贴纸层插入点**: ScrollView 内部，用 ZStack 叠加在 LazyVStack 之上。贴纸随内容滚动。

### 1.2 右栏 Tab 系统（已有！）

**文件**: `Views/MemoryPanelView.swift`

```swift
enum RightPanelTab {
    case calendar, memory    // ← 加 .sticker 即可
}

struct RightPanelView: View {
    @Binding var selectedTab: RightPanelTab
    var viewModel: ConversationViewModel
    
    var panelContent: some View {
        switch selectedTab {
        case .calendar: CalendarPanelView(...)
        case .memory: MemoryPanelView(...)
        // case .sticker: StickerLibraryView(...)  ← 新增
        }
    }
}
```

Tab 按钮样式：Capsule 背景 + 薄荷绿高亮，已有 macOS/iOS 自适应。
ContentView 里 normalLayout 和 fullscreenLayout 两处都引用了 RightPanelView，只改一处（RightPanelView 内部）。

面板尺寸：最小 250pt，默认 300pt，最大 380pt。

### 1.3 数据模型

**文件**: `Models/Conversation.swift`

现有 UserCard 模型：
```swift
@Model final class UserCard {
    var id: UUID; var content: String; var imageData: Data?
    var attachedToNodeId: String?
    var positionX: Double; var positionY: Double
    var createTime: Date
}
```
简陋，没有 rotation/scale/zIndex/conversationId/borderStyle。UI 层没有使用过。**可以安全弃用，新模型替代。**

Schema 注册在 `ProfileManager.makeContainer()`，共 9 个模型。

### 1.4 SearchService（独立服务）

**文件**: `Services/SearchService.swift`

`enum SearchService` 纯静态方法，后台线程执行：
- `performSearch(filter:container:) async -> [SearchResult]`
- 按关键词搜消息内容 + 对话标题
- 支持日期范围、角色过滤、排序
- 返回 `SearchResult`（含 `[MatchedNode]`）

扩展点：加一个 `searchStickers(keyword:tags:container:)` 方法，返回匹配的贴纸。

### 1.5 文件存储路径

```
~/Library/Application Support/MemoryPalace/
├── ghost-lily.store          // 默认楼层数据库
├── third-floor-left.store    // 其他楼层
└── stickers/                 // 新增：贴纸文件存储
    └── {profileId}/
        ├── {id}.png          // 抠图+描边后的贴纸
        ├── {id}_thumb.png    // 缩略图（gallery 用）
        └── {id}_original.png // 原图（可选）
```

---

## 2. Apple Vision 抠图 API

**VNGenerateForegroundInstanceMaskRequest** — macOS 14.0+ 可用，正好是 deployment target。

```swift
// 核心流程（必须后台线程）
let request = VNGenerateForegroundInstanceMaskRequest()
let handler = VNImageRequestHandler(ciImage: ciInput, options: [:])
try handler.perform([request])

guard let observation = request.results?.first else { return nil }
let maskBuffer = try observation.generateScaledMaskForImage(
    forInstances: observation.allInstances, from: handler
)

// CoreImage 合成透明背景
let filter = CIFilter.blendWithMask()
filter.inputImage = ciInput
filter.maskImage = CIImage(cvPixelBuffer: maskBuffer)
filter.backgroundImage = CIImage.empty()
// → 渲染为 PNG
```

限制：必须后台线程、Apple Silicon 最佳、软遮罩边缘、不能模拟器测试、大图注意内存。

---

## 3. 粟粟确认的设计决策

| 问题 | 决策 |
|------|------|
| 右栏切换 | 在已有 tab（日历/记忆）旁加"贴纸"tab |
| 放置方式 | **拖拽**。学 Telegram：贴纸面板 → 拖到画布。便签弹小卡片打字 |
| 编辑模式 | **长按**进入编辑（拖动/缩放/旋转），不是随时可操作 |
| 描边流程 | 多张**一步到位**（自动抠图+默认描边），之后可改描边样式 |
| 便签体验 | **都要** — 极简弹窗 + 手写字体/颜色笔选择 |
| 消息关联 | **自动计算**最近消息。搜索结果显示带旋转角度的缩略图 |
| UserCard | 弃用，新建模型 |

---

## 4. 关键技术方案

### 4.1 贴纸画布层

贴纸在 ScrollView 内部，和消息在同一 ZStack——"贴在纸上"自然滚动：

```swift
ScrollView {
    ZStack(alignment: .topLeading) {
        LazyVStack(spacing: 22) { /* 消息气泡 */ }
            .padding(...).frame(maxWidth: 720).frame(maxWidth: .infinity)
        
        // 贴纸层
        ForEach(placedStickers) { sticker in
            StickerView(sticker: sticker)
                .position(x: sticker.positionX, y: sticker.positionY)
                .zIndex(Double(sticker.zIndex))
        }
    }
}
```

- `.position()` 使用 ScrollView content 坐标系 → 未来无限画布直接沿用
- 贴纸默认 `allowsHitTesting(false)`，长按进入编辑模式后才可交互
- 需要 GeometryReader 测量 LazyVStack 高度来约束可放置范围

### 4.2 拖拽放置

从右栏 Gallery 拖到画布：
- macOS: `.onDrag { NSItemProvider(...) }` on gallery item → `.onDrop` on ScrollView
- 需要坐标转换：drop 的位置（视口坐标）→ ScrollView content 坐标

### 4.3 描边渲染

描边是一次性渲染后存为新 PNG，不是每帧实时计算：
1. 抠图得到透明 PNG
2. 对 alpha 通道做膨胀（CoreImage morphology dilate）得到描边区域
3. 描边区域填充样式（纯色/渐变/pattern）
4. 合成最终 PNG（描边 + 原图）
5. 存盘

预设样式：none / solid_white / solid_black / gradient_rainbow / laser / lace / glitter / neon

### 4.4 数据模型

```swift
// 贴纸库资产（模板）
@Model final class StickerAsset {
    @Attribute(.unique) var id: UUID
    var name: String
    var imagePath: String           // 相对路径
    var thumbnailPath: String
    var originalImagePath: String?
    var borderStyle: String         // "none", "solid_white", "laser", ...
    var borderWidth: Double
    var tags: [String]
    var createdAt: Date
    var profileId: String
}

// 画布上的贴纸实例
@Model final class PlacedSticker {
    @Attribute(.unique) var id: UUID
    var stickerAssetId: UUID?       // nil = 便签
    var conversationId: String
    var nearestMessageId: String?
    var positionX: Double
    var positionY: Double
    var rotation: Double            // 微歪角度
    var scale: Double
    var zIndex: Int
    var noteContent: String?        // nil = 图片贴纸
    var noteStyle: String?          // 便签样式
    var placedAt: Date
    var profileId: String
}
```

### 4.5 动画

| 动画 | 参数 |
|------|------|
| 贴上 | scale 1.0→0.93→1.04→1.0 + rotation ±2°, spring(0.35, 0.6) |
| 撕掉 | rotation3DEffect 沿左边缘 0→90° + opacity 1→0, easeIn 0.4s |
| 纸质感 | noise overlay opacity 0.03 + shadow(0.08, r:2, x:1, y:2) + 边角微翘 1.5° |
| Gallery 飘入 | 从随机位置+旋转 ±30° → 网格位置+微旋转 ±5°, spring, delay 0.03s/个 |

---

## 5. 文件变更预估

### 新增
| 文件 | 用途 |
|------|------|
| `Models/StickerAsset.swift` | 贴纸库资产模型 |
| `Models/PlacedSticker.swift` | 画布贴纸实例模型 |
| `Services/SubjectLifter.swift` | Apple Vision 抠图封装 |
| `Services/StickerBorderRenderer.swift` | 描边渲染引擎 |
| `Services/StickerFileManager.swift` | 贴纸文件存储管理 |
| `Views/StickerLibraryView.swift` | 右栏 Gallery 面板 |
| `Views/StickerCanvasLayer.swift` | 画布贴纸叠加层 |
| `Views/StickerView.swift` | 单个贴纸渲染（纸质感+动画） |
| `Views/NoteStickerEditor.swift` | 便签编辑浮窗 |
| `Views/StickerImportSheet.swift` | 导入流程（选图→抠图→描边→保存） |
| `ViewModels/StickerViewModel.swift` | 贴纸状态管理 |

### 修改
| 文件 | 改动 |
|------|------|
| `MemoryPalaceApp.swift` | Schema 加 StickerAsset + PlacedSticker |
| `MemoryPanelView.swift` | RightPanelTab 加 .sticker，tab 按钮 +1 |
| `CardFlowView.swift` | ScrollView 内加 ZStack + StickerCanvasLayer |
| `SearchService.swift` | 加贴纸搜索方法 |
| `SidebarView.swift` | 搜索结果旁显示贴纸缩略图 + 图层筛选 |
