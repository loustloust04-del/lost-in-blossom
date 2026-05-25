# Research: tab 栏横滑与 TabView 翻页的手势冲突

> 日期：2026-04-18
> 问题：iOS 版 SidebarView 顶部 tab 栏（横向 ScrollView）横滑时，一旦滚到边界，剩余手势会"漏"给外层 TabView(.page)，触发左右翻页。
> 目标：手指落在 tab 栏上时，横滑只滚 tab 栏，即使滚到底也不翻页；其他区域正常翻页。

## 当前架构

```
ContentView.iOSLayout
└── TabView(.page) [$iOSPage]                 ← 底层 UICollectionView，横向翻页
    ├── iOSListPage → SidebarView             ← page 0
    │   └── sidebarTabBar
    │       └── HStack
    │           ├── tabButton(全部)            ← 锁定不滚
    │           └── ScrollView(.horizontal)   ← 横滑滚 tab（冲突源头）
    │               └── HStack
    │                   ├── HStack { tabs }.scrollTargetLayout()
    │                   └── plusButton
    ├── iOSChatPage                            ← page 1
    └── iOSDashboardPage                       ← page 2
```

**关键事实：**
- `TabView(.page)` 底层是 **UICollectionView**（已在 `disableTabViewBounce()` 证实）
- UICollectionView 的 `panGestureRecognizer` 作用于整个 TabView 的 hit 区域
- SwiftUI `ScrollView(.horizontal)` 和 UICollectionView 的 pan 是**两套独立**手势识别器
- UIKit 的默认行为：当内层 ScrollView 滚到边界，外层同向滚动接管（典型 bouncing 转嫁）

## 现有尝试及其失效原因

| 尝试 | 代码 | 为什么不起作用 |
|---|---|---|
| SwiftUI `.simultaneousGesture(DragGesture)` | SidebarView.swift:837 | 是 SwiftUI 层的 gesture，和 UIKit 底层 UIPanGestureRecognizer 不在同一识别器树里，拦不住 |
| `.scrollBounceBehavior(.basedOnSize)` | SidebarView.swift:834 | 只禁 SwiftUI ScrollView 自己的回弹，不影响外层 TabView collectionView |
| `.scrollTargetBehavior(.viewAligned(limitBehavior: .always))` | SidebarView.swift:833 | 控制 snap 对齐，不改手势传递 |

结论：**SwiftUI 层拦不住 UIKit 层的 pan**。必须下沉到 UIKit。

## 可行方案对比

### 方案 A：劫持 UICollectionView.panGestureRecognizer 的 delegate（推荐）

**原理：** 找到 TabView 底层 UICollectionView，给它的 `panGestureRecognizer` 挂一个 `UIGestureRecognizerDelegate`，在 `gestureRecognizer(_:shouldReceive touch:)` 里判断 touch 是否落在 tab 栏区域，落在就 return false。

**落点判断的两种做法：**
- **view-tag 链查找**：给 tab 栏外层套一个 `UIViewRepresentable` 的 UIView，tag 设成约定常量（如 `918273`）。delegate 里沿着 `touch.view` 的 superview chain 找，找到 tag 匹配的就 return false。**跟着 view 走，不用算 frame，最稳。**
- **frame 判断**：tab 栏用 GeometryReader+PreferenceKey 把 global frame 导出来传给外层 delegate。delegate 里比较 `touch.location(in: window) ∈ frame`。frame 需要同步更新，稍麻烦。

view-tag 方案更优。

**优点：** 干净彻底，只在 touch 落在 tab 栏时屏蔽 TabView pan，其他区域不受影响。
**缺点：** 需要 walk view hierarchy 拿 UICollectionView（已有熟路），需要 delegate 对象持久持有。

### 方案 B：在 tab 栏 UIViewRepresentable 的 touchesBegan/Ended 里切 TabView pan 的 isEnabled

**原理：** tab 栏套 UIView，它的 `touchesBegan` 里 `collectionView.panGestureRecognizer.isEnabled = false`，`touchesEnded/Cancelled` 里恢复。

**缺点：** 状态管理脆弱（多指、中断、异常路径容易卡住）；且 disable 的瞬间若 pan 已 activate 会有副作用。不推荐。

### 方案 C：用 UIScrollView (UIViewRepresentable) 替代 SwiftUI ScrollView，调用 `panGestureRecognizer.require(toFail:)` 互锁

**原理：** 用 UIKit ScrollView 自己跑 tab 栏，拿到自己的 pan，叫 TabView 的 collectionView.pan `require(toFail:)`。这样只有 tab scrollview 认定"不是我的 pan"才给外层翻页。

**缺点：** 要把 SwiftUI 那一坨 scrollTargetLayout/scrollPosition/viewAligned 全部手写回去，工程量很大；且 `require(toFail:)` 反向挂钩（collection 的 pan 要等 tab 的 pan fail）会明显拖慢外层翻页启动。不推荐。

## 推荐方案：A + view-tag

最小改动：
1. 新增 `TabBarGestureBlocker` — `UIViewRepresentable` 返回一个 tag 固定的透明 UIView，套在 tab 栏 ScrollView 的 `.background` 或 `.overlay`。
2. 在 `ContentView.disableTabViewBounce()`（walk view hierarchy 的老路径）里拿到 `UICollectionView`，顺便给它的 `panGestureRecognizer` 挂上一个持久 delegate（以 `objc_setAssociatedObject` 保活）。
3. delegate 的 `gestureRecognizer(_:shouldReceive touch:)`：沿 `touch.view` 的 superview chain 找 tag == `918273`，找到就 return false。

这样 tab 栏上的手指摸到哪里都触发不了 TabView 翻页，其他区域的 pan 不受任何影响。

## 风险与边界

- **多指/快速滑过**：shouldReceive 在每个 touch-begin 时判定一次，足够早，没有竞态。
- **tab 栏换主题色/重新 layout**：tag view 跟着 SwiftUI view tree 变，不影响 tag 查找。
- **原本就有的 UICollectionView delegate**：TabView 底层用的是 SwiftUI 内部 collection，它的 panGestureRecognizer 默认没有挂外部 delegate，我们挂上不会冲突。如果未来 SwiftUI 版本改动，我们的 delegate 仍然会被尊重（pan recognizer 只支持一个 delegate，最后设置的生效）。
- **保活**：delegate 作为 AssociatedObject 绑在 collectionView 上，跟它同生命周期，不会泄漏不会提前释放。

## 文件改动预估

| 文件 | 改动 |
|---|---|
| `Views/iOSTabBarGestureBlocker.swift` (新) | UIViewRepresentable + tag 常量 |
| `Views/ContentView.swift` | `disableBounceInSubviews` 里多一步：给 collectionView.panGestureRecognizer 挂 delegate（新类 `TabBarPanBlockerDelegate`） |
| `Views/SidebarView.swift` | tab 栏 ScrollView 外 `.background(TabBarGestureBlocker())` |

## 不做

- 不改 TabView 的实现（不换 UIPageViewController、不手写 collection）
- 不处理 tab 栏垂直滑动（垂直时仍想让聊天页的纵向滚动生效，这个已经正常）
