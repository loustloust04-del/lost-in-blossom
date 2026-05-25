# Plan: iOS 聊天页底部安全区透明 hit shield

> 日期：2026-04-25
> 工作树：`.claude/worktrees/theme-kelivo-settings`
> 依赖 research：`docs/research-bottom-safearea-gesture-block.md`
> 状态：**plan-only，粟粟批注后再 implement，don't implement yet**

---

## 0. 已确认方向（粟粟批注 2026-04-25）

| 问题 | 决定 |
|------|------|
| 修复方案 | **方案 A — 在 home indicator 区挂透明 hit shield** |
| shield 高度读法 | GeometryReader 量 `safeAreaInsets.bottom`（兼容稳） |
| shield absorb 哪些手势 | tap + long-press；**不加 pan**（避免影响 ScrollView 边缘滑动 / 系统 home gesture） |
| 编辑贴纸模式下 | 保留 shield（home indicator 区不该响应任何手势） |
| iPad / iPhone 老款 | 自动 0pt（GeometryReader 读到 safeAreaInsets.bottom = 0 时 frame 高度 = 0，shield 形同不存在） |
| **键盘灌水防御** | **clamp shield 高度 ≤ 40pt**（任何机型 home indicator ≤ 34pt，40pt 留余量。即使外层 UIKit VC 通过 additionalSafeAreaInsets 手动注键盘 inset 让 safeAreaInsets.bottom 撑到 300+pt，shield 永远最多 40pt） |
| 平台范围 | 只 iOS，全部 `#if os(iOS)` 圈 |

---

## 1. 目标

修这一条：iOS 聊天页 home indicator 区被点 / 长按时不再误触发 bubble contextMenu / sticker 编辑模式。

**不做**：
- 不改 ScrollView frame、不改 LazyVStack padding
- 不动 bubble 的 `.contentShape(Rectangle())` / `.frame(maxWidth: .infinity)`（hover / 长按命中区维持现状）
- 不动 sticker 长按入口（`.onLongPressGesture` on stickerItem）
- 不动 StickerCanvasGestureOverlay（编辑模式 UIKit 手势层）
- 不动 ChatInputBar
- 不动 macOS 路径

---

## 2. 改动方案

### 2.1 在 `iOSChatPage` 加底部 hit shield

**位置**：`MemoryPalace/Views/ContentView.swift:597-607` 那个 `iOSChatPage` 的 ZStack

**改法**：在已有的 `.overlay(alignment: .top) { iOSChatTopBar }` 之后追加 `.overlay(alignment: .bottom) { … }`：

```swift
private var iOSChatPage: some View {
    ZStack(alignment: .top) {
        if viewModel.selectedConversation != nil {
            CardFlowView(viewModel: viewModel, stickerVM: stickerVM)
        } else {
            EmptyStateView(showImporter: $showImporter, profileId: profileManager?.currentProfile.id ?? "")
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .overlay(alignment: .top) {
        iOSChatTopBar
    }
    #if os(iOS)
    .overlay(alignment: .bottom) {
        BottomSafeAreaShield()
    }
    #endif
    .alert(…) { … }   // 已有
}
```

### 2.2 新增 `BottomSafeAreaShield` view

**位置**：放在 `ContentView.swift` 末尾、`EmptyStateView` 旁（同文件，避免新增 file 噪声；它只服务 iOSChatPage，不通用）

```swift
#if os(iOS)
/// home indicator 安全区手势屏蔽板。
/// 透明、只挡 tap + long-press、frame 高度 = 设备 bottom safeAreaInset，
/// home button 旧机型读到 0pt 时 frame = 0，等于不存在。
private struct BottomSafeAreaShield: View {
    var body: some View {
        GeometryReader { geo in
            Color.clear
                // clamp 40pt：任何机型 home indicator ≤ 34pt，
                // 即使外层 UIKit VC 通过 additionalSafeAreaInsets 注键盘 inset
                // 让 safeAreaInsets.bottom 撑到 300+pt，shield 永远最多 40pt，不挡键盘上方
                .frame(height: min(geo.safeAreaInsets.bottom, 40))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .contentShape(Rectangle())
                // 吃 tap：避免 bubble contextMenu 长按
                .onTapGesture { /* absorb */ }
                // 吃 long-press：避免 sticker .onLongPressGesture 进编辑模式
                .onLongPressGesture(minimumDuration: 0.2) { /* absorb */ }
                .ignoresSafeArea(.container, edges: .bottom)
                .allowsHitTesting(true)
        }
        .frame(height: 0)        // GeometryReader 不参与父 layout 高度计算
        .allowsHitTesting(true)
    }
}
#endif
```

