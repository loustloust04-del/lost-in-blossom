# Research: 17 Air 冷启动 / 第一次键盘卡顿

日期：2026-04-22
机型：iPhone 17 Air（A19 Pro）
现象：粟粟反馈 **"第一次打开第一次点键盘也卡的要死"**
优先级：**🔴 高**（17 Air 是主力机 + TestFlight 主打机型，如果冷启动 jank 到"要死"，非修不可）

> 这条**独立于** B13（iPhone 14 滚动卡），不共享主因。B13 是稳态 / 滑动；这条是 cold-path（"第一次"）。

---

## 一、先把"卡"的特征摸清

粟粟的原话给了两个非常关键的 qualifier：**"第一次"** + **"卡的要死"**。

| 触发 | 17 Air 表现 | 17 Air 之后再做 | iPhone 14 |
|---|---|---|---|
| 第一次打开 app | 卡 | 再次打开不再卡 | （B13 更严重，推测也有第一次特征，需确认） |
| 第一次点键盘 | 卡 | 再次点同样场景不卡 | （B13 场景） |

**"第一次" = cold path**：系统层资源（Metal shader / backdrop filter / font metrics / SwiftUI 首次 diff）需要在这个时刻实例化，花销大。

**"卡的要死"** = 非几毫秒级感知，可能 200-600ms 的 stall。用户能看到：
- 点击后屏幕不动 X 百毫秒才响应
- 或者键盘弹起动画掉帧很明显

这份 research 要定位的就是 **A19 Pro 这种顶级 GPU 也吃不消的 cold path 到底在做什么**。

---

## 二、App 启动到 chat idle 的关键链路（静态梳理）

### 2.1 启动主线程堆栈（`MemoryPalaceApp.swift:350-386`）

```
App.init()
├─ FontManager.registerImportedFonts()        (log: 毫秒级)
├─ ProfileManager.makeUnifiedContainer()      (SwiftData schema 第一次 init，log: ~80ms)
├─ ProfileManager.loadProfiles()               (UserDefaults + seed)
├─ UnifiedContainerMigration.needsMigration(profiles:)
│  (新用户无 legacy → 跳过；粟粟已迁过 → 跳过)
├─ ProfileManager(container:profiles:currentProfile:)
└─ migrateMemoryNotesIfNeeded(container:)     (v2 已跑过 → 跳过)

log: [PERF] App.init total=109ms font=3ms unified=82ms profile=15ms migrate=8ms
```

App.init 总共 **~110ms**。不算离谱但也不算快。

### 2.2 ContentView 第一次 body + iOS 布局构造（`ContentView.swift:103-319`）

```
ContentView.body
├─ themeManager / 订阅
├─ iOSLayout.PagingContainerView(listPage:, chatPage:, dashPage:, ...)
│  └─ 3 个 AnyView 都立即 build（lazy eval 但 makeUIViewController 会展开）
```

### 2.3 `PagingViewController.viewDidLoad` (`PagingViewController.swift:68-117`)

```
viewDidLoad()
├─ wallpaperContainer + wallpaperImageView + wallpaperGradientLayer (UIKit layer setup)
├─ view.insertSubview(wallpaperContainer, at: 0)
├─ scrollView setup
├─ for hc in hostingControllers {
│     addChild(hc)
│     hc.view.backgroundColor = .clear
│     hc.view.clipsToBounds = true
│     scrollView.addSubview(hc.view)
│     hc.didMove(toParent: self)
│  }   // ← 3 个 HC 一次性 add，都会 layout
├─ NotificationCenter.addObserver(keyboardWillChangeFrame)
└─ NotificationCenter.addObserver(keyboardWillHide)
```

**关键点**：3 个 UIHostingController **同时**被 attach。`hc.view.clipsToBounds = true` 触发 first layout → SwiftUI 开始 diff 整棵 rootView。

### 2.4 第一次 viewDidLayoutSubviews (`PagingViewController.swift:144-175`)

- scrollView.frame = view.bounds
- wallpaper frame + CAGradientLayer frame
- `applyWallpaper(config)` → 第一次触发 `UIImage(contentsOfFile:)` decode + `applySaturation()` CIFilter 跑一次
- 3 个 hc.view.frame 设定
- scrollView.contentOffset 设到 initialPage=1（chat 页）

### 2.5 每个 HC 第一次 render rootView（同步）

**chatHC**（`iOSChatPage` → `CardFlowView`）整棵第一次 build：
- ScrollView + LazyVStack + 可见 bubbles
- overlay Layer 1：**VariableBlurView**（顶部 130pt）
- overlay Layer 2：PinnedMessageBar
- safeAreaInset.bottom：**ChatInputBar**
  - InputFieldContainer：**`.glassEffect(.regular.tint(...).interactive(), in: .rect(cornerRadius: 20))`** full-width
  - 底栏贴纸按钮：**`.glassEffect(.regular.tint(...).interactive())`**
  - 底栏模型按钮：**`.glassEffect(.regular.tint(...).interactive())`**
  - 输入条背景：**VariableBlurView**（底部 60-160pt）

