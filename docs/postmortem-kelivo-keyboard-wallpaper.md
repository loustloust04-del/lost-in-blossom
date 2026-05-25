# Postmortem: kelivo 路线 C 下的键盘 + 背景双重坑

> 2026-04-21
> 分支：`codex/theme-kelivo-settings`
> 时长：一天（从初次汇报到收官）
> 最终 commit：`192bf62`

## TL;DR

粟粟报告"聊天页点输入框键盘弹起但输入框不动"。实际上这是**两个独立根因叠加**带来的幻觉：
1. wallpaper 在 SwiftUI layer 响应键盘 safeArea 等比放大 13% → 视觉"背景在动"
2. `injectPagingEnv` 漏注入 ProviderManager → ChatInputBar 根本没 render
3. 即便补了 env 注入，嵌套 child HC 在 UIKit `PagingViewController` 下，SwiftUI `UIHostingController` 默认 keyboard avoidance 机制**失灵**——keyboard region 不进 SwiftUI tree

三个根因互相掩盖，花了一天才依次定位。最终修法：
- wallpaper 下沉到 UIKit `PagingViewController.view` 底层 UIImageView + CAGradientLayer
- `injectPagingEnv` 补齐 ProviderManager / ProfileManager / PresetManager
- `PagingViewController` 监听键盘通知 + 手动设 `additionalSafeAreaInsets.bottom`

## 背景

master 架构是 TabView + 同一 App-level UIHostingController；SwiftUI 的 environment 和 keyboard avoidance 都自然工作。

kelivo 路线 C 把 TabView 换成了 **自定义 `PagingViewController`（UIKit）**，里面 `UIScrollView(.horizontal) + 3 个 child UIHostingController`，为了解决 TabView 的水平 paging bounce 和 `.ignoresSafeArea` 跨页溢出问题。这个重构结构性正确，但引入了**两个 SwiftUI / UIKit 边界陷阱**，正好都在键盘这条链路上。

## 症状时间线

| 时刻 | 粟粟报告 | 我误判的根因 |
|---|---|---|
| T0 | "点输入框键盘弹起但输入框没跟着弹起" | 以为是 `.ignoresSafeArea()` 参数问题 |
| T1 | 改 `.ignoresSafeArea(.container, [.top, .bottom])` → 输入框动了但**背景也动** | 以为背景不动是目标，修错方向 |
| T2 | 加 observer + `safeAreaRegions = .container` → 输入框有 2× 空白 | 以为是 region 叠加（实际当时 ChatInputBar 根本没 render） |
| T3 | wallpaper 挪 chat page HC 外（ZStack）→ 左栏右栏翻页三倍宽被裁切 | 以为是 ZStack 的 Representable sizing bug |
| T4 | 换成 `.background` pattern → 三倍宽修了，**但背景还动** | 以为是 `.background` 的 safe area 传递不一致 |
| T5 | Step 1 保存时 center-crop wallpaper → aspect 对了（427×929）**但键盘时背景还动 13% 放大** | 找到了 image intrinsic 根因但 keyboard 根因还没暴露 |
| T6 | Step 3 wallpaper 挪 UIKit 层 → 背景完全不动 ✅ | A 系列收官 |
| T7 | 真机截图"输入框不见了" → 初判 env 问题，补注入 | 部分对 |
| T8 | 补 env 后红条可见但**键盘弹起红条不动** | 锁定 child HC keyboard avoidance 失灵 |
| T9 | PagingViewController observer + additional safeArea → 键盘 346 → 34 切换，红条跟着动 ✅ | B 系列收官 |

## 根因分析

### A 系列：键盘弹起 wallpaper 跟着动

**实证**（commit 9850905 探针 log）：
```
wallpaper onAppear size=(427.83, 929.0)   ← 初始
wallpaper size changed to (484.01, 1051.0) ← 键盘弹起，等比放大 13%
PagingVC.viewDidLayoutSubviews bounds=(0,0,420,912)  ← UIKit 层不变
（键盘弹起时 PagingVC.viewDidLayoutSubviews **不 fire**）
```

→ UIKit `PagingViewController.view.bounds` 不响应键盘，但 SwiftUI 层 wallpaper 的 `.background` content frame 却响应了 keyboard safeArea。

**机制推断**（未严格 xcdoc 验证，但行为一致）：`.background { content.ignoresSafeArea() }` 的 content 的 proposed size 来自 primary view 的 SwiftUI layer frame，SwiftUI layer 会响应 `.keyboard` region。即便 primary view 用 `.ignoresSafeArea()` 吞掉 keyboard region，background layer 的 sizing 仍会被重算。

**修法（Step 3）**：把 wallpaper 从 SwiftUI `.background` 挪到 UIKit `PagingViewController.view` 底层：
```swift
view.insertSubview(wallpaperContainer, at: 0)   // UIKit 层最底
wallpaperContainer.frame = view.bounds           // 只随 viewDidLayoutSubviews 变
```

UIImageView.contentMode = `.scaleAspectFill` 自动处理任意 aspect 图（之前试过的 "保存时 center-crop" Step 1 方案就变冗余了，已 revert）。键盘弹起 `viewDidLayoutSubviews` 不 fire → wallpaper 不动。

### B 系列根因 1：ChatInputBar 根本没 render

**实证**（commit 0e0ece7 [PROBE env]）：
- ContentView.body: `provider=true profile=true preset=true wb=true` ← App 注入 OK
- CardFlow body: 补 env 前 `prov=nil`，补后 `prov=true`

**根因**：`MemoryPalaceApp.swift:385-392` 给 ContentView 外层注入 **8 个 managers**：
```swift
.environment(themeManager)
.environment(profileManager)
.environment(providerManager)   // ← chat 链路必需
.environment(presetManager)
...
```

