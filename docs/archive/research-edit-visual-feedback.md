# Research: 编辑模式视觉反馈

## 目标

两个改进：
1. **选中动效** — 选中时平滑放大 + 提亮，取消选中回原样（替代/补充绿框）
2. **物理拖拽** — 从贴纸边缘拖动产生角动量（扭矩），模拟真实纸片行为

---

## 一、选中动效

### 现状

`StickerView.swift`:
- `.scaleEffect(sticker.scale * appearScale)` — 只有出场动画用 appearScale
- `.shadow(color: .black.opacity(0.08), radius: 2, x: 1, y: 2)` — 固定阴影
- `.rotation3DEffect(.degrees(1.5), ...)` — 固定微翘
- 没有任何根据 `isSelected` 改变的视觉效果

`StickerSelectionOverlay`（StickerCanvasLayer.swift L367-452）:
- 独立在贴纸之上绘制绿色虚线框 + 把手
- macOS 需要保留把手（鼠标操作需要），但边框可以去掉或弱化
- iOS 把手已经隐藏（纯视觉），只有边框和删除按钮

### 方案

在 `StickerView` 里根据 `isSelected` 状态加动画：

```swift
// 选中放大：1.05 倍
.scaleEffect(sticker.scale * appearScale * (isSelected ? 1.05 : 1.0))
// 选中提亮：增加亮度
.brightness(isSelected ? 0.05 : 0)
// 选中阴影加强
.shadow(color: .black.opacity(isSelected ? 0.15 : 0.08), radius: isSelected ? 6 : 2, x: 1, y: isSelected ? 4 : 2)
// 动画
.animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
```

选中框（StickerSelectionOverlay）保留但弱化：
- macOS：把手保留（鼠标操作需要），边框从实线改为极淡虚线
- iOS：边框去掉或改为极淡，只保留删除按钮和锁定图标

### 涉及文件
- `StickerView.swift` — 加 isSelected 动效
- `StickerCanvasLayer.swift` — StickerSelectionOverlay 弱化边框

---

## 二、物理拖拽（扭矩）

### 原理

真实物体被推时，如果推力不过质心，会产生旋转。这是**扭矩**（torque）：

```
τ = r × F
```

简化到 2D：
- r = 触摸点到贴纸中心的偏移向量
- F = 手指移动方向（translation）
- 扭矩 = r.x * F.y - r.y * F.x（叉积 z 分量）

角加速度 α = τ / I，其中 I 是转动惯量。对矩形：I ∝ (w² + h²) / 12。

实际实现不需要精确物理，只需要：
1. 拖拽时计算触摸点相对贴纸中心的偏移
2. 偏移越大（越靠边缘），拖拽时加的旋转越多
3. 用一个 torqueFactor 缩放，让效果微妙不夸张

### 现状

**iOS** (`StickerGestureOverlay.swift handlePan`):
- `.began` 阶段有 `gesture.location(in:)` — 知道触摸点
- `.changed` 阶段用 `gesture.translation(in:)` 做纯平移
- 贴纸中心是 `(sticker.positionX, sticker.positionY)`
- 但 overlay 坐标系和贴纸画布坐标系是对齐的（同一个 ZStack）

**macOS** (`StickerCanvasLayer.swift DragGesture`):
- SwiftUI DragGesture 的 `value.location` 是在 view 坐标系里的
- 不方便拿到触摸相对贴纸中心的偏移（因为 DragGesture 是加在已 .position() 的 view 上）

### 方案

每帧拖拽时：
```swift
// 触摸点相对贴纸中心的偏移
let offsetX = touchLocation.x - sticker.positionX
let offsetY = touchLocation.y - sticker.positionY

// 叉积（2D 扭矩）
let crossZ = offsetX * translation.y - offsetY * translation.x

// 归一化：除以贴纸半对角线长度的平方（I ∝ size²）
let size = stickerSizes[sticker.id] ?? CGSize(width: 80, height: 80)
let halfDiag = sqrt(pow(size.width * sticker.scale / 2, 2) + pow(size.height * sticker.scale / 2, 2))
let normalizedTorque = crossZ / max(halfDiag * halfDiag, 1)

// 应用（很小的系数，效果微妙）
let torqueFactor: Double = 15.0  // 需要实测调参
sticker.rotation += normalizedTorque * torqueFactor
```

如果触摸点在贴纸正中心（offset ≈ 0），叉积 ≈ 0，不产生旋转 — 完美。
如果从边角拖，偏移大，叉积大，产生旋转。方向也对：从右边往下拖 → 顺时针。

### 摩擦 + 惯性（松手后滑行）

真实纸片在桌面上：
- 拖动时，桌面摩擦力分布在整个接触面上。手指推力偏离中心 → 摩擦力合力产生净扭矩 → 旋转
- 松手后，纸片不会立刻停。有线性动量（滑行）和角动量（继续旋转），摩擦使两者衰减到零

实现方案：**记录最近几帧的速度，松手时用 spring 动画让贴纸"滑到停"**

```swift
// .ended 阶段
let velocity = gesture.velocity(in: gesture.view)  // UIPanGestureRecognizer 自带！

// 线性惯性：沿速度方向滑行一小段
let friction: CGFloat = 0.15  // 越大滑越远
let slideX = velocity.x * friction
let slideY = velocity.y * friction

// 角惯性：最后几帧累计的角速度继续衰减
// angularVelocity 从拖拽过程中每帧的 rotation 增量推算

withAnimation(.interpolatingSpring(stiffness: 120, damping: 15)) {
    sticker.positionX += slideX
    sticker.positionY += slideY
    sticker.rotation += angularVelocity * 0.3  // 继续转一小段
}
```

关键：`UIPanGestureRecognizer` 有 `.velocity(in:)` 方法，不需要自己算速度。macOS 的 SwiftUI `DragGesture` 有 `value.velocity`（iOS 17+/macOS 14+）。

角速度需要自己追踪：每帧记录 rotation 增量，松手时取最后一帧的值。

### 涉及文件

- `StickerGestureOverlay.swift` handlePan — iOS 拖拽加扭矩
- `StickerCanvasLayer.swift` DragGesture — macOS 拖拽加扭矩（需要额外存触摸起始偏移）
- `StickerViewModel.swift` — 可能需要存 dragTouchOffset

---

## 总结

| 改动 | 难度 | 文件 |
|------|------|------|
| 选中放大+提亮+阴影 | 简单 | StickerView.swift |
| 选中框弱化 | 简单 | StickerCanvasLayer.swift (StickerSelectionOverlay) |
| 物理拖拽扭矩 (iOS) | 中等 | StickerGestureOverlay.swift |
| 物理拖拽扭矩 (macOS) | 中等 | StickerCanvasLayer.swift |
