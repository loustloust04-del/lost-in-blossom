# 任务：修复侧边栏手势 — UIKit 边缘手势替代 SwiftUI DragGesture

## 问题

当前侧边栏的"右滑打开"手势用 SwiftUI `.gesture(DragGesture(...))` 实现，但 PagingContainerView 内部的 UIScrollView.panGestureRecognizer 优先级更高，把左边缘的右滑手势吃掉了。结果：按钮能打开侧边栏，手势不能。

## 修复方案

在 UIKit 层（PagingViewController）添加 UIScreenEdgePanGestureRecognizer，让它优先级高于 scrollView 的 panGestureRecognizer。通过 closure 回调把手势状态传给 SwiftUI 层。

### 1. PagingViewController — 添加边缘手势

```swift
// ── 新增属性 ──
var onEdgePanChanged: ((CGFloat) -> Void)?
var onEdgePanEnded: ((CGFloat, CGFloat) -> Void)?  // (translation.x, velocity.x)

// ── viewDidLoad() 末尾添加 ──
let edgePan = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleLeftEdgePan(_:)))
edgePan.edges = .left
view.addGestureRecognizer(edgePan)
// 关键：让 scrollView 的 pan 手势等待边缘手势失败后才识别
scrollView.panGestureRecognizer.require(toFail: edgePan)

// ── 新增方法 ──
@objc private func handleLeftEdgePan(_ gesture: UIScreenEdgePanGestureRecognizer) {
    let tx = gesture.translation(in: view).x
    switch gesture.state {
    case .changed:
        onEdgePanChanged?(max(0, tx))
    case .ended, .cancelled:
        let vx = gesture.velocity(in: view).x
        onEdgePanEnded?(tx, vx)
    default:
        break
    }
}
```

### 2. PagingContainerView — 暴露回调

在 struct 里添加两个新属性：

```swift
var onEdgePanChanged: ((CGFloat) -> Void)?
var onEdgePanEnded: ((CGFloat, CGFloat) -> Void)?
```

在 `makeUIViewController` 里赋值：
```swift
vc.onEdgePanChanged = onEdgePanChanged
vc.onEdgePanEnded = onEdgePanEnded
```

在 `updateUIViewController` 里也赋值（保持同步）：
```swift
vc.onEdgePanChanged = onEdgePanChanged
vc.onEdgePanEnded = onEdgePanEnded
```

### 3. ContentView — 接收 UIKit 手势，替代 SwiftUI 手势

#### 3a. 新增 @State 替代 @GestureState

```swift
// 删除这行：
// @GestureState private var sidebarLiveDrag: CGFloat = 0

// 替换为：
@State private var sidebarEdgeDrag: CGFloat = 0
```

#### 3b. 更新 chatOffset 计算

把原来引用 `sidebarLiveDrag` 的地方改为 `sidebarEdgeDrag`：

```swift
let chatOffset = max(0, min(fullSlide, targetOffset + sidebarEdgeDrag))
```

#### 3c. PagingContainerView 调用处添加回调

```swift
PagingContainerView(
    chatPage: AnyView(injectPagingEnv(iOSChatPage)),
    dashPage: AnyView(injectPagingEnv(iOSDashboardPage)),
    currentPage: $iOSPage,
    disableScroll: stickerVM.isEditingStickers,
    initialPage: 0,
    wallpaper: wallpaperConfig,
    isStreaming: viewModel.providerRouter.isStreaming,
    onEdgePanChanged: { tx in
        sidebarEdgeDrag = tx
    },
    onEdgePanEnded: { tx, vx in
        let geo = UIScreen.main.bounds
        let sidebarW = geo.width * 0.8
        let shouldOpen = tx > sidebarW * 0.3 || vx > 500
        withAnimation(sidebarAnimation) {
            isSidebarOpen = shouldOpen
        }
        // 归零 drag（带动画或不带都行，isSidebarOpen 会接管 targetOffset）
        sidebarEdgeDrag = 0
    }
)
```

#### 3d. 简化 .gesture 修饰符

原来的 `.gesture(DragGesture(...))` 里有两段逻辑：
- `!isSidebarOpen`（打开手势）→ **删除这段**，已由 UIKit edge pan 处理
- `isSidebarOpen`（关闭手势）→ **保留这段**，因为侧边栏打开时 PagingContainerView 的 `allowsHitTesting` 为 false，SwiftUI 手势不会被 UIScrollView 吃掉

改为只处理关闭：

```swift
.gesture(
    DragGesture(minimumDistance: 8, coordinateSpace: .local)
        .updating($closeDrag) { value, state, _ in
            guard isSidebarOpen else { return }
            state = min(0, value.translation.width)
        }
        .onEnded { value in
            guard isSidebarOpen else { return }
            let sidebarW = geo.size.width * 0.8
            let shouldClose = value.translation.width < -(sidebarW * 0.3)
                || value.velocity.width < -500
            if shouldClose {
                withAnimation(sidebarAnimation) { isSidebarOpen = false }
            }
        }
)
```

注意：关闭手势仍然需要一个 @GestureState 来做实时跟手。新增：

```swift
@GestureState private var closeDrag: CGFloat = 0
```

chatOffset 计算改为：

```swift
let chatOffset = max(0, min(fullSlide, targetOffset + sidebarEdgeDrag + closeDrag))
```

### 4. 清理

- 删除所有引用旧 `sidebarLiveDrag` 的代码
- 确认 `import UIKit` 存在于 PagingViewController.swift（应该已有）

## 测试

1. 从左边缘右滑 → 侧边栏跟手滑出，松手后弹开或回弹
2. 侧边栏打开后，在聊天遮罩区左滑 → 侧边栏关闭
3. 侧边栏打开后，点击遮罩 → 侧边栏关闭
4. 点左上角按钮 → 侧边栏打开（不受影响）
5. 聊天页左右滑切换到 dashboard → 正常工作（不受 edge pan 影响）

一个 commit：`fix(sidebar): replace SwiftUI DragGesture with UIKit edge pan to fix gesture conflict with UIScrollView`

