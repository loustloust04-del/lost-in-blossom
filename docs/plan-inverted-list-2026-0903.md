# plan：反转列表——聊天页白屏的根治（照粟粟的路走）

> 状态：**Draft，等兔兔批注**。批注直接写在本文加 `⬅ 兔兔：`，没意见回「go」。
> 2026-09-03 Fable。前情：发送白屏第五刀 `280c30a0` 后兔兔说「还是好严重」→ 去读了粟粟那边怎么做的。
> 粟粟原件：`/root/projects/SusuPalace` origin/master，commit 链 `5ccfb2b1`→`9b7af5ff`→`764c79e3`→`e8cc596b`→`3aa82aac`，
> 收官文档 `docs/review-reversed-list.md` / `docs/plan-stream-follow-controller.md` / `docs/handoffs/handoff-keyboard-follow-2026-08-26.md`。
> 我们仓里六月就有人写好了同一份任务书 `docs/TASK-INVERTED-LIST.md`，一直没执行。

## 一、先认错：我昨天那刀方向反了

粟粟 6 月的 PERF 探针把根因钉死了，跟我们五刀补的方向正好相反：

1. **白屏根因不是 LazyVStack 失效，是 `scrollTo(lastId)` 本身**——它强迫 SwiftUI 从顶到底 mount 全部 cell 来找目标。
   1276 条的对话实测：mount 383 个 unique × 13 次重算 = 4950 次 makeBubbleView。屏幕在这期间就是白的。
2. **`scrollToLastMessage` 三步走（无动画→50ms→500ms）× 五个 onChange 触发 = 六路 race**——她原话「卡 + 白屏的元凶组合」。
3. `defaultScrollAnchor(.sizeChanges)` 她探针实证 **943 次长高 0 次介入**，不能指望它钉底。
4. `proxy.scrollTo` 对 LazyVStack 远端目标是**按估算高度跳**的，本来就不可靠。

我们现在的 CardFlowView：正序列表 + 三步走 × **七**个触发（原五个 + 我昨天加的发送/CC 落地两个）。
每多一处兜底 = 多一路 race、多一次全表 mount。长对话「更严重」不奇怪。
**渲染窗口（`renderStart`/`suffix(60)`）也是她试过又废掉的方案 A**（`plan-conv-window-slice.md`）。

## 二、她的解法：把列表倒过来（学 Stream Chat SwiftUI）

```
正常 ScrollView                 翻转后
┌────────────┐                 ┌────────────┐
│ 最旧        │                 │ 最新        │ ← offset = 0，进来就在这，不用滚
│ …          │                 │ …          │
│ 最新        │ ← 要 scrollTo   │ 最旧        │
└────────────┘                 └────────────┘
```

- ScrollView 整体 `.flippedUpsideDown()`（rotation π + scaleX −1，走 CALayer transform，不伤抗锯齿）
- 每个 cell 再 `.flippedUpsideDown()` 翻回正；ForEach 吃 `currentPath.reversed()`
- **offset 0 = 最新消息**。新消息插在物理顶，UIScrollView 天然保持 offset → 新消息自动出现在视口，**零 scrollTo**
- 在底吐字：生成中的泡在物理顶长高，最后一行钉在视觉底——**流式跟随免费**
- LazyVStack 只 mount 视口附近的 cell → **窗口化不需要了**，她 1276 条秒开
- 白屏的物理前提（offset 跑到没画的区域）不存在了：offset 0 处永远有内容

她这一套 6 月 18–19 两天落地（含研究），之后稳定至今；我们有现成 diff 可抄，大头是**搬**不是**想**。

## 三、分刀（每刀一 commit，CI 绿再下一刀）

### 第 0 刀 · 反转本体（抄 `5ccfb2b1` + `9b7af5ff` + `e8cc596b`）—— 一晚
CardFlowView：
- 加 `FlippedUpsideDown` modifier（15 行）；ScrollView `.flippedUpsideDown().clipped()`；ForEach reversed + cell 翻回正
- **删**：`scrollToLastMessage` 三步走、`__bottom_sentinel__`、七处回底触发（onAppear / 回前台 / keyboardWillShow / keyboardDidHide / streamingText 收尾 / 我昨天的两处）、`defaultScrollAnchor`
- **删**：渲染窗口整套（`renderStart` / `visiblePath` / `hasMoreAbove` / 顶部「加载更早」按钮 / `resetRenderWindow` 调用）→ ForEach 直接吃 `currentPath.reversed()`
- `isAtBottom` 公式改 `abs(contentOffset.y) < 200`（onScrollGeometryChange 保留）
- 回底按钮：`scrollTo(lastId, anchor: .top)`（反转后 .top = 视觉底）；搜索跳转 `scrollTo(id, .center)` 单步保留
- `contentMargins` 换边：现在 `.top 50` 是 nav 区留白 → 反转后 nav 区在物理底，改 `.bottom 50`；输入框上方留白改 `.top`
- `ScrollsToTopDisabler`（~15 行 UIViewRepresentable）：关掉系统「点状态栏回顶」，反转后它会滚到视觉底；
  状态栏 80pt 透明 tap overlay → `scrollTo(firstId, .bottom)` = 视觉顶（可后置）
