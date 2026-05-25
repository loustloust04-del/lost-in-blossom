# 贴纸手势系统复盘

## 目标

编辑模式下，选中贴纸后：
- 单指拖拽移位
- 双指捏合缩放（手指放画布任意位置）
- 双指旋转（手指放画布任意位置）
- 双指双击撤回
- 单击选中/取消选中
- 双击编辑便签

## 尝试过的方案 & 失败原因

### 1. SwiftUI 原生 MagnifyGesture + RotateGesture（最初版本）

```swift
.simultaneousGesture(
    MagnifyGesture().simultaneously(with: RotateGesture())
)
```

**问题**：SwiftUI 的 DragGesture 会抢走第一根手指，MagnifyGesture 永远凑不齐两指。成功率约 10%。这是 SwiftUI 手势系统的根本限制——DragGesture 在 `.began` 阶段就 claim 了第一个 touch，MagnifyGesture 等不到第二个。

**教训**：SwiftUI 手势不适合多手势共存的复杂场景。

### 2. Per-Sticker UIKit Overlay（StickerGestureOverlay，单贴纸级别）

把 UIKit 的 UIPanGestureRecognizer + UIPinchGestureRecognizer + UIRotationGestureRecognizer 放在选中贴纸上方的一个 UIViewRepresentable overlay 里。

**解决了**：DragGesture 不再抢触摸，pinch/rotate 能正常启动。

**新问题**：overlay 的尺寸 = 贴纸的视觉尺寸。双指必须精确落在贴纸上才能触发。如果贴纸小或手指位置稍偏（尤其是纵向放大，手指在贴纸上下方），overlay 的 hitTest 返回 nil，手势不触发。

**教训**：per-sticker overlay 面积太小，不适合双指手势。

### 3. Per-Sticker + Canvas-Level 双层 UIKit Overlay（拆分架构）

拆成两个 UIViewRepresentable：
- `StickerDragOverlay`（per-sticker）：单指 pan + 双击
- `StickerCanvasGestureOverlay`（画布级）：pinch + rotate + 双指双击

**致命问题**：两个 UIViewRepresentable 在 ZStack 里是**兄弟 UIView**。UIKit hit testing 只命中最上层的 UIView。画布 overlay 在上层，吃掉所有触摸；per-sticker overlay 在下层，永远收不到 touch。反过来放也不行——第一根手指命中 per-sticker，第二根命中 canvas，各拿一半触摸，pinch 凑不齐。

**教训**：SwiftUI ZStack 中多个 UIViewRepresentable 不能分层协作处理触摸。UIKit 的 touch delivery 是单路径的——一个 touch 只给一个 hit-tested view。

### 4. 单个画布级 UIKit Overlay（当前方案）

一个 UIViewRepresentable 覆盖整个画布，6 个 recognizer 全挂在同一个 UIView 上：
- UIPanGestureRecognizer（max 1 touch）
- UIPinchGestureRecognizer
- UIRotationGestureRecognizer
- UITapGestureRecognizer（单击）
- UITapGestureRecognizer（双击）
- UITapGestureRecognizer（2 fingers, 2 taps）

**解决了**：
- 双指放画布任意位置都能缩放/旋转
- 不存在多层 UIView 抢触摸的问题

**遇到的坑**：

#### 4a. StickerSelectionOverlay 挡触摸
选框有 `.zIndex(999)` 在最上层。虽然 iOS 上没有交互元素（把手、删除按钮都是 macOS only），但 SwiftUI 的 `Rectangle().stroke().frame()` 仍然有 hit area，拦截了所有落在选框范围内的触摸。
→ 修复：iOS 加 `.allowsHitTesting(false)`

#### 4b. shouldRecognizeSimultaneouslyWith 太严
只允许 pinch + rotate 互相同时。ScrollView 的 UIPanGestureRecognizer（即使 `.scrollDisabled(true)` + `isScrollEnabled = false`）仍然作为 gesture recognizer 存在。如果 ScrollView 的 pan 先 claim 了触摸，pinch 因为不允许同时识别而启动失败。
→ 修复：pinch/rotate 对所有手势都允许同时识别

#### 4c. shouldRecognizeSimultaneouslyWith 太松
pinch/rotate 和自己的 pan 同时识别，导致缩放时贴纸同时被拖拽移位（边缩放边乱跑）。
→ 修复：pan handler 内部加 `!vm.pinchStarted` 守卫，pinch 期间冻结拖拽

