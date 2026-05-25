# Plan: 编辑模式视觉反馈

## 改动

### 1. 选中动效（StickerView.swift）

选中时平滑放大 + 提亮 + 阴影加深，取消选中恢复：
```swift
.scaleEffect(sticker.scale * appearScale * (isSelected ? 1.05 : 1.0))
.brightness(isSelected ? 0.05 : 0)
.shadow(... isSelected ? 加深 : 默认)
.animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
```

### 2. 选中框弱化（StickerCanvasLayer.swift StickerSelectionOverlay）

- 边框从实线改为极淡虚线（或直接去掉，只在 macOS 保留把手）
- iOS：完全去掉边框线条，只保留删除按钮和锁定图标

### 3. 物理拖拽 — iOS（StickerGestureOverlay.swift handlePan）

`.began`：记录触摸点相对贴纸中心的偏移 `dragOffset`
`.changed`：除了平移，还加扭矩旋转
```swift
let crossZ = dragOffset.x * translation.y - dragOffset.y * translation.x
let halfDiag = sqrt(w*w + h*h) / 2
sticker.rotation += (crossZ / (halfDiag * halfDiag)) * torqueFactor
```
同时追踪 `lastRotationDelta`（角速度）

`.ended`：用 gesture.velocity + 角速度做惯性滑行
```swift
withAnimation(.interpolatingSpring(stiffness: 120, damping: 15)) {
    sticker.positionX += velocity.x * frictionFactor
    sticker.positionY += velocity.y * frictionFactor
    sticker.rotation += lastRotationDelta * angularInertia
}
```

### 4. 物理拖拽 — macOS（StickerCanvasLayer.swift DragGesture）

同样逻辑，但用 SwiftUI DragGesture 的 `value.startLocation` 算偏移，`value.velocity` 算惯性。

### 5. ViewModel 辅助属性（StickerViewModel.swift）

```swift
@ObservationIgnored var dragTouchOffset: CGPoint = .zero  // 触摸点相对贴纸中心偏移
@ObservationIgnored var lastRotationDelta: Double = 0      // 角速度追踪
```

## 文件清单

| 文件 | 改动 |
|------|------|
| `Views/StickerView.swift` | isSelected 动效（scale/brightness/shadow） |
| `Views/StickerCanvasLayer.swift` | 选中框弱化 + macOS 物理拖拽 |
| `Views/StickerGestureOverlay.swift` | iOS 物理拖拽 |
| `ViewModels/StickerViewModel.swift` | +dragTouchOffset, +lastRotationDelta |

## Checklist

- [x] **1.** StickerView 选中动效
- [x] **2.** StickerSelectionOverlay 弱化边框
- [x] **3.** StickerViewModel 加辅助属性
- [x] **4.** iOS 物理拖拽（扭矩 + 惯性）
- [x] **5.** macOS 物理拖拽（扭矩 + 惯性）
- [x] **6.** Build 验证