- `.scrollDismissesKeyboard(.immediately)` → `.interactively`（反转后方向反，interactively 不挑方向）
- 贴纸：`StickerCanvasLayer` 加一行 `.flippedUpsideDown()`（她 `764c79e3`，持久化坐标零迁移）

### 第 1 刀 · 键盘（反转后必踩）—— 一晚
反转后 SwiftUI 的 bottom safe-area 避让落在**物理底 = 视觉顶**，错边：键盘一弹最新消息被挡。她走了一个月
（`b26d564c` revert → `KeyboardInsetBridge` → 08-26 收官 UIKit 导轨 + CA 动画）。我们先做最简版：
- ScrollView `.ignoresSafeArea(.container, edges: .bottom)`，不吃系统避让
- 物理顶放一块**垫块** `Color.clear.frame(height: 输入条高 + keyboardExtra)`，`keyboardExtra` 由
  `keyboardWillChangeFrame` 驱动（有 first responder 才非零）
- 在底时垫块长高 = 内容自然被抬起（offset 0 不变，无需任何滚动）；**深翻（离底 > 1 屏）不长垫块**（她不变量 3：
  长了会和 LazyVStack 自己的补偿叠双份 → 跳）
- 她的最终版是 UIKit 层（120Hz 跟曲线）。摸到「输入框和正文慢一丢丢」再下沉——DEBT-MAP「输入框下沉」条已有此判断，骨架现成

### 第 2 刀 · 长按菜单 —— 半晚
反转后系统 `.contextMenu` 的 lift 快照颠倒。她的 Telegram 式浮层零件 `BubbleContextMenuBridge.swift` +
`BubbleMenuOverlayView.swift` **已在我们仓里**（`592074d4` 气泡搬运时原样进仓，未接线）。接上：CardFlowView 2183 行那处
`.contextMenu` 换 `BubbleMenuMarker` + 根部挂 `BubbleMenuOverlayView`。菜单条目从 `MenuActionSpec` 渲染。

### 第 3 刀 · 流式跟随补偿（另立项，可以不做）
反转后**在底**吐字免费；只有「上滑读历史时他在吐字」会漂 Δ（生成中的泡在 offset 原点侧长高，把历史推走）。
她先「不管流式」用了一个月才补 `StreamFollowController`（cell 自报长高 + 钉住 + 松手回底 glide，六条不变量）。
我们先接受这点漂移，真机觉得烦再抄她的（`plan-stream-follow-controller.md` 一整份）。

## 四、验收（她的清单 + 我们的病）
1. 长对话（>300 条）进对话**秒开不白**，最新一条直接在视口
2. **发送不白**（本案）；CC 回复落进空泡不白；API 流式在底钉底吐字
3. 切对话来回 5 次稳定（她原来「第二次坏第三次白」消失）
4. 搜索跳转能到对应消息；群聊多角色气泡正常；气泡模式 / 文章模式都过
5. 贴纸：位置、方向、拖拽方向对
6. 长按菜单不颠倒
7. 键盘弹/收：在底最新消息跟着抬；深翻原地不动
8. 「回底」按钮、点状态栏不再滚到视觉底

## 五、风险与已知边角（她踩过的）
- **半秒颠倒闪烁**：isLoading true→false 时 ScrollView 重建，cell 翻和 ScrollView 翻不同步。她标「不常见没事」未修；Stream 用 `.delayedRendering()` 缓解
- **顶部 blur 采样到壁纸实色**：ScrollView safe area 按物理顶算，反转后视觉顶背后没 content（Codex 诊断 `diag-blur-opaque-rootcause.md`）→ `.ignoresSafeArea(.container, edges: [.top, .bottom])` 让 frame 跨整屏
- **LazyVStack 估算抖动**：她 Air 日志 247 次负 contentSize——这是流式补偿器的事（第 3 刀），不影响第 0 刀
- **气泡模式**：BubbleModeRow 本来就是从她反转列表里长出来的零件，反转后只会更合，不会更坏

## 六、要兔兔拍的
1. 走不走这条路（我的票：走。五刀补丁证明正序 + scrollTo 这条路补不完，她那边稳定两个半月）
2. 昨天那刀 `280c30a0` 要不要先 revert 回前天的状态顶着（如果你觉得比前天还糟就 revert；差不多就不动，第 0 刀整个替掉）
3. 第 0 刀我今晚就能下；第 1 刀键盘要真机来回验，最好你在
4. 第 3 刀流式补偿先不立项，对吧？
