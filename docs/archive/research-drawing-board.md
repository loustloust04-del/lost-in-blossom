# Research: 画画便签（磁性画板）

## 技术方案

**PencilKit 不可用** — `PKCanvasView` 是 iOS only，macOS 原生不支持。

**用 SwiftUI Canvas + DragGesture** — 纯 SwiftUI，macOS 12+ 可用。

### 核心数据结构
```swift
struct Line {
    var points: [CGPoint]
    var color: Color
    var lineWidth: CGFloat
    var isEraser: Bool
}
```

### 画笔实现
- `DragGesture(minimumDistance: 0)` 捕获每个移动点
- `Canvas` view 遍历所有 Line，用 `Path` + `context.stroke()` 渲染
- 橡皮擦 = 白色/透明笔（compositingGroup + .clear blendMode）
- 平滑曲线：相邻点取中点做二次贝塞尔插值

### 导出透明 PNG
- `ImageRenderer`（macOS 13+）渲染 Canvas 为 CGImage
- Canvas 默认透明背景，ImageRenderer 保留 alpha
- 导出后存为 StickerAsset（assetType: "image"）

## 交互设计：磁性画板感

- 画板背景：浅灰绿色（模拟磁性画板的那种淡绿灰）
- 画出来的线条：深灰色（像磁粉的颜色）
- "清除"按钮 = 摇一摇/滑动条动画（模拟拉杆清除）
- 可选彩色模式：红/蓝/绿/黄几种颜色笔

## 和贴纸系统的集成

画完 → 导出透明 PNG → 自动抠图（不需要，已经是透明的）→ 可选描边 → 存为 StickerAsset → 出现在 Gallery。

工具栏"画画"按钮 → 弹出 DrawingBoardSheet → 画完点"保存为贴纸" → 入库。