**关键点**：
- 外层 `GeometryReader` 高度强制 0，让它**不影响 iOSChatPage 的 layout**（GeometryReader 默认会 expand）
- 内层 `Color.clear.frame(height: geo.safeAreaInsets.bottom)` 撑出实际 home indicator 高度
- `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)` + `.ignoresSafeArea(.container, edges: .bottom)` 让 shield 真正贴到屏幕底
- `.onTapGesture { }` + `.onLongPressGesture(minimumDuration: 0.2) { }` 空体 → 吃手势不触发任何动作
- 不加 `.gesture(DragGesture)` → 用户从 home indicator 边缘的滑动手势（系统 home gesture）不被影响

### 2.3 z 顺序（保证 input bar 不被挡）

`iOSChatPage` 的 ZStack 默认 alignment .top，子 view 按声明顺序叠：
- 底层（先声明）：`CardFlowView` / `EmptyStateView`
- `.overlay(.top) { iOSChatTopBar }` → 在底层之上
- `.overlay(.bottom) { BottomSafeAreaShield }` → 在 topBar overlay 之后追加，z 最高

但 ChatInputBar 在 `CardFlowView` 内部的 `.safeAreaInset(edge: .bottom)`（CardFlowView.swift:311），它在 SwiftUI 渲染上是属于 `CardFlowView` 这一层级的内容。BottomSafeAreaShield 在 `iOSChatPage` 这一层 `.overlay`，**z 上比 CardFlowView 更高**。

**关键检查**：shield 高度 = safeAreaInset**.bottom**（home indicator 高度，~34pt），ChatInputBar 在 home indicator **之上**。所以：
- shield 实际占据 = 屏幕底部 0 ~ 34pt（home indicator 区）
- ChatInputBar 实际占据 = 屏幕底部 34pt ~ 34+inputBarHeight pt（safe area 之内）
- 两者**不重叠** ✅

---

## 3. 风险与防守

### R1. shield 把 ChatInputBar 给挡了

**判断**：不会（见 §2.3）。但要验证：
- iPhone 14 Pro（home indicator 34pt）：shield 高 34pt，input bar 在 34pt 之上 → 不重叠
- iPhone SE 老款（home button，bottom safe area = 0pt）：shield 高 0pt，等于不存在 → 不影响

**验证**：模拟器 iPhone 14 Pro + iPhone SE，输入框点击文本框、attach 按钮、send 按钮，都正常响应。

### R2. shield 把 StickerKeyboardPanel 给挡了

**判断**：StickerKeyboardPanel 是 CardFlowView 内部 `.overlay(.bottom)` (CardFlowView.swift:370-394) + `.ignoresSafeArea(.container, edges: .bottom)` (CardFlowView.swift:391)，**会延伸到 home indicator 区**。

shield 在 iOSChatPage 这一层 overlay，z 比 StickerKeyboardPanel 高 → **会挡**。

**防守**：
- 编辑模式 / 贴纸面板模式下，**关掉 shield**（条件渲染 `if !stickerVM.isEditingStickers && !showStickerPanel`）
- 但等下——粟粟决策表里是"保留 shield"。问题是 StickerKeyboardPanel 的工具栏按钮就在 home indicator 上方那一带，按钮点击位置可能就是 shield 区。

**改方案**：shield 条件渲染——非编辑模式 + 非贴纸面板时才挂。这跟"保留 shield"的初衷（防 home indicator 区误触）一致：编辑模式时贴纸面板自己占据底部，没有 bubble 渗到那里，本来就没问题。

```swift
.overlay(alignment: .bottom) {
    if !stickerVM.isEditingStickers && !showStickerPanel {
        BottomSafeAreaShield()
    }
}
```