#### 4d. 当前残留问题——成功率约 50%
"凑合能用但弄一次失败一次"。可能的原因：

1. **ScrollView pan 仍然在抢触摸**：`.scrollDisabled` 和 `isScrollEnabled = false` 阻止了滚动行为，但 UIScrollView 内部的 UIPanGestureRecognizer 可能仍然在 claim touch。即使我们的 delegate 允许同时识别，ScrollView 的 pan 可能在调用自己的 delegate 时拒绝同时——UIKit 只需要**一侧**同意就允许同时，所以这个方向应该没问题。但 ScrollView 的 pan 可能还有 `delaysTouchesBegan` 或其他配置影响 touch delivery timing。

2. **UIKit touch delivery 时序**：第一根手指落下时，多个 recognizer 进入 `.possible` 状态。UIKit 需要等待判断这是单指还是双指操作。如果 pan recognizer 的识别速度快于 pinch（pan 只需要很小的移动量），pan 可能在 pinch 之前进入 `.began`，然后 pinch 被取消。

3. **SwiftUI 残留手势干扰**：stickerItem 上还挂着 `.onLongPressGesture` 和 `.onTapGesture`。虽然画布 overlay 在上层应该挡住它们，但 SwiftUI 的手势系统可能有内部路径绕过 UIKit 的 hit testing 层级。

4. **TabView 的手势干扰**：ContentView 的 TabView 即使 `.scrollDisabled` 也可能有底层 UICollectionView/UIScrollView 的手势在竞争。

## 可能的进一步优化方向

### A. 彻底杀死 ScrollView/TabView 的手势 recognizer

不是设 `isScrollEnabled = false`（认识器还在），而是直接 `recognizer.isEnabled = false`：

```swift
for scrollView in allScrollViews {
    for recognizer in scrollView.gestureRecognizers ?? [] {
        if recognizer is UIPanGestureRecognizer {
            recognizer.isEnabled = !editing
        }
    }
}
```

### B. 用 `require(toFail:)` 建立识别器优先级

让 ScrollView 的 pan 和我们的 tap **require failure of** 我们的 pinch/rotate：

```swift
scrollViewPan.require(toFail: ourPinch)
scrollViewPan.require(toFail: ourRotate)
```

这样双指操作时，ScrollView 的 pan 会等 pinch 结果出来再决定。需要拿到 ScrollView 的 recognizer 引用。

### C. 把 recognizer 加到 UIWindow 上

Window-level recognizer 看到所有触摸且不参与 hit testing 竞争。缺点是生命周期管理复杂（进出编辑模式要 add/remove）。

### D. 完全接管编辑模式的触摸

编辑模式下，在 UIKit 层面插入一个全屏透明 UIView（不是 SwiftUI overlay，而是直接加到 window 的 subview），所有手势挂在上面。彻底绕过 SwiftUI 的手势系统。退出编辑模式时移除。

### E. 放弃画布级双指，回到加大 per-sticker overlay

给 per-sticker overlay 加大 padding（比如 150pt），让 hit area 远大于贴纸视觉区域。不能保证"手指放哪都行"，但对大部分场景够用，且架构最简单。

## 关键认知

| 认知 | 详情 |
|------|------|
| SwiftUI DragGesture 是贪婪的 | 它在第一个 touch 就 claim，后续的 MagnifyGesture 拿不到第二个 touch |
| ZStack 中的兄弟 UIView 不能协作 | UIKit hit testing 是单路径的，一个 touch 只给一个 view |
| `.scrollDisabled` 不够可靠 | 需要走 UIKit hierarchy 设 `isScrollEnabled = false`，甚至可能要 `recognizer.isEnabled = false` |
| `.zIndex()` 影响 hit testing | 高 zIndex 的纯视觉 view 也会拦截触摸，必须显式关掉 `.allowsHitTesting(false)` |
| delegate 是单向放行 | `shouldRecognizeSimultaneouslyWith` 只要一方返回 true 就允许同时，设太严会被外部 recognizer 卡住 |
| SwiftUI + UIKit 手势共存很脆弱 | SwiftUI 的 `.onTapGesture` / `.onLongPressGesture` 在底层也是 UIKit recognizer，可能和 UIViewRepresentable 的 recognizer 冲突 |
