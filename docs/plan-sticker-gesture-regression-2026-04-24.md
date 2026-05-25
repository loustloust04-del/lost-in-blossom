# Plan: 贴纸手势 regression 诊断 + fix

> 日期：2026-04-24
> Research：`docs/research-sticker-gesture-regression-2026-04-24.md`
> 领先假设：**机理 B**（父 UIScrollView `canCancelContentTouches` 在 scrollDisabled 下依然 cancel overlay 触摸）

## 诊断原则

- 不再盲目试修（ctxMenu 已试过无效）
- **先探针拿 log，再定根因，再 fix**
- 探针一批上齐，一次 build、一次真机测、log 一次性定论
- 只加 print，不改逻辑；探针 prefix `[PROBE 贴纸]` 便于一次性清

## Phase 1：探针（信息收集）

### Task 1.1：`StickerGestureOverlay.swift` 加探针
- [ ] **SingleFingerPanGesture.touchesBegan**
  - print `touches.count`、`event.allTouches?.count`、`state.rawValue`
- [ ] **SingleFingerPanGesture.touchesMoved**
  - print `touches.count`、`event.allTouches?.count`、`activeTouchCount` 结果、`state.rawValue` before & after
  - 特别关注 `activeTouchCount > 1` 是否误触发 `.failed`
- [ ] **handlePan** 5 个 state 分支入口 + 出口
  - print `state.rawValue`、`numberOfTouches`、location
- [ ] **handlePinch** 3 个 state 分支入口
  - print `state.rawValue`、`scale`、`numberOfTouches`
- [ ] **handleRotate** 3 个 state 分支入口
  - print `state.rawValue`、`rotation`、`numberOfTouches`
- [ ] **handleSingleTap / handleTwoFingerTouch / handleDoubleTap** 入口
  - print `gesture.state`、location
- [ ] **shouldRecognizeSimultaneouslyWith** 入口
  - print 双方 recognizer 的 `classForCoder`、各自 state
- [ ] **makeUIView** 末尾
  - print "[PROBE 贴纸 makeUIView] created UIView"
  - DispatchQueue.main.async 后 print **superview 链 5 层的 className + frame + isUserInteractionEnabled**
    - 目的：定位父 UIScrollView + 其他可疑 ancestor
- [ ] **updateUIView** 入口
  - print `uiView.frame`、`uiView.superview?.classForCoder`

### Task 1.2：`StickerCanvasLayer.swift` 加探针
- [ ] body 重算计数器（`let _ = { print("[PROBE 贴纸 layer.body] count=\(counter)") }()`）
- [ ] `.frame(height: max(contentHeight, 1))` 改用 print 插入：每次 contentHeight 变化打印新值

### Task 1.3：祖先 UIScrollView 状态探针（新增文件或嵌入 Overlay）
- [ ] 在 StickerCanvasGestureOverlay.makeUIView 里，main.async 后走 superview 链找到所有 UIScrollView
- [ ] 对每个找到的 UIScrollView，print：
  - `className`、`frame`
  - `isScrollEnabled`
  - `canCancelContentTouches`
  - `delaysContentTouches`
  - `panGestureRecognizer.isEnabled`、`panGestureRecognizer.state.rawValue`
  - `gestureRecognizers?.map { ($0.classForCoder, $0.state.rawValue, $0.isEnabled) }`

### Task 1.4：build 验证
- [ ] `xcodegen generate && xcodebuild -scheme MemoryPalaceIOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' build` 绿
- [ ] 探针 commit 单独："probe: [PROBE 贴纸] 全量 recognizer + superview 链 log"

### Task 1.5：粟粟真机复现 + 收 log
- [ ] 粟粟拿 kelivo worktree，Xcode 里选 MemoryPalaceIOS + iPhone 17 Air，Cmd+R
- [ ] 场景 1：进有贴纸对话 → 底栏"贴纸"按钮 → tap 贴纸 A（看到浮起）→ 贴 log
- [ ] 场景 2：紧接场景 1 → 尝试单指拖贴纸 A → 贴 log
- [ ] 场景 3：紧接 → 双指 pinch 贴纸 A → 贴 log
- [ ] 场景 4：tap 贴纸 B（观察第二次 tap 是否浮起）→ 贴 log
- [ ] 场景 5：退出编辑 → 长按贴纸 A 进编辑 → 再 tap 浮起 → 再拖 → 贴 log（对比进入路径差异）

## Phase 2：根因定论（读 log 判断）

### 判定分支树