**listHC**（`iOSListPage` → `SidebarView`）：
- 搜索框：**`.glassEffect(.regular.tint(...), in: .capsule)`**（`SidebarView.swift:150`）
- 菜单按钮：**`.glassEffect(.regular.tint(...).interactive(), in: .circle)`**（`SidebarView.swift:166`）

**dashHC**（`iOSDashboardPage` → `RightPanelView`）：
- 默认 `selectedToolId="memory"` → `MemoryPanelView`（内含列表）
- 不含 glass（快速目测）

### 2.6 总 offscreen pass 首次 shader 编译数量

| 页 | offscreen pass 类型 | 数量 | 是否 .interactive() |
|---|---|---|---|
| chatHC | VariableBlur backdrop | 2 | — |
| chatHC | glassEffect | 3 | 3/3 |
| listHC | glassEffect | 2 | 1/2 |
| dashHC | — | 0 | — |
| **合计** | **7 个 shader pipeline** | — | **4 个 interactive** |

**7 个 Metal shader pipeline 第一次编译**（并行 enqueue，但 pipeline creation 有串行化开销），A19 Pro 也不能免。典型每个 pipeline 20-80ms compile，累积可达 300-600ms 主线程阻塞。

---

## 三、"第一次点键盘"的链路（静态梳理）

### 3.1 触发序

```
用户 tap 输入框
  ↓
SwiftUI FocusState: isFocused true
  ↓
InputFieldContainer.body 重算 (focused=true 分支)
ChatInputBar.body 重算（isFocused 在 @FocusState）
  ↓
系统路径：
  UIKit 拉起键盘动画 + UIResponder.keyboardWillShowNotification
  ↓
PagingViewController.keyboardFrameWillChange(_:)  ← @objc observer
  ├─ 计算 overlap + systemBottom + extra
  └─ chatHC.additionalSafeAreaInsets = UIEdgeInsets(bottom: extra, ...)
  ↓
chatHC.view.setNeedsLayout() 被 UIKit 自动标记
  ↓
chatHC 内部 UIHostingController 触发 SwiftUI re-measure
  ↓
整棵 CardFlowView re-layout：
  - ScrollView bottom inset 变
  - LazyVStack 可见 bubbles 重 frame
  - ChatInputBar padding(.bottom, isFocused ? 5 : 8)
  - .safeAreaInset(.bottom) spacing/frame 变
  - overlay VariableBlur 上 frame 变
  - 3 个 glass bounds 变 → backdrop 重 sample
  ↓
iOS 键盘动画 (0.25s) 同时进行
```

### 3.2 关键痛点 — chatHC.additionalSafeAreaInsets 是**整棵 SwiftUI re-layout 触发器**

这是**设计上的耦合**：

- `PagingViewController` 是 UIKit
- 键盘第一次要把 insets 传到 SwiftUI 只有通过 `additionalSafeAreaInsets` 这个 UIHostingController 属性
- 改这个属性 → UIHostingController 让 SwiftUI root 整棵 re-compute，SwiftUI 不能部分重算（它的 layout model 就是自顶向下）

首次尤其贵：
- 之前 LazyVStack 的可见 bubble frame 是 "no-keyboard" layout 下算的
- 第一次键盘来，整棵重算到 "with-keyboard" layout，所有 bubble frame 都要重做
- 同时 4 个 interactive glass 的 backdrop sample 也要在新位置重采样（第一次可能触发 backdrop render pipeline cold path）

A19 Pro 也会感知（4+2 offscreen pass 同时 re-layout + backdrop re-sample 第一次是 shader miss）。

---

## 四、嫌疑排序

| # | 嫌疑 | 证据强度 | 修复成本 | 预期收益（17 Air） |
|---|---|---|---|---|
| **H1** | 冷启动时 3 个 HC × 共 7 个 offscreen pass shader 首次编译 | 高 | 中 | 高 |
| **H2** | 第一次点键盘触发 chatHC.additionalSafeAreaInsets → 全页 re-layout + 4 个 glass backdrop re-sample | 高 | 中-大 | 高 |
| H3 | 冷启动时 wallpaper UIImage 第一次 decode + CIFilter saturation（主线程） | 中 | 小 | 中 |
| H4 | SwiftData 第一次 @Query fetch（SidebarView 的对话列表 / EmptyStateView） | 中 | 小 | 中（log 已经有 App.init 时间，但第一次 @Query 没探针） |
| H5 | Font 渲染 cache 未预热 | 低 | 小 | 低 |

---

## 五、建议方向（给 Plan 参考，don't implement yet）

### 方向 A — GlassEffectContainer 合并（解 H1 + H2 部分）

Apple 官方推荐：`GlassEffectContainer` 把多个 `glassEffect` 合并成一次 offscreen pass。

```swift
// ChatInputBar 当前：3 个 glassEffect 彼此独立
GlassEffectContainer {
    VStack {
        InputFieldContainer(...)
            .glassEffect(...)
        HStack {
            stickerButton.glassEffect(...)
            Spacer()
            modelButton.glassEffect(...)
        }
    }
}
```

