# Gotcha: SwiftUI `.ignoresSafeArea()` 在 UIHostingController 内让 UIView 物理 frame 溢出 hc.view.bounds

日期：2026-04-20
踩坑分支：`codex/theme-kelivo-settings`（路线 C Phase 1 调试时发现）
相关 commit：`8e31fae`
重要性：**核心陷阱**。影响所有"每页独立 UIHostingController 做 UIKit 容器（如自定义 UIScrollView paging / UICollectionView cell / UIPageViewController）"的场景。

---

## TL;DR

SwiftUI `.ignoresSafeArea()` 在 UIHostingController scope 里不仅让 view 扩展到 safe area，**还会让内部 UIView 的物理 frame 在 UIKit 层面超出 `hc.view.bounds`**——不止垂直方向，水平方向也可能。

UIScrollView / 自定义容器里把 UIHostingController.view 作为 subview 时，**`hc.view` 默认 `clipsToBounds = false`**，溢出的 SwiftUI view layer 能 render 到相邻 HC 的 viewport 区域，造成**跨页内容泄漏**。

**修复一行**：

```swift
hc.view.clipsToBounds = true   // 强制每页裁剪到 hc.view.bounds
```

对所有在 UIKit 层挂的 UIHostingController 都该这样加，不管 SwiftUI content 看起来"是否需要 clip"。

---

## 现象

路线 C Phase 1 的 3-page paging 容器（`UIScrollView(.horizontal) + isPagingEnabled + 3 UIHostingController`）：

- Page 0 = `Color.blue.ignoresSafeArea()`
- Page 1 = `Color.clear.background { ChatWallpaperBackdrop(...).ignoresSafeArea() }`
- Page 2 = `Color.green.ignoresSafeArea()`

**bug 表现**：swipe 到 page 0 停稳后，屏幕**左半纯蓝、右半 chat page 的 wallpaper**。scrollView.contentOffset.x = 0（正确）、page 0 HC.view.frame = (0, 0, 402, h)（正确）、page 1 HC.view.frame = (402, 0, 402, h)（正确），但视觉上 page 1 的 wallpaper 渲染到了 page 0 的右半 viewport。

纯色测试（`Color.magenta.ignoresSafeArea()` 替 `Color.clear.background { wallpaper.ignoresSafeArea() }`）**同样有泄漏**——所以不是 `ChatWallpaperBackdrop` 内部 layout 的锅，是 `.ignoresSafeArea()` 本身在 UIHostingController 里的系统行为。

---

## 根因分析

### 表层事实

1. UIHostingController.view 默认 `clipsToBounds = false`（`UIView` 的默认值；UIScrollView 是例外默认 true，但它的 subview 不是）
2. SwiftUI `.ignoresSafeArea()` 在 UIHostingController 里让 SwiftUI content 延伸到忽略 safe area insets
3. 这个"延伸"在 UIKit 层面是通过**把承载 SwiftUI content 的 UIView 的 frame 放大**实现的（而不是单纯 render trick）

### 实测确认的行为

当把每个 `hc.view.clipsToBounds = true` 后跨页泄漏**完全消失**——纯色、wallpaper、任意 SwiftUI content 都 OK。这反证了根因：SwiftUI 让某个内部 UIView 的 frame 比 hc.view.bounds 大，clip 一开就兜住。

### 为什么水平方向也溢出？

Portrait iPhone 的 horizontal safe area insets 应该是 0，`.ignoresSafeArea()` 理论上只垂直延伸。但实测水平方向也漏。推测原因（未 100% 确认）：

- SwiftUI 给 `.ignoresSafeArea()` view 的 UIView 多给了某种 margin（iOS 26 SwiftUI 实现细节）
- 或 UIHostingController 的 layout 把 safeAreaInsets 和 `additionalSafeAreaInsets` 组合时，横向也有 non-zero 的 effective inset
- 或 SwiftUI `.background` + `.ignoresSafeArea` 这种组合产生 UIView 嵌套结构，其中某一层 over-extend

精确机制不重要——**结论是 hc.view.clipsToBounds = true 是正确且必要的兜底**。

---

## 被这条坑影响过的历史 bug

1. **路线 C Phase 1 的"page 0 右半漏 wallpaper"**（本次发现，commit `8e31fae` 修）
2. **Phase 2 v1 的 Bug B**（commit `f7af017` 未修复就放弃）：wallpaper 在 body.background + `.offset` + `.ignoresSafeArea()`，翻页时非聊天页 status bar + home indicator 区漏 wallpaper 残影。之前猜的"`.ignoresSafeArea` 的 extension 由 UIHostingController 独立 tile 渲染不跟 `.offset`"**解释错了**——真相是 wallpaper UIView 的物理 frame 超出 body 的 frame，没有 clip 的父容器让溢出部分直接渲染在 window safe area 区
3. 可能还影响过「iOS 白条排查记录」、「theme-background-regression」等旧 issue。日后遇到"SwiftUI view 漏出预期边界"的 symptom，先怀疑这条
4. TabView 看上去没这问题是因为 TabView 内部每页是独立 UIHostingController **且** UIPageViewController 的 page content view 有自己的 clip

---

## 预防规则

**凡是把 UIHostingController.view 挂到 UIKit 层（UIScrollView、UICollectionViewCell、UIView addSubview、UIViewController 的 view hierarchy）的场景，都要：**

```swift
let hc = UIHostingController(rootView: someSwiftUIView)
hc.view.backgroundColor = .clear       // 常规
hc.view.clipsToBounds = true           // ← 必加，防 .ignoresSafeArea 物理溢出
```

即使 SwiftUI content 看起来"不该溢出"也要加。`clipsToBounds = true` 对 SwiftUI content 的视觉表现**没有负面影响**（SwiftUI 的 layout 本就期待被容器约束），但能兜住 `.ignoresSafeArea()` 等 API 在 UIKit 层制造的物理溢出。

---

## 测试 pattern（future-proof 建议）

建 UIKit 容器包 SwiftUI 的 paging / cell 时，放一个 **跨 scope 对比色** 的 debug mode 验证是否跨边界泄漏：

```swift
// 每页不同的 .ignoresSafeArea() 纯色
// 如果 swipe 后相邻页有其他色漏出 → clipsToBounds 没加或没生效
```

不要只用"正常 content"测——正常 content 的溢出可能视觉不明显（比如 wallpaper fill + overlay 容易伪装成"就该这样"），用显眼纯色一秒暴露问题。

---

## 相关

- `research-uikit-paging-container-2026-04-20.md` §1.2 的 "Hypothesis"——当时猜的 extension 机制是错的，真相是本 doc
- `plan-uikit-paging-container-2026-04-20.md` §5 Fallback（GeometryReader + explicit frame）—— 不需要了，`clipsToBounds` 就够
- `feedback_ios_ui_lessons.md`（auto-memory）—— 应该把这条加进去