但这要求 iOSChatPage 能读到 stickerVM 和 showStickerPanel——stickerVM 是 ContentView 已有的 `@State`/`@Bindable`，showStickerPanel 是 CardFlowView 内部的 @State，**iOSChatPage 读不到**。

**两种解决**：
- **A1**：把 showStickerPanel 提到 ContentView 层（@State），传给 CardFlowView。改动比 shield 本身大。
- **A2**：BottomSafeAreaShield 自己在 SwiftUI 层 disable hit testing on edit mode，靠 stickerVM 即可。但 showStickerPanel 不在 stickerVM 上，是 CardFlowView 私有 @State。
- **A3**：忽略 showStickerPanel，只看 `stickerVM.isEditingStickers`。逻辑：showStickerPanel 必然伴随 isEditingStickers = true（CardFlowView.swift:341 `showStickerPanel = true` 同时 `stickerVM.isEditingStickers = true`），所以读 isEditingStickers 已经够了。

→ **采用 A3**，shield 条件 = `if !stickerVM.isEditingStickers`。

```swift
.overlay(alignment: .bottom) {
    if !stickerVM.isEditingStickers {
        BottomSafeAreaShield()
    }
}
```

**修订决策表**：跟"编辑贴纸模式下保留 shield"略冲突——但实际上编辑模式下 home indicator 区被 StickerKeyboardPanel 占了，没有 bubble 渗到那里，shield 就没必要存在；非编辑模式才是真正需要挡的场景。这个修订更合理，先写进 plan。

### R3. shield 挡了系统 home indicator 上滑手势

**判断**：iOS 系统 home gesture 由 SpringBoard 拦截在窗口最外层，App 内的 view hit testing 不会阻止它。`.onTapGesture` / `.onLongPressGesture` 是 SwiftUI 高层手势，不影响系统手势。

**但要小心**：如果用 `.gesture(DragGesture())` 会拦截 pan，可能干扰 home gesture 起手。**plan 已决定不加 pan**，安全。

### R4. shield 高度计算 + 软键盘交互

`safeAreaInsets.bottom` 在软键盘弹起时会变成键盘高度（~291pt 左右，含 toolbar）。如果 shield 直接读这个值，键盘弹起时 shield 高度 = 键盘高度，**会挡键盘上方一大片可视区域**。

**怎么办**：
- 选 1：shield 读的是 `geo.safeAreaInsets.bottom` 在 GeometryReader 看到的"自家"safe area。GeometryReader 在 iOSChatPage 这一层，bottom safe area 包含键盘还是不包含？SwiftUI 默认键盘会被加进 safeAreaInset.bottom。
- 选 2：clamp 到设备 home indicator 高度。iPhone 14 Pro = 34pt，iPhone SE = 0pt。但这要做设备检测，繁琐。
- 选 3：用 `.ignoresSafeArea(.keyboard)` 让 GeometryReader 不响应键盘 inset，只响应设备 home indicator inset。

**采用 clamp 40pt 双保险**：
```swift
.frame(height: min(geo.safeAreaInsets.bottom, 40))
```

理由：粟粟 memory `feedback_nested_hosting_controller_keyboard.md` — 项目用外层 UIKit VC 手动 `additionalSafeAreaInsets` 注键盘 inset，**不是走 SwiftUI `.keyboard` region**。所以 `.ignoresSafeArea(.keyboard)` 可能挡不住手动注入的 inset。

clamp 40pt 是硬天花板：home indicator 最高 ≈ 34pt（iPhone 16 Pro Max），任何机型都 ≤ 40pt。即使 safeAreaInsets.bottom 被键盘撑到 300+pt，shield 永远最多 40pt 高，**绝无可能挡键盘上方区域**。

不再用 `.ignoresSafeArea(.keyboard)`（无副作用，但 clamp 已是硬保险，不需双重防御）。

### R5. EmptyStateView 路径

无 selectedConversation 时走 EmptyStateView (ContentView.swift:601)，shield 仍挂着——但 EmptyStateView 是垂直居中的占位文字，没有 home indicator 区误触问题。shield 在 EmptyStateView 上挂着也无副作用（吃 tap，但 EmptyStateView 不响应 tap）。