Route C 重构时 `injectPagingEnv`（`ContentView.swift:308`）只补了 `modelContext / themeManager / globalWBManager` **3 个**。child HC 不继承 parent SwiftUI env，其它 5 个全被 swallow。

CardFlowView `.safeAreaInset(.bottom) { else if let pm = providerManager { ChatInputBar... } }` 没 else 分支，`providerManager` nil → inset content 为空 → **ChatInputBar 根本不 render**（截图里看不到输入框的根因）。

**修法**（`a2a97e8`）：`injectPagingEnv` 补齐 Provider / Profile / PresetManager。

### B 系列根因 2：嵌套 child HC 下 SwiftUI keyboard avoidance 失灵

**实证**（commit 24b6257 [PROBE kbd A/B]）：
```
# 初始状态
chatPage root safeAreaInsets initial = (top:68, bottom:34)  ← home indicator only
scrollView safeAreaInsets initial    = (top:68, bottom:34)

# 点输入框弹键盘
（无 changed to 事件）  ← SwiftUI view tree 完全不响应键盘
```

xcdoc 说 `UIHostingController.safeAreaRegions` 默认 `.all` 包含 `.keyboard` 应该自动注入键盘 region。**实际在嵌套 child HC（不是 window rootVC）下这个机制不工作**。

这是 SwiftUI / UIKit 边界行为，xcdoc 没明说。唯一的可靠修法是**手动补**。

**修法**（`82f52bb`）：`PagingViewController` 监听 `keyboardWillChangeFrameNotification`，计算 overlap 后设 `chatHC.additionalSafeAreaInsets.bottom`：

```swift
let overlap = max(0, chatHC.view.bounds.maxY - frameInChat.minY)
// 扣系统 bottom safeArea（home indicator）避免 double count
let systemBottom = currentBottom - currentExtra
let extra = max(0, overlap - systemBottom)
chatHC.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: extra, right: 0)
```

**实证验证**（最终 log）：
```
chatPage root safeAreaInsets changed to bottom=346   ← 34 (home) + 312 (extra) = keyboard overlap
chatPage root safeAreaInsets changed to bottom=34    ← 键盘收起
```

`.safeAreaInset(.bottom) { ChatInputBar }` 正确响应 bottom safe area，ChatInputBar 贴键盘顶。

## 关键教训

### 1. "事出有因"救命

全程用 `feedback_cite_evidence_no_guessing.md` 当武器。ever当面 hypothesis "UIScrollView.sizeThatFits 返回 contentSize 导致 ZStack 给 Representable 3×pageW frame" 被粟粟让我批评自己，查 xcdoc 发现默认返回 existing size，hypothesis 整个错。之后每个 claim 都查 xcdoc 或代码引用或加探针实测。

### 2. 探针先于推理

嵌套 SwiftUI + UIKit 边界的行为**无法靠推理预测**。A6 靠 PROBE bg 探针发现 SwiftUI layer vs UIKit layer 不同步。B1 靠 PROBE env/sai/kbd 三层探针依次排除 env / render / keyboard 三个不同根因。

### 3. 多根因互相掩盖

一开始 "输入框不动" 看起来是一个问题，实际是 3 个：
- 背景 wallpaper 在 SwiftUI 层响应键盘
- ChatInputBar 因 env 缺失不 render
- child HC 键盘 avoidance 失灵

如果没把 A 系列背景问题先修到 UIKit 层，B 系列键盘修了 wallpaper 仍然动，会反复返工。修一层，让下一层 bug 暴露出来。

### 4. 小步迭代 + revert 的价值

中间试错走过 Step 1（wallpaper 保存时 crop），验证发现不是根治方向 → revert，进 Step 3（UIKit 层）。revert 不是失败，是**逐层定位信息价值**。

### 5. feedback_worktree_coexistence 验证

这次在 `.claude/worktrees/theme-kelivo-settings` 里纯隔离工作，没影响主分支。CLAUDE.md 的 worktree pattern 又被验证对。

## 相关文档 / 记忆

- `docs/research-chat-input-keyboard-avoid.md` — 初版 research（历史）
- `docs/research-wallpaper-crop.md` + `plan-wallpaper-crop.md` — Step 1 试错
- `docs/research-wallpaper-uikit-layer.md` + `plan-wallpaper-uikit-layer.md` — Step 3 最终方案
- `docs/legacy/ChatWallpaperBackdrop.swift.txt` — 原 SwiftUI wallpaper 备份
- `feedback_cite_evidence_no_guessing.md` — 本次新建规则
- `feedback_probes_over_reasoning.md` — 被反复验证

## commit 时间线

| commit | 意图 | 成败 |
|---|---|---|
| `fc19d14` | 初版 observer + safeAreaRegions=.container | WIP，2× 空白（误判：其实 ChatInputBar 没 render） |
| `703006d` | wallpaper 挪 iOSLayout ZStack + transition | 三倍宽 bug |
| `879d536` | 换 `.background` pattern | 修三倍宽 |
| `2320429` | 保存时 center-crop | aspect 对了但背景还动 |
| `d9b9b3f` | revert 2320429 | 方向错了 |
| `150d89b` | Step 3 research + plan | 文档 |
| `97d11d3` | Step 3 UIKit wallpaper | **A 系列修好** |
| `f64bec2` | 撤 UIKit probes | A 清理 |
| `a2a97e8` | injectPagingEnv 补 env | **B 根因 1 修好** |
| `82f52bb` | PagingViewController 键盘 observer | **B 根因 2 修好** |
| `192bf62` | 撤 B probes | 收尾 |

共 11 个 commit，净代码 ~220 行增。
