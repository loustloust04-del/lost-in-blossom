# Research: 贴纸手势 regression — iOS 编辑模式下拖/缩放/旋转全失效

> 日期：2026-04-24
> 分支：codex/theme-kelivo-settings（但 bug 在 master 也有）
> 症状报告者：粟粟实测
> 基准 good state：`ff23400`（贴纸系统合入 master 那次，2026-04-15）

## 症状（粟粟实测）

编辑模式下已经放到对话里的贴纸：

| 手势 | 行为 |
|------|------|
| 单指 tap | ✓ 浮起（首次） |
| 单指 pan（拖动） | ✗ 完全不动 |
| 双指 touch（落下） | ✓ 浮起（首次） |
| 双指 pinch（缩放） | ✗ 完全不动 |
| 双指 rotate（旋转） | ✗ 完全不动 |
| 第二次 tap 同一贴纸 | ✗ 不浮起 |

**特征**：瞬时 recognizer（tap / zero-duration longPress）work 第一次；**持续性 recognizer（pan / pinch / rotation）从不触发**；第二次 tap 不出动画（极可能因 `selectedPlacedStickerId` 已经是这个 sticker id，SwiftUI 同值 set 无 diff）。

## 核心事实

### 事实 1：贴纸手势两个核心文件从 ff23400 到现在**一个字没改过**

```
$ git diff ff23400 HEAD --stat \
  -- MemoryPalace/Views/StickerGestureOverlay.swift \
     MemoryPalace/Views/StickerCanvasLayer.swift
（0 行输出）
```

→ **bug 不在 sticker 手势/canvas 代码本身**，而在挂它们的**环境**里。

### 事实 2：bug 在 master 也有（粟粟实测）

→ **路线 C（UIKit PagingViewController）不是根因**。master 当前仍是 SwiftUI TabView。
→ 必须在 ff23400 → master HEAD 之间找环境侧改动。

### 事实 3：ff23400 → master HEAD 环境侧改动总览

master 对贴纸挂载环境改的文件：

```
CardFlowView.swift    +536 行（PinBar / 回底按钮 / 哨兵 / InputFieldContainer / equatable）
ContentView.swift      +61 行（小改动）
StickerViewModel.swift +42 行（profileSwitchObserver + onConversationMutated）
```

关键改动清单（master 相对 baseline）：

- [B1] LazyVStack 里新增底部哨兵 `Color.clear.frame(height:1).id("__bottom_sentinel__")`
- [B2] `.safeAreaInset(edge: .top)` 顶部挂 PinBar（非空 pin 时）
- [B3] `.onScrollGeometryChange(for: Bool.self)` 监听 isAtBottom
- [B4] bubble `.contextMenu` 菜单项 `+"钉住 / 取消钉住"`（**不**新增 gesture modifier，只加 menu item）
- [B5] `LazyVStack(spacing: 22 → bubbleSpacing)` dynamic（默认 31）
- [B6] ChatInputBar 拆出 InputFieldContainer 子 view
- [B7] ChatInputBar `.equatable()`（stream perf）
- [B8] StickerViewModel init 里挂 `NotificationCenter.profileWillSwitch` observer
- [B9] onStickerTap 的 onStickerTap 闭包 nil/non-nil 区分

路线 C 额外改动（kelivo only，不影响 master bug 定位）：

- [C1] TabView → PagingViewController（UIKit UIScrollView + 3 × UIHostingController）
- [C2] PinBar 从 CardFlowView.safeAreaInset 挪到 ContentView.iOSChatTopBar
- [C3] 贴纸按钮位置从底部 HStack 挪进 InputFieldContainer 左侧
- [C4] wallpaper 挪到 UIKit layer（CAGradientLayer）

## 诊断性实验记录

### 实验 1（2026-04-24）：注掉 StickerGestureOverlay 的 UIContextMenuInteraction
- 改动：`view.addInteraction(contextMenu)` 一行注释
- 粟粟真机实测结果：**没有任何改变**（pan/pinch/rotate 依然不动，第二次 tap 依然不浮）
- **结论**：
  - H1（bubble contextMenu 冲突）**证伪**
  - H6（iOS 26 UIContextMenuInteraction 行为改变）**证伪**
  - 粟粟明确说"不只是 26 特性"，bug 在更早 iOS 版本上也应该有
