# Research: 精确 nearestMessageId 计算

## 问题

`findNearestMessageId(y:)` 用粗估算（每行 102pt）算贴纸附近的消息。消息实际高度差异极大（短消息 40pt，长消息 500pt+），导致：
1. 贴纸搜索跳转到错误的消息
2. nearestMessageId 关联不准确

## 现状

```swift
// 估算：每个消息 ≈ 80pt 高 + 22pt 间距 + 20pt 顶部 padding
let estimatedRowHeight: CGFloat = 102
let index = max(0, Int((y - topPadding) / estimatedRowHeight))
```

完全是瞎猜。一个 3 行的消息和一个 50 行的消息被当做一样高。

## 正确方案：用 GeometryReader 测量每个 BubbleView 的实际 Y 坐标

### 思路

在 CardFlowView 的 LazyVStack 里，每个 BubbleView 用 GeometryReader 记录它在 ScrollView content 坐标系里的 Y 位置（中点）。存一个 `[String: CGFloat]` 字典：`nodeId → centerY`。

放置贴纸时，拿贴纸的 Y 坐标，在字典里找距离最近的 nodeId。

### 问题

LazyVStack 是懒加载的——屏幕外的消息不会渲染，GeometryReader 拿不到它们的位置。

但这其实没关系：
- 贴纸只能贴在**当前可见区域附近**（拖放的落点一定在视口内）
- 所以只需要**已渲染的**消息的位置
- 搜索跳转时，先跳到对话、滚动到 nearestMessageId，LazyVStack 自然会渲染那附近的消息

### 实现

1. CardFlowView 加 `@State private var bubblePositions: [String: CGFloat] = [:]`
2. 每个 BubbleView 包一层 background GeometryReader，读取 Y 坐标（相对于 ScrollView content），写入字典
3. `findNearestMessageId(y:)` 改为遍历字典找最近的
4. 需要一个 named coordinateSpace 在 ScrollView content 上

### 坐标空间

```swift
ScrollView {
    ZStack(alignment: .topLeading) {
        LazyVStack(spacing: 22) {
            ForEach(viewModel.currentPath) { node in
                makeBubbleView(for: node)
                    .id(node.id)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: BubblePositionKey.self,
                                value: [node.id: geo.frame(in: .named("scrollContent")).midY]
                            )
                        }
                    )
            }
        }
        ...
    }
    .coordinateSpace(name: "scrollContent")
}
.onPreferenceChange(BubblePositionKey.self) { positions in
    bubblePositions.merge(positions) { _, new in new }
}
```

PreferenceKey 需要用 `[String: CGFloat]` 类型，merge 所有子 view 的值。

### 注意

- PreferenceKey reduce 需要合并字典（不是覆盖）
- LazyVStack 回收 view 时，旧位置可能过期——但只要当前可见的是对的就行
- 性能：每个 BubbleView 加一个 GeometryReader background，开销很小