→ **不区分**，shield 在两条路径都挂。

### R6. macOS 路径

全部修饰用 `#if os(iOS) … #endif` 圈，macOS 路径不动。

---

## 4. 实施步骤

### Step 1：加 BottomSafeAreaShield struct + iOSChatPage 挂 overlay

- [ ] ContentView.swift 末尾（在 EmptyStateView 之后）加 `private struct BottomSafeAreaShield`，`#if os(iOS) … #endif` 圈
- [ ] iOSChatPage 在已有 `.overlay(alignment: .top) { iOSChatTopBar }` 之后加 `#if os(iOS) .overlay(alignment: .bottom) { if !stickerVM.isEditingStickers { BottomSafeAreaShield() } } #endif`
- [ ] BottomSafeAreaShield 内部用 GeometryReader 读 safeAreaInsets.bottom + `.ignoresSafeArea(.keyboard, edges: .bottom)` 屏蔽键盘 + `.frame(height: 0)` 不抢 layout

完成标准：
- 代码加 ~25 行（一个 struct + 一个 overlay）
- macOS 路径不动一字符
- 不引入新 file / 新 import

### Step 2：build 验证

- [ ] `xcodegen generate && xcodebuild -scheme MemoryPalaceIOS -destination 'generic/platform=iOS Simulator' build`
- [ ] `xcodebuild -scheme MemoryPalace build`（macOS）

完成标准：双平台 build 通过。

### Step 3：模拟器手动验证（iOS）

- [ ] **场景 1**：进入一条**有消息渗到 home indicator 区**的对话（最后一条 assistant 长气泡），点 home indicator 区 → 不弹 contextMenu ✅
- [ ] **场景 2**：长按 home indicator 区 → 不弹 contextMenu ✅
- [ ] **场景 3**：贴纸放在底部气泡附近，滚动让 sticker 渗到 home indicator 区，点 / 长按那里 → 不进编辑模式 ✅
- [ ] **场景 4**：input bar 各按钮（attach 图标、文本框、发送箭头）正常响应 ✅
- [ ] **场景 5**：中部聊天区点气泡 → contextMenu 正常弹（hover 按钮也正常）✅
- [ ] **场景 6**：中部聊天区长按 sticker → 进入编辑模式正常 ✅
- [ ] **场景 7**：进入编辑模式后，StickerKeyboardPanel 工具栏按钮（在 home indicator 上方那带）正常响应 ✅（shield 此时关掉）
- [ ] **场景 8**：软键盘弹起 → home indicator 被键盘覆盖、shield 高度仍 = 设备 home indicator 不变（不会挡键盘上方区域）✅
- [ ] **场景 9**：iPhone SE 模拟器（无 home indicator）→ shield 高度 = 0，所有点击照常 ✅
- [ ] **场景 10**：从屏幕底向上滑（系统 home gesture）→ 正常返回桌面，shield 不拦截 ✅

完成标准：以上全部 pass。

### Step 4：commit + push

- [ ] `git add MemoryPalace/Views/ContentView.swift docs/research-bottom-safearea-gesture-block.md docs/plan-bottom-safearea-gesture-block.md`
- [ ] commit message: `fix(iOS): home indicator 区透明 hit shield — 防 bubble contextMenu / sticker 长按误触`
- [ ] push 到 origin

---

## 5. 影响范围

### 必改文件
- `MemoryPalace/Views/ContentView.swift`（+~25 行：1 个 overlay 修饰 + 1 个 struct）

### 不改
- `MemoryPalace/Views/CardFlowView.swift`（不动）
- `MemoryPalace/Views/StickerCanvasLayer.swift`（不动）
- `MemoryPalace/Views/ChatInputBar.swift`（不动）

### 新增文件
- `docs/research-bottom-safearea-gesture-block.md`（已写）
- `docs/plan-bottom-safearea-gesture-block.md`（本文件）

---

## 6. 完成定义