- 改动已回滚。

## 假设池

### H1：bubble 的 `.contextMenu` 在 iOS 26 下劫持持续性 recognizer（✗ 证伪 — 见实验 1）

### H2：`.safeAreaInset(edge: .top)` PinBar 改变 ScrollView 内部 UIView 层级（中）
- `.safeAreaInset` 在 iOS 下会给 UIScrollView 套一层 container，改变 content view 的 superview 链。
- overlay UIView 的 hit test 路径多一层；但 singleTap 能 fire 说明 hit test 链通。
- 可能影响的是 `UIGestureRecognizer` 之间的 `require(toFail:)` 关系 — 如果 PinBar container 挂了某个手势，可能污染下游。

### H3：`.onScrollGeometryChange` 内部 observer 触发 ScrollView frame 变化（中）
- 这个 iOS 18+ API 内部实现可能在 UIScrollView 上挂 observer，每次 scroll geometry 变化就 notify。
- 如果 observer 触发 SwiftUI re-layout → ContentHeightKey preference 变化 → StickerCanvasGestureOverlay frame 变 → **SwiftUI 在 updateUIView 期间 reparent UIView** → 正在进行的 pan recognizer 被 reset。
- 但这个理论下 singleTap 应该也不稳定（touches 没抬起前就 reparent），但实测 singleTap 第一次稳定。需要探针验证。

### H4：底部哨兵 + sticker canvas 导致 contentHeight 在 gesture 中动态变化（高⭐）
- 哨兵 `Color.clear.frame(height:1).id("__bottom_sentinel__")` 在 LazyVStack 里，让 content 总高多 1pt。
- sticker canvas `.frame(height: max(contentHeight, 1))` 响应 `ContentHeightKey` preference。
- 当 user 开始拖贴纸 → sticker.positionX/Y 变 → bubble 位置不变但 sticker canvas 内 ZStack 的 subview position 变 → 可能触发 preference 重算 → contentHeight 抖动 → overlay UIView frame 抖动 → SwiftUI 可能在这期间重 layout → 打断 pan。
- **matches 瞬时 recognizer OK、持续性 recognizer 挂** 的症状特征。

### H5：ChatInputBar.equatable() 拦住了 onStickerTap 的 closure 更新，导致 stickerVM ref stale（低）
- 从 InputFieldContainer 点按钮 → stickerVM 的 ref 可能 stale。
- 但 stickerVM 是 @State 在 ContentView，ref 恒定，stale 不太可能。
- **反证**：第一次 tap 能浮起贴纸说明 `stickerVM.selectedPlacedStickerId` set 成功，stickerVM ref 有效。
- 排除。

### H6：iOS 26 系统行为改变（✗ 证伪 — 粟粟明确说"不只是 26 特性"）
- 粟粟反馈更早 iOS 版本应该也有这个 bug。

### H7：StickerViewModel.init 里 NotificationCenter observer 引发 VM 被重新订阅/重算（低）
- observer 只在 `.profileWillSwitch` 时触发，平时无行为。
- 排除。

### 机理重建模（ctxMenu 证伪后）

症状再审视："瞬时 recognizer（tap、zero-duration longPress）首次 work，持续性 recognizer（pan、pinch、rotate）完全不 fire" 的物理机理：

**机理 A** — SingleFingerPanGesture.touchesMoved 的 `event.allTouches > 1` 误判
- `event.allTouches` 是**整个 window 所有活跃 touch**，不是 pan 自己 track 的 touches
- 如果系统/祖先某处有 phantom touch（palm rejection / Pencil hover / iOS 26 系统 touch），activeTouchCount > 1 → pan 立刻 `.failed`
- 解释 pan ✗：完美
- 解释 pinch/rotate ✗：**不解释**（它们是标准 UIKit recognizer，没子类化）
- 解释 tap ✓：tap 在 `.ended` 判定，touch 数已降到 0
- **只能解释单一症状，不是根因**

