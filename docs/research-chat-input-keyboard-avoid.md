# Research: 聊天页输入框不跟键盘上移（kelivo 路线 C 回归）

> 2026-04-21 · ultrathink
> 现象：kelivo 分支聊天页点输入框，键盘弹起，输入框不跟着上浮（master 正常）

## 一、现象 & 确认

- **粟粟报告**：聊天页点输入框，键盘弹起，**输入框不跟着弹起**（原地待着）
- **master 正常**：键盘弹起时 ChatInputBar 自动贴键盘顶边
- **kelivo**（路线 C 重构后）失效

区别发生在路线 C（UIKit paging 容器）那组 commit：
- `8e31fae` Phase 1 of C — UIKit paging 容器
- `d084c6d` Phase 2 of C — chat page 挪进 child HC
- `57bfbb5` Phase 3 of C — pageIndicator 挪 body overlay

## 二、master vs kelivo 架构差异

### Master（TabView）
```
App UIHostingController （唯一 HC，监听键盘）
  └── SwiftUI TabView
        .ignoresSafeArea(.container, edges: [.top, .bottom])   ← 只 container, 不含 .keyboard
        └── UICollectionView (TabView 底层)
              contentInsetAdjustmentBehavior = .never          ← 不靠 UICollectionView 做键盘 inset
              └── cell (iOSChatPage) — 直接嵌 SwiftUI，无独立 HC
                    └── CardFlowView.ScrollView
                          .safeAreaInset(.bottom) { ChatInputBar }   ← 跟 .keyboard region 走
```

键盘 avoidance 链路：
1. App HC 监听键盘
2. SwiftUI 给 rootView 加 `.keyboard` safe area region = 键盘高度
3. TabView 外层 `.ignoresSafeArea(.container, …)` — **没忽略 .keyboard**，region 继续向下传
4. 传到 CardFlowView 的 ScrollView → `.safeAreaInset(.bottom)` 把 ChatInputBar 推到键盘之上 ✅

### Kelivo（路线 C / UIKit PagingViewController）
```
App UIHostingController
  └── SwiftUI iOSLayout
        └── PagingContainerView（UIViewControllerRepresentable）
              .ignoresSafeArea()                                ← ⚠️ 默认 .all（含 .keyboard）
              └── PagingViewController（UIKit）
                    └── UIScrollView(水平 paging)
                          contentInsetAdjustmentBehavior = .never
                          ├── 列表 HC (独立 UIHostingController)
                          ├── 聊天 HC (独立 UIHostingController) ← ChatInputBar 在这里面
                          └── 面板 HC (独立 UIHostingController)
```

## 三、最可疑根因（hypothesis A）

**`PagingContainerView(...).ignoresSafeArea()` 默认 regions = `.all`，包含 `.keyboard` region。**

对比 master 是 `.ignoresSafeArea(.container, edges: [.top, .bottom])` — 明确排除 `.keyboard`。

影响链：
1. 外层 SwiftUI view tree 的 `.keyboard` safe area 被 `.ignoresSafeArea()` 吞掉
2. 传递到 PagingContainerView wrapper view 的 SwiftUI layout 时，wrapper 不响应键盘（不留出键盘区域）
3. PagingViewController.view 也不缩 frame
4. child HC 的 view.frame 由 PagingViewController.viewDidLayoutSubviews 硬编码为 `CGRect(x: i·w, y: 0, w, screenH)`，**不随键盘 resize**
5. child HC 内部 SwiftUI 虽然自己监听键盘（iOS 16+ 每个 HC 自带 keyboardLayoutGuide），但由于 `hc.view.clipsToBounds = true` + frame 覆盖全屏（含键盘区），SwiftUI 对 rootView 加的 `.keyboard` safe area 失效或被吃

简言之：**`.ignoresSafeArea()` 的默认参数在路线 C 的多级嵌套 HC 结构下，导致 keyboard region 在 SwiftUI / UIKit 边界丢失**。

## 四、Fix 假设（hypothesis）

**最小改动**：`ContentView.swift:256` 把 `.ignoresSafeArea()` 改成 `.ignoresSafeArea(.container, edges: [.top, .bottom])`（对齐 master TabView modifier）。

### 预期效果
- PagingContainerView wrapper view 保留 `.keyboard` region
- 键盘弹起时，wrapper view 的 SwiftUI frame 响应键盘 → PagingViewController.view.bounds.height 随键盘减小（≈ screenH - keyboardH）
- child HC.view.frame 在 viewDidLayoutSubviews 里也跟着缩小 h
- chat page 内 SwiftUI `.safeAreaInset(.bottom)` 的 ChatInputBar 自然贴到新的 bounds 底 = 键盘顶 ✅

### 副作用风险
- `.ignoresSafeArea(.container, edges: [.top, .bottom])` 是 master 原 TabView 行为——列表/面板 page 也会跟着键盘上移，但它们不 focus 无输入，视觉不突兀
- 如果 PagingViewController.viewDidLayoutSubviews 的 frame 计算对 bounds 变化不 re-layout，可能产生副作用——但看代码 `hc.view.frame = CGRect(x, 0, w, h)` 每次都用最新 `view.bounds.height` ✅
- `scrollView.contentInsetAdjustmentBehavior = .never`（paging scrollView）不受影响，因为水平 paging 不 care 垂直 inset

## 五、验证方式

1. 修改 `ContentView.swift:256`
2. `xcodegen generate && xcodebuild -scheme MemoryPalaceIOS -destination "generic/platform=iOS" build`
3. 装真机，聊天页点输入框验证键盘弹起后 ChatInputBar 是否跟着上浮
4. 回归 checklist：
   - [ ] 列表 / 面板 page 切过去，status bar / home indicator 底色没漏白
   - [ ] 编辑贴纸模式：StickerKeyboardPanel 正确挂底
   - [ ] 键盘收起后 ChatInputBar 回底

## 六、如果 hypothesis A 不对的备选方向

- 给每个 child HC 显式设 `automaticallyAdjustsScrollIndicatorInsets` / `view.keyboardLayoutGuide.followsUndockedKeyboard` 等
- PagingViewController.view 订阅 `UIKeyboardWillShowNotification`，手动调整 view.bounds 或 child HC.view.frame
- 改回 TabView（放弃路线 C）— 极端方案

## 七、记忆索引

- `feedback_ignoressafearea_hosting_overflow.md` — .ignoresSafeArea 在 HC 里物理溢出
- `feedback_ios_ui_lessons.md` lesson #5.5（safeAreaInset 内 view 不突破安全区）
- `feedback_ios_ui_lessons.md` lesson #8（TabView 键盘避让 `contentInsetAdjustmentBehavior`）
- `docs/research-ios-keyboard.md`（TabView 架构下的 S1-S5 键盘研究，历史）
