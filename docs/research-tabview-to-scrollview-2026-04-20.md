# Research: iOS 聊天页翻页不穿模 — TabView → ScrollView(.horizontal) paging

日期：2026-04-20
分支：`codex/theme-kelivo-settings`
状态：**Research，等粟粟确认理解正确**

---

## 1. 背景

引入 wallpaper 功能后，iOS 聊天页翻页穿模（图 18-22）。多次尝试把 wallpaper / top bar 挪进 iOSChatPage 都失败：

| 尝试 | 问题 |
| --- | --- |
| ZStack 里 wallpaper `.ignoresSafeArea()` | 撑大 ZStack，气泡被拉宽 |
| `.background { wallpaper.ignoresSafeArea() }` | SwiftUI 把 background 推到更外层，穿到邻页水平位置 |
| 外层 chatPage `.ignoresSafeArea()` | 整页漫 safe area，nav buttons 贴 status bar，ChatInputBar chip 贴 home indicator |

### 本质矛盾

- **wallpaper 漫 safe area** = 视图 frame 超出 TabView page 水平/垂直可见边界
- **翻页不穿模** = 视图 frame 必须严格跟随 page 的水平位置

TabView.page（内部 UIPageViewController）不暴露实时 drag offset，SwiftUI 没法让 body level 的 wallpaper 跟 page 同步滑动。唯一能规避穿模的办法是 wallpaper 和 page 水平位置绑定，但又要求 wallpaper 漫到 page 边界外 → 天然冲突。

### master 为什么没这问题

master **没有 wallpaper**。所有 page content 都在 safe area 内，翻页时每个 page 都是规规矩矩的卡片，自然没穿模。这个 worktree 加 wallpaper 后才暴露出这个架构短板。

---

## 2. 新 API：iOS 17/18 `ScrollView(.horizontal) + paging + onScrollGeometryChange`

### 2.1 关键组件

```swift
ScrollView(.horizontal) {
    HStack(spacing: 0) {
        listPage.containerRelativeFrame(.horizontal)
        chatPage.containerRelativeFrame(.horizontal)
        rightPage.containerRelativeFrame(.horizontal)
    }
    .scrollTargetLayout()
}
.scrollTargetBehavior(.paging)                     // 对齐到 page 边界
.scrollPosition($scrollPosition)                   // 程序化切页 + 当前 id
.scrollIndicators(.hidden)
.scrollBounceBehavior(.basedOnSize)                // 边界页不 bounce
.onScrollGeometryChange(for: CGFloat.self) {
    $0.contentOffset.x
} action: { _, newX in
    scrollOffsetX = newX
}
```

### 2.2 API 覆盖范围（全 iOS 17+，worktree deployment target `IPHONEOS_DEPLOYMENT_TARGET = 26.0` 完全可用）

| SwiftUI 符号 | 作用 | min iOS |
| --- | --- | --- |
| `ScrollView(.horizontal)` | 水平滚动容器 | 13+ |
| `.scrollTargetBehavior(.paging)` + `PagingScrollTargetBehavior` | page snap（等同 TabView.page 的停靠行为） | 17+ |
| `.scrollTargetLayout()` | 标记 HStack children 为 paging target | 17+ |
| `.containerRelativeFrame(.horizontal)` | 每个 child 占 container 宽度（=1 页） | 17+ |
| `.scrollPosition(Binding<ScrollPosition>)` + `ScrollPosition(idType:)` | 程序化切页 + 当前 id | 18+ |
| `.onScrollGeometryChange(for:of:action:)` | ⭐ 实时 scroll offset callback（每帧） | 18+ |
| `.scrollBounceBehavior(.basedOnSize)` | 边界页不 bounce | 17+ |
| `.scrollDisabled(Bool)` | 禁用滚动（替代 hack `isScrollEnabled`） | 16+ |

### 2.3 wallpaper + top bar 跟手公式

```swift
// body 层：
.background {
    ZStack {
        Theme.sidebarBg  // 常驻底色
        ChatWallpaperBackdrop(...)
            .offset(x: chatPageBaselineX - scrollOffsetX)
            .opacity(wallpaperOpacity)  // 可选：边缘淡出
    }
    .ignoresSafeArea()
}
.overlay(alignment: .top) {
    iOSChatTopBar
        .offset(x: chatPageBaselineX - scrollOffsetX)
        .opacity(wallpaperOpacity)
}
```

- `scrollOffsetX` 范围 `[0, 2*pageWidth]`（3 页）
- `chatPageBaselineX = 1 * pageWidth`（聊天页在中间页的 offset）
- 翻页时 `chatPageBaselineX - scrollOffsetX` 实时变化，从 0（聊天页居中）滑向 `-pageWidth`（聊天页滑出左）或 `+pageWidth`（滑出右）
- wallpaper 和 top bar **跟着聊天页水平同步滑动**
- 挂在 body 层所以漫 safe area 没问题
- 受 body 的 frame clip 限制，滑出屏幕就看不见 → 不穿模