**机理 B** — ⭐ 领先 ⭐ 父层 UIScrollView 的 `canCancelContentTouches = YES` 在 scrollDisabled(true) 下依然 cancel 触摸
- 默认值：`UIScrollView.canCancelContentTouches = YES`、`delaysContentTouches = YES`
- 当用户手指在 overlay 上移动时，父 UIScrollView 的 panGestureRecognizer **依然在 evaluating**（虽然 `isScrollEnabled = false` 让它永远不 `.recognized`）
- evaluating 过程中的 `cancelsTouchesInView` 行为 → overlay 的 touches 被 cancel → pan/pinch/rotate 的 `.began` 永远不触发
- 解释 pan ✗：完美（pan 需要持续 touch + 移动来识别）
- 解释 pinch ✗：完美（需要 2 指持续 touch）
- 解释 rotate ✗：完美（同上）
- 解释 tap ✓：完美（tap 在手指没移动时 `.ended` 完成，未触发 scroll view 的 cancel）
- 解释二次 tap ✗：部分 — 若首次 tap 后 scroll view 进入某种 hold 状态持续 cancel，可解释

**机理 B 胜出**：统一解释所有症状。

### B 的佐证链

1. **symptom matrix 完全拟合** — 最强佐证
2. **iOS 版本无关** — 符合 "master 也有 + 粟粟说不只 iOS 26" 的事实
3. memory `feedback_uikit_gesture_layer.md` 第 1 条同源 pattern — UIKit 祖先 pan delay 让子 view 手势失灵
4. SwiftUI ScrollView 在 iOS 的底层实现使用 UIScrollView，`scrollDisabled(true)` 仅设 `isScrollEnabled = false`，**不会改变 `canCancelContentTouches` 或 `delaysContentTouches`**（Apple xcdoc 核实：这两个 property 默认 YES 且 SwiftUI 无对应 modifier）

### B 的反证（待实验验证）

- 理论上 `isScrollEnabled = false` 会让 panGestureRecognizer.isEnabled 也变 false，disabled recognizer 不 evaluate → 不 cancel touches
- **但 SwiftUI ScrollView 的 isScrollEnabled 切换行为未经确认**；更重要的是，在 **嵌套 ScrollView**（chat page 的竖直 ScrollView + 路线 C 下 PagingContainer 的水平 UIScrollView）里，**某层的 cancelsTouchesInView 可能未被禁**
- baseline ff23400 只有一层 ScrollView（竖直），`scrollDisabled(true)` 足够
- 现在 master 有 `.safeAreaInset(edge: .top)` PinBar，safeAreaInset 的实现在 iOS 底层会**套一层 UIView 容器**（可能是另一个 UIScrollView 或带 gesture 的 UIView），这层可能没被 scrollDisabled 禁

### 为什么 baseline (ff23400) 不复现？

ff23400 的 CardFlowView 只有**一层 SwiftUI ScrollView**（竖直），外包一个 TabView（水平）。
- SwiftUI TabView(.page) 底层是 UICollectionView；`.scrollDisabled(stickerVM.isEditingStickers)` 挂在 TabView 上 → 禁了 UICollectionView 水平 pan
- 内层 SwiftUI ScrollView 也有 `.scrollDisabled(stickerVM.isEditingStickers)` → 禁了竖直 pan

现在 master 在**同一层 SwiftUI ScrollView 上加了 `.safeAreaInset(edge: .top)` PinBar** + `.onScrollGeometryChange`。这两个 modifier **可能让 ScrollView 的 hit test 结构新增一层 UIView / UIScrollView / 或改变 scroll geometry**，scrollDisabled 不再完全禁 cancel 行为。

## 领先假设：机理 B（父 UIScrollView cancelsTouchesInView）

**领先度排序更新**：
1. ⭐⭐⭐ **机理 B**（父 UIScrollView cancel content touches）
2. ⭐⭐ H2（`.safeAreaInset` PinBar 改 UIView 层级）— 是 B 的具体诱因
3. ⭐ H3（`.onScrollGeometryChange` 相关）— 可能协同
4. ⭐ H4（contentHeight 抖动）— 更弱

H-New1（event.allTouches phantom touch）降级为备选诊断，不是主要怀疑。

## 领先假设：H4（保留作备选）

**核心机理推测**：

