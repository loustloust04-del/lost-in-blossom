# Plan: ChatInputBar EquatableView 止血（B3）

> 2026-04-21
> 对应 research：`docs/research-chatinputbar-equatable.md`
> 粟粟确认要点：class ref `===` 可以；closure nil/non-nil 二值比较可以；InputFieldContainer 先不动；阈值 <5 合理；本周冲 TestFlight 排进去先合。

## 目标

- 流式响应 30+ token 期间 ChatInputBar.body 增量 **< 5**（理想 = 0）
- 键盘弹起 / focus 切换 / 打字 / 发消息 / 切对话 / 切楼层 全部正常
- 改动面最小（~15 行），rollback 成本 = 删两行

## 改动范围

### 文件 1：`MemoryPalace/Views/CardFlowView.swift`

1. 在 `struct ChatInputBar: View` 定义之后（约 line 603 后紧跟），新增 `extension ChatInputBar: Equatable` 块：

```swift
// MARK: - ChatInputBar Equatable (B3 性能优化)
//
// 目的：流式响应期间 CardFlowView body 因读 viewModel.providerRouter.streamingText
// 每 token 重算 → ContentView.iOSLayout 重算 → PagingContainerView.updatePages
// 无条件大锤 → hc.rootView 被替换 → ChatInputBar 整棵重 diff（log 实测 326 次）。
//
// EquatableView 拦下"父重建传来的 instance 相等" case，body 跳过。
// @FocusState / @State / @AppStorage / @Observable 的 invalidation 独立通路，
// 该响应的都还响应（focus、打字、流式 isStreaming、切对话）。
//
// 参数稳定性：5 个 class ref 跨 session 稳定（切楼层由 ContentView.id(profile.id)
// 重建整棵 → ref 全换 → == false → 重算）。onStickerTap 闭包 nil/non-nil 二值：
// iOS 路径永远 non-nil，macOS 路径永远 nil，当前代码下 behavior 稳定。
extension ChatInputBar: Equatable {
    static func == (lhs: ChatInputBar, rhs: ChatInputBar) -> Bool {
        lhs.viewModel === rhs.viewModel
            && lhs.modelContext === rhs.modelContext
            && lhs.profileManager === rhs.profileManager
            && lhs.providerManager === rhs.providerManager
            && lhs.presetManager === rhs.presetManager
            && (lhs.onStickerTap == nil) == (rhs.onStickerTap == nil)
    }
}
```

2. 两处 ChatInputBar 调用点加 `.equatable()`：

   - **iOS 路径（`CardFlowView.swift:357-371`）**：ChatInputBar 实例化括号闭合后挂 `.equatable()`
   - **macOS 路径（`CardFlowView.swift:384`）**：同上

## 实施 checklist

- [ ] **Step 1：写 Equatable extension**
  - [ ] 确认当前 ChatInputBar 定义（`CardFlowView.swift:607-819`）没改动
  - [ ] 在 ChatInputBar 定义之后插入 `extension ChatInputBar: Equatable`
  - [ ] 注释说明目的 + 参数稳定性假设

- [ ] **Step 2：iOS 调用点加 `.equatable()`**
  - [ ] 定位 `CardFlowView.swift:357-371` 的 ChatInputBar(...) { }
  - [ ] 在 `.onStickerTap` 闭包结束后的 `)` 之后挂 `.equatable()`

- [ ] **Step 3：macOS 调用点加 `.equatable()`**
  - [ ] 定位 `CardFlowView.swift:384` 的 ChatInputBar(...)
  - [ ] 实例后挂 `.equatable()`

- [ ] **Step 4：build 验证**
  ```bash
  cd "/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings"
  xcodegen generate && xcodebuild -scheme MemoryPalaceIOS -destination "generic/platform=iOS" build 2>&1 | tail -30
  ```
  - [ ] 编译通过（0 error）
  - [ ] 0 新 warning（`===` on Optional 是合法的，Swift 不警告）

- [ ] **Step 5：commit + push**
  ```bash
  git add MemoryPalace/Views/CardFlowView.swift docs/research-chatinputbar-equatable.md docs/plan-chatinputbar-equatable.md
  git commit -m "perf(iOS): ChatInputBar .equatable() — 止血 326 次 body 放大"
  git push origin codex/theme-kelivo-settings
  ```