可选优化：`wallpaperOpacity = max(0, 1 - abs(chatPageBaselineX - scrollOffsetX) / pageWidth)` 让边缘渐透，降低硬切感。

---

## 3. 现有 TabView 所有 behavior 对照表

这是改造的关键——每一条现有行为都要在新架构里有对应实现，不能遗漏。

### 3.1 ContentView.swift:216-289 `iOSLayout`

| 现有行为 | 代码 | 新方案 |
| --- | --- | --- |
| 3 页 TabView | `TabView(selection: $iOSPage) { page0.tag(0); page1.tag(1); page2.tag(2) }` | `ScrollView(.horizontal) { HStack { page0; page1; page2 }.scrollTargetLayout() }.scrollPosition($scrollPosition)` |
| `.frame(width: proxy.size.width)` 每页全屏宽 | `.frame(width: proxy.size.width)` | `.containerRelativeFrame(.horizontal)` |
| TabView 容器漫 top/bottom safe area | `.ignoresSafeArea(.container, edges: [.top, .bottom])` | ScrollView 外层 `.ignoresSafeArea(.container, edges: [.top, .bottom])` |
| 页内容样式 | `.tabViewStyle(.page(indexDisplayMode: .never))` | `.scrollTargetBehavior(.paging)` + `.scrollIndicators(.hidden)` + `.scrollBounceBehavior(.basedOnSize)` |
| 贴纸编辑时禁用翻页 | `.scrollDisabled(stickerVM.isEditingStickers)` | **同样**可以直接用 `.scrollDisabled()`（已原生支持） |
| 禁用 UIKit bounce | `disableTabViewBounce()` 找 UICollectionView 设 `bounces = false` | **全删**，用 `.scrollBounceBehavior(.basedOnSize)` 替代 |
| 键盘切页 inset 切换 | `updateKeyboardBehavior(for:)` 修改 `contentInsetAdjustmentBehavior` | **大概率不再需要**（ScrollView 不是 UICollectionView，键盘 inset 行为不同，待测） |
| 贴纸编辑 scroll 锁死 | `setStickerEditScrollLock(editing)` 遍历所有 UIScrollView | 只需锁水平 ScrollView（`.scrollDisabled`），竖直 CardFlowView 的锁仍需要（内部实现不动） |
| 翻页触感 | `.sensoryFeedback(.impact(weight:.light), trigger: iOSPage)` | 改用 `scrollPosition.viewID(type: Int.self)` 的 id 变化触发（`iOSPage` 变 computed） |
| 翻页收键盘 | `.onChange(of: iOSPage) { ... resignFirstResponder }` | 监听 scrollPosition id 变化做同样事 |
| 列表选对话跳聊天 | `withAnimation { iOSPage = 1 }` | `scrollPosition.scrollTo(id: 1)`（同样程序化） |
| page indicator | ZStack 内 VStack+Spacer+ignoresSafeArea(.container, .bottom) | 保留不动（挂在 iOSLayout 外层），fill 颜色改 read scrollPosition 的 id |
| 键盘隐藏时才显示 indicator | `if !isKeyboardVisible { ... }` | 保留 |
| 键盘显示/隐藏监听 | `onReceive(UIResponder.keyboard*Notification)` | 保留 |
| 世界书 entries 同步 | `onChange(of: globalWBManager?.books.count)` | 保留 |

### 3.2 ContentView.swift:136-166 body iOS 分支（wallpaper + top bar）

| 现有行为 | 代码 | 新方案 |
| --- | --- | --- |
| body sidebarBg 底色漫 safe area | `.background { ZStack { Theme.sidebarBg; ... } }` | 保留 |
| iOSPage==1 条件挂 wallpaper | `if iOSPage == 1 { ChatWallpaperBackdrop(...) }` | **不再条件**，永远挂（用 offset 决定可见性） |
| wallpaper 淡入淡出 | `.transition(.opacity) + .animation(.easeInOut(0.3), value: iOSPage)` | 改成 `.offset(x: ... - scrollOffsetX)`（跟手滑动代替淡入淡出） |
| top bar 同上 | `.overlay(alignment: .top) { if iOSPage == 1 { iOSChatTopBar } }` | 永远挂，加 offset |

### 3.3 其他

| 文件 | 现有行为 | 改不改 |
| --- | --- | --- |
| `CardFlowView.swift` | 内部 vertical ScrollView + ChatInputBar + top `.ignoresSafeArea(.container, edges: .top)` | 不改。嵌套 ScrollView(v→h) SwiftUI 原生支持 |
| `SidebarView.swift:332` | `Theme.sidebarBg`（不 ignoresSafeArea） | 不改 |
| `iOSChatTopBar` (ContentView:358-416) | ZStack { blur+gradient.ignoresSafeArea(.all, .top) + nav buttons HStack } | 不改（内部结构稳定） |
| `ChatWallpaperBackdrop.swift` | frame flex + allowsHitTesting(false) | 不改 |