| log 观察 | 诊断 | 进入哪个 fix 分支 |
|---------|------|-----------------|
| touchesBegan 收到但 touchesMoved 里 activeTouchCount > 1 | 机理 A：event.allTouches 误判 | F-A |
| handlePan `.began` 从未 fire + 祖先 UIScrollView `canCancelContentTouches = YES` | 机理 B：父 scroll view cancel touches | F-B |
| handlePan `.began` fire 了但立刻 `.cancelled` | 机理 B 的变种 | F-B |
| 祖先 UIScrollView 的 panGestureRecognizer 在用户拖动时 state 从 .possible 变 .began/.changed | 父 pan 真的被激活了（scrollDisabled 没禁） | F-B' |
| makeUIView 被反复调（每次 state 变化都调） | UIView 被 reparent / recreate | F-C |
| updateUIView 每帧都调 + contentHeight 抖动 | H4（contentHeight loop） | F-D |
| shouldRecognizeSimultaneouslyWith 收到**非预期**祖先 recognizer | ancestor 有新手势抢 touch | F-E |

### Phase 2 产出

- [ ] 写 postmortem 入 research doc 底部："根因定论"段落
- [ ] 附关键 log 证据行（不超过 30 行）
- [ ] 明确选哪个 fix 分支

## Phase 3：Fix 方案分支

### F-A：活跃 touch 误判
- 改用 `gestureRecognizer.numberOfTouches` 代替 `event.allTouches`，只数**自己这个 recognizer 当前 track 的 touches**
- 或：删 SingleFingerPanGesture 子类，换普通 `UIPanGestureRecognizer` + `maximumNumberOfTouches = 1`（UIKit 自己会在第 2 指到来时把 pan 进 `.failed`）
- 验证：真机复跑场景 2

### F-B：父 UIScrollView canCancelContentTouches
- 在 StickerCanvasGestureOverlay.makeUIView 里，main.async 后沿 superview 链找所有 UIScrollView
- 进入编辑模式时设 `canCancelContentTouches = false` + `delaysContentTouches = false`
- 退出编辑模式时恢复默认（两者都设 true）
- 实现放在一个小 helper：`AncestorScrollViewGuard`（弱引用祖先 scroll views，用 dismantleUIView 恢复）
- 验证：真机复跑场景 2/3/4

### F-B'：更 robust — 不改祖先属性，而给祖先 pan `require(toFail:)`
- 找到祖先 UIScrollView 的 panGestureRecognizer
- 让它 `require(toFail: stickerPan)` / `require(toFail: stickerPinch)`
- 风险：可能影响其他正常 scroll 行为（sidebar 滑动等）
- 若 F-B 有副作用才 fallback 到 B'

### F-C：UIView 被 reparent
- 修 StickerCanvasLayer / StickerCanvasGestureOverlay 的 SwiftUI 挂载，让 identity 稳定
- 具体 fix 待 log 给定再设计

### F-D：contentHeight 抖动
- 改 `Color.clear.frame(height: max(contentHeight, 1))` 为 `.frame(minHeight: ...)` 或解耦 sticker canvas 的 frame 和 contentHeight preference
- 具体 fix 待 log 给定再设计

### F-E：祖先新 gesture 抢 touch
- 具体 fix 待 log 给定再设计

## Phase 4：Fix 落地 + 验证

- [ ] 按 Phase 2 选定的 F-* 分支实施
- [ ] 真机复跑 Phase 1 的 5 个场景，全通过
- [ ] 回归测试：退出编辑模式后贴纸库正常、对话滚动正常、TabView（master）或 PagingContainer（kelivo）翻页正常、sidebar 手势正常
- [ ] 撤探针：`git revert <probe-commit>` 或手动 git log 清
- [ ] build 绿 + commit + push

## Phase 5：Memory 沉淀

- [ ] 如果 F-B 胜出，写一条 feedback memory：
  - name: "SwiftUI ScrollView scrollDisabled 不禁 cancelsTouchesInView"
  - 含：症状、机理、fix 路径、避坑规则（UIKit 手势在嵌套 SwiftUI ScrollView 里要手动管 `canCancelContentTouches`）

## 风险 + 回滚

- 探针 commit 独立，实测无效随时 `git revert`
- Fix commit 不和探针混，便于独立 review / revert
- 每个 F-* fix 失败时，立刻回 Phase 2 重新读 log 不要堆 fix

## 粟粟待确认 / 批注点

- [ ] 探针范围是否合适？有没有希望加/减的？
- [ ] 5 个测试场景是否合适？需要加"切换对话后再测"这类吗？
- [ ] 若根因是机理 B，F-B 方案（改祖先 scroll view 属性）能否接受？有没有更保守的偏好（F-B' require-to-fail 路线）？
- [ ] Phase 5 是否需要沉淀 memory？（默认我会做）