- 优点：Apple 官方解，collateral damage 最小
- 缺点：需要确认容器是否影响视觉（`GlassEffectContainer` 会把里面所有 glass shape 合并到一个 "morph" 层，跟当前"3 个独立 capsule"视觉可能不一致）
- 预期收益：首次 shader 编译 3 → 1 pass，第一次键盘 re-layout 时 backdrop re-sample 3 → 1

### 方向 B — 冷启动 shader 预热

在 App.init 后或 ContentView.onAppear 里，后台 render 一个离屏 GlassEffectContainer + VariableBlurView，让 Metal pipeline 提前编译。

```swift
// 原理：show 一次、隐藏掉；shader 缓存住
.task {
    let prewarm = ZStack {
        Text("").padding().glassEffect(.regular.interactive())
        VariableBlurView(maxBlurRadius: 1.3, direction: .blurredTopClearBottom)
    }
    // render 到 offscreen UIWindow / ImageRenderer 一次就好
}
```

- 优点：专治 cold path，不改视觉
- 缺点：需要测 A/B 证明真的把 shader compile 前置到 idle 时间片

### 方向 C — 键盘避让路径改造（解 H2）

当前：`additionalSafeAreaInsets` 改 → SwiftUI 全页 re-layout

替代：让 `ChatInputBar` 自己响应键盘（SwiftUI native `.safeAreaInset(.bottom)` + `.ignoresSafeArea(.keyboard)` 组合），而不是通过 UIKit chatHC 注入。但历史上 Route C 的嵌套 HC 让 SwiftUI native keyboard avoidance 失灵（见 `feedback_nested_hosting_controller_keyboard.md`）。所以改造要回查这个坑。

- 优点：彻底避开整页 re-layout
- 缺点：回头看 Route C 嵌套 HC 键盘避让历史，这个改动风险大（可能复活已修好的 bug）

### 方向 D — 延迟 list/dash 页首次 render

3 个 HC 现在都立即 render rootView。可以让 list/dash 页在 HC 首次 attach 时塞一个 `Color.clear` 占位，等主线程空闲或用户 scroll 到该页时再 swap 成真 rootView。

- 优点：首次可见 chat 页的"总 shader 编译"从 7 降到 5（砍掉 SidebarView 的 2 个 glass）
- 缺点：改动 PagingViewController 结构，要注意不破坏 sidebar 已经 working 的行为

---

## 六、推荐下一步顺序

1. **第一步（简单且大概率见效）：方向 A — `GlassEffectContainer` 合并**
   - 两处需要合并：ChatInputBar 3 个 glass + SidebarView 2 个 glass
   - 改动 ~30 行，视觉验收粟粟确认
   - 预期：第一次冷启动 + 第一次键盘都明显变顺

2. **第二步（如果 A 不够）：方向 B — shader 预热**
   - 在 `ContentView.task` 里后台预热
   - 改动 ~30 行

3. **第三步（如果 A+B 不够才做）：方向 C 或 D**
   - C 风险高（回头碰 Route C 的键盘避让历史坑）
   - D 改动 PagingViewController 结构

先不碰 B13 iPhone 14 滚动那条——那条是 H3/H4（CALayer 数量 + MarkdownUI）路线，跟 17 Air cold path 解法不共享。

---

## 七、给粟粟的决定题

（doc 里列完，粟粟在这里批注）

### Q1：先上方向 A 吗？

- 建议 **是**。改动最小，风险可控，Apple 官方推荐解。实际效果我来 build + iPhone 17 模拟器/真机测冷启动 + 第一次键盘，看掉帧是否变好。
- 如果 A 装完 17 Air 真机反馈"还是卡"，再决定是否 B/C/D。

### Q2：A 如果视觉有变（`GlassEffectContainer` 把 3 个独立 capsule 合并成 morph 层），你接受吗？

- 如果接受，我直接上
- 如果不接受，我给你一张 A/B 对比截图再决定
- 默认：**先上，视觉不行就 git revert**

---

## 八、这份 research 不包含的

- **没有 cold path 真机 log**：第一次打开到 first frame 的 timing 需要粟粟在 17 Air 上装一个加了 [PERF] 探针的 debug build。但改 A 之前这个 log 也没必要——先改 A 测就行。
- **没排除 SwiftData 第一次 @Query 开销**（H4）：如果 A 上完粟粟还说卡，再查。

---

## 附：参考

- [Apple: glassEffect(_:in:)](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:))
- [Apple: GlassEffectContainer](https://developer.apple.com/documentation/swiftui/glasseffectcontainer)
- [Understanding GlassEffectContainer in iOS 26](https://dev.to/arshtechpro/understanding-glasseffectcontainer-in-ios-26-2n8p)
- [Liquid Glass in Swift: Official Best Practices](https://dev.to/diskcleankit/liquid-glass-in-swift-official-best-practices-for-ios-26-macos-tahoe-1coo)
- 项目内：`feedback_nested_hosting_controller_keyboard.md`（Route C 嵌套 HC 键盘避让历史）
- 项目内：`docs/postmortem-kelivo-keyboard-wallpaper.md`（Route C 双重坑复盘）
- 项目内：`docs/research-b13-iphone14-idle-lag.md`（B13 相关，独立主因）