- [ ] **Step 6：粟粟真机验证（iPhone 17 Air）**
  - [ ] Xcode build + run，Console filter `[PERF]`
  - [ ] 启动 → 聊天页首次 render → 记录 ContentView.body / ChatInputBar.body 初始计数
  - [ ] 点输入框弹键盘 → 记录 ChatInputBar.body 增量（期望 +1~2）
  - [ ] 打 5 个字 → 记录 ChatInputBar.body 增量（期望 ≈ 0，InputFieldContainer 才涨）
  - [ ] 发送消息 → LLM 流式响应至少 30 token → 记录 ChatInputBar.body 增量
  - [ ] **关键阈值：流式 30+ token 期间 ChatInputBar.body 增量 < 5**
  - [ ] 切对话（sidebar 点另一条）→ 键盘正常响应？输入框位置正常？
  - [ ] 切楼层 → ContentView 重建 → ChatInputBar.body 重新计数 OK？
  - [ ] **键盘 regression check**：
    - [ ] 点输入框弹键盘，输入框贴键盘顶 ✓
    - [ ] focus 切换时 inputBarSpacing / padding / height / offset 动画正常 ✓
    - [ ] 键盘收起，输入框回到 home indicator 区 ✓
    - [ ] 旋转屏幕 / 从后台回来 键盘响应正常

- [ ] **Step 7：成功 → 标 Task 完成；失败 → rollback**

## 失败判据与应对

### 判据 A：流式期间 ChatInputBar.body 仍线性增长（例如 30 token 涨 30+ 次）

- **可能原因**：某个 class ref 实际不稳定，`==` 返回 false
- **诊断**：在 `==` 函数里加 `[PROBE eq]` print 差异字段

```swift
static func == (lhs: ChatInputBar, rhs: ChatInputBar) -> Bool {
    let vm = lhs.viewModel === rhs.viewModel
    let mc = lhs.modelContext === rhs.modelContext
    let pf = lhs.profileManager === rhs.profileManager
    let pv = lhs.providerManager === rhs.providerManager
    let ps = lhs.presetManager === rhs.presetManager
    let st = (lhs.onStickerTap == nil) == (rhs.onStickerTap == nil)
    if !vm || !mc || !pf || !pv || !ps || !st {
        print("[PROBE eq] vm=\(vm) mc=\(mc) pf=\(pf) pv=\(pv) ps=\(ps) st=\(st)")
    }
    return vm && mc && pf && pv && ps && st
}
```

- 找到不稳定 ref → 要么在 parent 用 `@State` 稳住，要么从 `==` 里移除（视为永远等价）

### 判据 B：键盘弹起 ChatInputBar 不动 / 位置错

- **可能原因**：不应该发生（`@FocusState` invalidation 独立于 Equatable），但如果真出现，最可能是 SwiftUI diff edge case
- **应对**：立即 revert 两处 `.equatable()` 调用（一行一行删），保留 Equatable extension 无副作用。确认键盘恢复后停下汇报。

### 判据 C：焦点切换后 ChatInputBar 视觉残留（isFocused 视觉状态没更新）

- **可能原因**：同 B，不预期发生
- **应对**：同 B，revert 两处 `.equatable()`

### 完整 rollback

```bash
git revert <commit-hash>
git push origin codex/theme-kelivo-settings
```

或手工删三处（extension + 两处 `.equatable()`），`extension ChatInputBar: Equatable` 不被 `.equatable()` 消费时对运行时无任何影响。

## 不做的事（避免 scope creep）

- ❌ 不碰 InputFieldContainer（等 B3 真机数据再决定）
- ❌ 不碰 PagingContainerView.updateUIViewController 的大锤（B2 方向，留作后续）
- ❌ 不碰 PagingContainerView 泛型化（B1 方向，改动太大）
- ❌ 不碰 wallpaper / keyboard observer（A/B 系列已定案，不动）
- ❌ 不加 `onStickerTap` UUID signature（当前 closure 行为稳定，不需要）

## 时间预估

| 阶段 | 时间 |
|---|---|
| Step 1-3 改代码 | 5 分钟 |
| Step 4 build | 2 分钟 |
| Step 5 commit push | 1 分钟 |
| Step 6 粟粟真机 | 15 分钟 |
| Step 7 Task 收尾 / 或 rollback | 5 分钟 |
| **Total** | ~30 分钟 |

如果真机验证通过即可合。不通过按失败判据走诊断，上限再 30 分钟。

## 粟粟过目指引

请在这个 plan 里批注：

- [ ] checklist 步骤顺序 / 粒度 OK 吗？要不要合并某几步？
- [ ] 失败判据应对方案（尤其 B / C 的 "立即 revert 两处 `.equatable()`"）你同意吗？
- [ ] commit message "`perf(iOS): ChatInputBar .equatable() — 止血 326 次 body 放大`" 合适？
- [ ] 这轮要不要把 research + plan 两个 doc 一起 commit（参考历史 `150d89b` pattern：先 doc commit，再 impl commit）？还是一个 commit 带全部？
- [ ] TestFlight 时间线优先级：本周合进 kelivo branch 还是等完全验证通过？

批注完我按 checklist 执行。