---

## 4. 风险 / Edge cases

### 4.1 API 新度 / 兼容性

- `onScrollGeometryChange` 是 iOS 18+，deployment target 26.0 满足
- `ScrollPosition(idType:)` init 也是 iOS 18+
- 没有老设备兼容问题

### 4.2 嵌套 ScrollView

- 外层 horizontal paging ScrollView
- 内层 CardFlowView 的 vertical ScrollView
- SwiftUI 根据手势方向自动路由（测试过 iOS 17 后版本稳定），但需要在 simulator 里 regression：
  - 竖直滑动气泡：应该滑气泡不翻页 ✓
  - 水平 swipe 在气泡区域：应该翻页 ✓
  - 从气泡边缘斜向滑：两者之一占优（可接受）

### 4.3 性能

- `onScrollGeometryChange` 每帧 callback，wallpaper + top bar `.offset(x:)` 每帧更新
- wallpaper 是 Image + LinearGradient，更新 offset 应该是纯 compositor transform，不重绘，理论上不掉帧
- 需在 simulator 和真机（如有）回归

### 4.4 触感 sensoryFeedback

- `scrollPosition.viewID` 的类型安全：用 `Int` 当 id（0/1/2）
- `iOSPage` 改成 computed：`scrollPosition.viewID(type: Int.self) ?? 1`
- `sensoryFeedback(.impact, trigger: iOSPage)` 继续有效

### 4.5 初始位置

- TabView: `@State var iOSPage = 1`，启动时在聊天页
- ScrollView: 需要 `ScrollPosition(id: 1)` 初始化
- 可能需要 `.onAppear` 后 `scrollPosition.scrollTo(id: 1, animated: false)` 确保定位

### 4.6 程序化切页动画

- 当前：`withAnimation { iOSPage = 1 }`（淡入）
- 新：`withAnimation { scrollPosition.scrollTo(id: 1) }`（水平滑动）
- 视觉不同，但都是平滑过渡

### 4.7 键盘行为

- TabView 底层 UICollectionView 有复杂的 contentInsetAdjustmentBehavior 逻辑（针对 iOSPage==1 vs 其他切换）
- ScrollView 是纯 SwiftUI，contentInsets 由 SwiftUI 管理，键盘行为可能更简单或有差异
- **需在 simulator 回归**：
  - 聊天页打开键盘后气泡位置
  - 键盘时滑页（应被 scrollDisabled 或收键盘后允许）

### 4.8 `UIScrollView` hack 代码清理

- `disableTabViewBounce` / `disableBounceInSubviews` / `updateKeyboardBehavior` / `findCollectionView` 全删
- `setStickerEditScrollLock` / `setAllScrollViewsEnabled` 是否保留看是否还用于竖直 ScrollView 锁死（估计仍需要）

---

## 5. 改动文件清单

| 文件 | 改动范围 | 约行数 |
| --- | --- | --- |
| `ContentView.swift` | body iOS 分支 + iOSLayout + disableTabViewBounce 相关 | ±100 行 |
| `CardFlowView.swift` | 不改 | 0 |
| `SidebarView.swift` | 不改 | 0 |
| `ChatWallpaperBackdrop.swift` | 不改 | 0 |
| 其他 | 不改 | 0 |

---

## 6. 验收

1. 聊天页 wallpaper 漫 status bar + home indicator（现有效果保留）
2. 翻页时 wallpaper 和 top bar 跟聊天页一起滑走，**不穿模到邻页**
3. 控件位置正常（top bar nav 按钮、ChatInputBar chip 都在 safe area 内）
4. 翻页触感、键盘收起、程序化切页、page indicator 正常工作
5. 贴纸编辑时翻页被禁用
6. 嵌套 ScrollView 手势不冲突
7. macOS build 不受影响

---

## 7. 粟粟要确认的理解点

1. ✅ 现有 TabView 的所有 behavior 在新 ScrollView API 下都有对应实现（§3 表格）
2. ✅ 新方案用 iOS 17/18 官方 API，deployment target 26.0 满足
3. ⚠️ `onScrollGeometryChange` 每帧 offset callback + wallpaper offset 更新，**理论上**不掉帧，但需 simulator 回归
4. ⚠️ 键盘行为变化需要 simulator 回归
5. ✅ `disableTabViewBounce` 那套 UIKit hack 代码可以删了，用 `.scrollBounceBehavior(.basedOnSize)` 替代

这些理解对吗？确认后写 plan。