1. 编辑模式进入 → overlay UIView 创建 + 挂 recognizer ✓
2. 用户 tap 贴纸 → singleTap `.ended` 一次性 fire → `selectedPlacedStickerId = sticker.id` + 浮起动画 ✓
3. **浮起动画期间 sticker.scale 做 spring 动画（0.8x → 1.0x）**
4. sticker 本身 frame 变化 → bubble GeometryReader 的 preference 重算 → contentHeight 新值 → StickerCanvasLayer 的 `Color.clear.frame(height: max(contentHeight, 1))` frame 改 → ZStack 重 layout → overlay UIView 的 frame 被 SwiftUI reset
5. 此时用户手指在贴纸上按住 → pan 进 `.possible` → 但正在 layout 的 UIView **touches 被 cancel 或 delay**
6. pan 永远无法进 `.began`

**为什么 singleTap 第二次不 work**：
- 第一次 tap → id = sticker.id
- 0.5s 后 auto-deselect → id = nil
- 但如果 deselect 没跑（如 selected state 不稳定、或者 id 被 pan 的 `.began` try 重 set 一次），id 卡住 = sticker.id
- 第二次 tap → 同值 set → SwiftUI 不 diff → 无动画 → 视觉"没浮起"

### H4 反证未确认

- 为什么 master（没 Route C）也有？→ B1（底部哨兵）+ B2（PinBar safeAreaInset）+ B3（onScrollGeometryChange）三者叠加。
- 需要 bisect 才能真正落地 H4。

## 下一步：探针

### Step 1：在 `StickerGestureOverlay.swift` 加 `[PROBE 贴纸]` print
覆盖：
- SingleFingerPanGesture.touchesBegan / touchesMoved：活跃触点数、pan state、location
- handlePan 每个 state（.began / .changed / .ended / .cancelled / .failed）
- handlePinch / handleRotate 每个 state
- handleSingleTap / handleTwoFingerTouch / handleDoubleTap 入口
- shouldRecognizeSimultaneouslyWith（记录双方 class）
- makeUIView / updateUIView 调用次数 + UIView.superview 类名
- configurationForMenuAtLocation 入口

### Step 2：在 `StickerCanvasLayer.swift` 加探针
- body 重算次数（`let _ = { print... }()`）
- contentHeight 变化
- overlay frame height（从 `.frame(height: max(contentHeight, 1))` 拿）
- editModeStartTime 变更

### Step 3：粟粟装真机跑一次复现
步骤：
1. 进入一个已有贴纸的对话
2. 点底栏"贴纸"按钮 → 进入编辑模式（overlay 挂载）
3. tap 一次贴纸 → 看到浮起
4. 尝试拖动 → 拖不动
5. 再次 tap → 看到不浮起
6. 把 Xcode console 里 `[PROBE 贴纸]` 的 log 全部贴过来

### Step 4：看 log 定根因
根据 log 分支：

| 观察 | 诊断 |
|------|------|
| handlePan 的 `.began` 从没 fire | pan 被 block / 没识别到 touchesMoved → 查 touchesBegan 是否收到 |
| touchesBegan 收到但 pan 进 `.failed` | activeTouchCount > 1（误判为双指）或 state 被外力设 fail |
| pan 进 `.began` 但 `.changed` 立刻 `.cancelled` | UIView 在 drag 中被 reparent / touches cancel → H4 验证 |
| updateUIView 每帧被调 | H4 + H3 验证（contentHeight 抖动） |
| contentHeight 在 drag 中变化 | H4 验证（哨兵 + sticker canvas 循环） |

## 规则

- 探针全部 `print("[PROBE 贴纸] ...")` 前缀，定根因后 `git log | grep '[PROBE 贴纸]'` 一次清干净
- 不改任何逻辑，只加 print
- 加在 kelivoworktree，粟粟在 kelivo 分支 build 测；测完不 merge，探针 commit 单独

## 开放问题待粟粟确认

1. **进入编辑模式的路径**：底栏"贴纸"按钮进入 vs 长按贴纸进入 —— 两个路径是否症状一致？【一致】
2. **iPhone 型号 + iOS 版本**：iOS 26 / 18 / 其他？【17Air，ios26】
3. **是否有 log 规律**：第二次 tap 同一贴纸 vs tap 另一贴纸，症状是否相同？【同】
4. **bisect 预算**：如果粟粟愿意在 master 上 `git checkout` 到 ff23400、3f100c4、4534b74、e62cded 等几个 commit 装一次真机确认 "从哪个 commit 开始坏"，可以把假设收敛到一个具体 commit。但耗时约 30 分钟，可以不做。【可以试，但是你先修，自己先用模拟机验证，弄不好再排查】