1. iOS 聊天页 home indicator 区点 / 长按**不再触发** bubble contextMenu / sticker 编辑模式
2. 输入框 / 中部聊天区 / 编辑模式工具栏 / 系统 home gesture **全部不受影响**
3. macOS 路径零变化
4. iPhone 14 Pro / iPhone SE 两种机型 build + 表现都正确
5. 软键盘弹起时 shield 自动缩到设备 home indicator 高度（不挡键盘上方区域）
6. plan checklist 全 ✅，commit + push

---

## 7. Todo Tracker

- [ ] 1. ContentView.swift 加 `BottomSafeAreaShield` struct（**clamp 40pt** 写进 frame）
- [ ] 2. ContentView.swift `iOSChatPage` 挂 `.overlay(alignment: .bottom) { if !stickerVM.isEditingStickers { ... } }`
- [ ] 3. iOS build
- [ ] 4. macOS build
- [ ] 5. 模拟器：home indicator 区 tap → 无 contextMenu
- [ ] 6. 模拟器：home indicator 区 long-press → 无 contextMenu
- [ ] 7. 模拟器：sticker 渗到 home indicator 区 → 长按不进编辑模式
- [ ] 8. 模拟器：input bar 按钮正常
- [ ] 9. 模拟器：中部聊天区手势全正常（contextMenu / hover / sticker 长按进编辑）
- [ ] 10. 模拟器：编辑模式 StickerKeyboardPanel 工具栏正常
- [ ] 11. 模拟器：软键盘弹起 shield 不挡键盘上方
- [ ] 12. 模拟器：iPhone SE shield 高度 0pt
- [ ] 13. 模拟器：系统 home gesture 不受影响
- [ ] 14. commit + push

---

## 8. 状态

✅ **关档（2026-04-25）**

### 实际定案 ≠ 原 plan

原 plan 是 SwiftUI overlay shield 挡 home indicator 34pt。V1-V3 SwiftUI 实现失败（GeometryReader frame(0) 塌缩 / SwiftUI gesture 拦不住 UIContextMenuInteraction）。V4 改 UIKit 顶层 shield（PagingViewController.view 上 + window safeAreaInsets.bottom），命中链稳定但**只覆盖 home indicator 34pt**。

真机 17 Air 探针打出来，发现粟粟实际点击 y=848~865 — **不在 home indicator 区**，而是在 **ChatInputBar VStack 的空白区**（input field 下方 + 模型胶囊左边 Spacer + padding）。SwiftUI VStack 默认无 hit shape，空白区 hit 穿透到底下 ScrollView 的气泡 row → 触发 `.contextMenu`。

**V6 最终修复**（commit 33b7645）：
1. `CardFlowView.swift` ChatInputBar VStack 加 `.contentShape(Rectangle())` — VStack 自己吞空白区 hit，不穿透
2. `CardFlowView.swift:1330` 删 BubbleView 外层 `.contentShape(Rectangle())` — 顺手修气泡 row 空白宽度不响应（V5 commit 1217013）
3. `CardFlowView.swift` 视觉压缩：spacing 6→4, padding bottom 8→4, dots 上移 4pt（V5 commit 1217013）
4. `PagingViewController.swift` UIKit shield 保留挡 home indicator 34pt — sticker 渗到那里时不进编辑模式（V4 commit 4b28b3d）

### Commit 链

- 55bd252 V1 SwiftUI overlay（GeometryReader frame(0) 塌缩，失败）
- 3a88392 V2 VStack 双段（SwiftUI gesture 拦不住 UIContextMenuInteraction，失败）
- bb83c8f V3 UIViewRepresentable HitShield（在 chat HC 子树里漂移，时灵时不灵）
- 4b28b3d V4 UIKit 顶层 shield（PagingViewController + window safeArea + 4 类探针）
- 1217013 V5 删 BubbleView contentShape + 视觉压缩
- 33b7645 V6 ChatInputBar VStack contentShape — **真正解决误触**

### 关键教训

- 探针证据驱动 > 推理（feedback_probes_over_reasoning）— V1-V3 都是猜，V4 加探针后直接看到 point.y 在 shield 上方，方向立刻转
- "底部安全区"≠ home indicator —粟粟视觉概念是"input bar 底沿到屏底"，覆盖 input bar VStack 内空白
- SwiftUI VStack 默认无 hit shape，空白区让 hit 穿透是常见坑
