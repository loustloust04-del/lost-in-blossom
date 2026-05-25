# Plan: 解决 tab 栏与 TabView 翻页手势冲突（方案 A）

> ⚠️ **SUPERSEDED (2026-04-18)** — 这份计划的「view-tag 查链 + UICollectionView.panGestureRecognizer delegate 劫持」**没有落地**。
>
> 实际采用的方案是：`UIViewControllerRepresentable` + `UIHostingController` 让 UIView 真正成为 SwiftUI 内容的 superview，在上面挂 `UIPanGestureRecognizer`，UICollectionView 的 pan `require(toFail: blockerPan)`。
>
> 代码：`MemoryPalace/Views/iOSTabBarGestureBlocker.swift`（顶部注释解释了为什么 `.background/.overlay` 方案走不通）
> 复盘：`docs/postmortem-sidebar-polish-2026-04.md`（错 2）
>
> 下面的内容保留作为走过的岔路参考，不要照着实现。

---

> 前置：`research-tab-gesture-conflict.md`
> 日期：2026-04-18
> 方案：view-tag 查链 + UICollectionView.panGestureRecognizer delegate 劫持

## 设计概览

```
touch begins on tab 栏
  ↓
UICollectionView.panGestureRecognizer 收到 shouldReceive(touch)
  ↓
delegate 沿 touch.view 的 superview chain 找 tag == 918273
  ↓
找到 → return false（TabView pan 不激活）
找不到 → return true（翻页照常）
```

**关键不变量：**
- tab 栏外挂一个 `UIView(tag=918273)` 作为 marker
- 这个 marker 的 superview 链包含 tab 栏所有子孙 view
- delegate 被 AssociatedObject 绑在 collectionView 上，防止被释放

## Task Checklist

### T1：新建 `TabBarGestureBlocker` UIViewRepresentable

- [ ] 新建 `MemoryPalace/Views/iOSTabBarGestureBlocker.swift`（仅 iOS）
- [ ] `#if os(iOS)` 包住整个文件
- [ ] `enum TabBarMarker { static let tag = 918273 }` —— 导出常量
- [ ] `struct TabBarGestureBlocker: UIViewRepresentable` 返回 `UIView()`，`tag = TabBarMarker.tag`，`isUserInteractionEnabled = false`（不要拦住自己的点击/tap），`backgroundColor = .clear`
- [ ] `updateUIView(_:context:)` 空实现

### T2：实现 `TabBarPanBlockerDelegate`

- [ ] 同文件内新加 `final class TabBarPanBlockerDelegate: NSObject, UIGestureRecognizerDelegate`
- [ ] 实现 `gestureRecognizer(_:shouldReceive touch:) -> Bool`：
  - 拿 `touch.view`
  - 沿 `.superview` 链向上遍历，如果碰到 `tag == TabBarMarker.tag` 的 view → `return false`
  - 走到 nil 还没找到 → `return true`
- [ ] 实现 `gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:) -> Bool`：`return true`（不影响别的手势）

### T3：ContentView 里把 delegate 挂到 UICollectionView.panGestureRecognizer

- [ ] `ContentView.swift` 的 `disableBounceInSubviews(of:)` 里，拿到 `collectionView` 的那一支，多加：
  ```swift
  let delegate = TabBarPanBlockerDelegate()
  collectionView.panGestureRecognizer.delegate = delegate
  // 用 AssociatedObject 保活
  objc_setAssociatedObject(collectionView, &tabBarPanDelegateKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
  ```
- [ ] 文件顶部加 `private var tabBarPanDelegateKey: UInt8 = 0`
- [ ] import `ObjectiveC`（如果不在）

### T4：SidebarView 挂 TabBarGestureBlocker

- [ ] `sidebarTabBar` 有自定义 tag 那个分支：ScrollView 外（ScrollViewReader 包围前后都可以，但要包住 ScrollView 本身）加 `.background(TabBarGestureBlocker())`
- [ ] `#if os(iOS)` 包住，macOS 不需要
- [ ] 考虑：要不要连 tab 栏的「全部」锁定 tab 也包进去？——包。用户手指在「全部」上横滑也不应翻页。即：整个 `sidebarTabBar` 外层 HStack 都 `.background(TabBarGestureBlocker())`

### T5：删除失效的 `.simultaneousGesture`

- [ ] 删掉 SidebarView.swift:837-840 的 `.simultaneousGesture(DragGesture(minimumDistance: 0))` —— 已经被方案 A 取代，留着没用且会误导后人

### T6：build + 手测 + commit + push

- [ ] macOS build 通过（保证 `#if os(iOS)` 包得对，没泄漏 UIKit 到 macOS）
- [ ] iOS build 通过
- [ ] 手测：
  - 手指在 tab 栏上横滑：只滚 tab，不翻页 ✅
  - 手指在 tab 栏上滚到最左/最右：不翻页 ✅
  - 手指在聊天页/列表页正文区域横滑：照常翻页 ✅
  - 手指在「全部」tab 上横滑：不翻页 ✅
  - 点击 tab 切换：正常 ✅
  - 点击「+」：正常弹出 sheet ✅
- [ ] git commit + push

## 文件改动清单

| 文件 | 新增/修改 | 大小 |
|---|---|---|
| `Views/iOSTabBarGestureBlocker.swift` | 新增 | ~30 行 |
| `Views/ContentView.swift` | 修改 `disableBounceInSubviews` | +4 行 |
| `Views/SidebarView.swift` | 加 `.background`、删 `.simultaneousGesture` | +2 / -4 行 |

## 风险缓解

- **风险：** SwiftUI 未来版本可能给 collectionView.panGestureRecognizer 自己挂 delegate  
  **缓解：** 我们的 delegate 是最后挂的会覆盖。如果未来 SwiftUI 依赖它自己的 delegate 逻辑失效，可以改为 wrapper delegate（转发给原 delegate）。暂时不做。
- **风险：** iOS 升级改变 TabView(.page) 底层实现（比如改回 UIPageViewController）  
  **缓解：** `disableTabViewBounce` 的 walk 已经只按类型判断 `is UICollectionView`，如果未来换了，那段代码整体失效，我们的挂 delegate 也一起失效——不会引入新问题，只是功能回退。
- **风险：** tag 数字冲突  
  **缓解：** 918273 足够大且非常规，业务代码不会用到。放常量 `TabBarMarker.tag` 单点维护。

## 不做（留给未来）

- 不处理 macOS（macOS 没有 TabView(.page)，没这个问题）
- 不给 TabView 的 pan 加 `require(toFail:)` —— 会拖慢主翻页响应
- 不用 GeometryReader+frame 方案 —— view-tag 更稳
