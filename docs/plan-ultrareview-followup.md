# Plan: B17 / B18 / B19 ultrareview 后续 3 bug 修复

> 日期：2026-04-25
> 工作树：`.claude/worktrees/theme-kelivo-settings`
> 依赖 research：`docs/research-ultrareview-followup.md`
> 状态：**plan-only，粟粟批注后再 implement，don't implement yet**

---

## 0. 已确认方向（粟粟 2026-04-25）

| 决定 | 内容 |
|------|------|
| B19 方向 | **Option a：补一行 post**（最小改动，注释承诺的 defense-in-depth 生效）|
| Commit 方式 | **分 commit**（B17 / B18 / B19 各自独立 commit + push）|
| 顺序 | B17 → B18 → B19（逻辑独立，顺序无关，按 roadmap 编号）|

---

## 1. 目标

把 ultrareview 找出的 3 个 bug 修干净，roadmap 全部标 ✅。

**不做**：
- 不改 `triggerContextSummaryIfNeeded`（research 提到的潜在隐患，不在本 scope）
- 不重构记忆提取 / sidebar tag / 楼层切换主流程
- 不改 macOS 路径（这 3 处都跟平台无关，但 build 验证还是双平台都跑）

---

## 2. B17 — 记忆提取按 extractModel 价钱算

### 2.1 改动

`MemoryPalace/ViewModels/ConversationViewModel.swift:1024`：

```diff
- self?.commitBudgetSpend(providerManager: providerManager, model: model, usage: usage)
+ self?.commitBudgetSpend(providerManager: providerManager, model: extractModel, usage: usage)
```

注释（line 1021）"Spent 累加到主对话 provider（共用一个预算；和 gate 保持一致）"——表述可以保留，但加一句说明 `extractModel` 是实际计价模型：

```swift
// Spent 累加到主对话 provider 的全局预算池（共用一个预算；GlobalBudgetStore 不分 providerId）。
// 但 actualCost 必须用 extractModel（实际跑的廉价模型）查 PricingCatalog，
// 否则 Haiku token 数 × Opus 单价会超收 ~18×（ultrareview B17）。
```

### 2.2 风险与防守

#### R1. 主模型 / 提取模型在不同 provider？
- `cheapModel(providerManager:fallback:)` 通常返回**同 provider 内的廉价模型**（如 anthropic/Opus → anthropic/Haiku）
- `BudgetCalculator.actualCost(provider:modelId:usage:)` 同时取 provider ratio 跟 modelId 价格
- 同 provider 时 ratio 一致 → 改 model 只影响价格，不影响 ratio ✓
- 跨 provider（罕见）：ratio 也跟着变，但这才是正确行为（实际跑哪家就按哪家算）✓

#### R2. 预算 gate（L1000）保持用 `model`
research 已说明：gate 是预提交粗估，按主模型保守估值合理（用户在写下条消息前就该被挡）。**不改**。

#### R3. 历史 spend 已经被超收过了
当前 GlobalBudgetStore.spentUSD 数字偏高。**不在本 fix scope** —— 但 plan 末尾给个备注：粟粟可以手动在 API 设置里 reset spent，或者等月度自动滚动。

### 2.3 验证

- [ ] iOS Debug build 通过
- [ ] macOS build 通过
- [ ] 如果方便，跑一轮真机对话观察记忆提取触发后 `[PERF]` 日志里 spend 增量是不是符合 Haiku 单价

完成标准：build 通过 + 一行 diff 准。

### 2.4 commit message

```
fix(api): B17 记忆提取按 extractModel 计价 — 修 ~18× 超收

extractMemoriesIfNeeded 实际跑 cheapModel（Haiku）但 commitBudgetSpend
传 model（Opus），PricingCatalog 按 modelId 查价 → token 数 × 主模型单价
= 18.75× 实际成本（Opus + Haiku 组合）。预算 5% 即触发安全闸。

修：commitBudgetSpend 改传 extractModel。预算 gate（L1000）保持用 model
（提交前粗估，按主模型保守估值合理）。

ultrareview B17（bug_004）。roadmap 标 ✅。
```

---

## 3. B18 — Sidebar「加标签」漏 profileId

### 3.1 改动

#### 3.1.1 主修复 `SidebarView.swift:410-414`

```diff
  let item = FavoriteItem(
      conversationId: conversation.id,
      tagId: tag.id,
-     contentPreview: conversation.title
+     contentPreview: conversation.title,
+     profileId: profileId
  )
```

#### 3.1.2 防再撞：删 init 默认值 `ConversationTag.swift:50`

```diff
- init(nodeId: String? = nil, conversationId: String, tagId: String, contentPreview: String, profileId: String = "") {
+ init(nodeId: String? = nil, conversationId: String, tagId: String, contentPreview: String, profileId: String) {
```

### 3.2 删默认值前必须扫所有 caller

`grep -rn "FavoriteItem(" MemoryPalace/` 列出所有 init 调用。每一处都必须显式传 `profileId`，否则编译报错。

**plan 阶段就跑 grep**，列出 caller 清单：

```bash
grep -rn "FavoriteItem(" MemoryPalace/ --include="*.swift" | grep -v "FavoriteItem.swift\|//\|^\s*\*"
```

预期 caller（来自 research §B18）：
1. `SidebarView.swift:410` — **正在修**
2. `CardFlowView.swift:1456` FolderPickerSheet — 已正确（research 已确认传 profileId）
3. `CardFlowView.swift:1708` TagPickerPopover — 已正确

implement 前实测 grep 一遍，**有任何额外 caller 都要补传 profileId**。

### 3.3 风险

#### R1. 还有未发现的 caller
grep 兜底，编译错误兜底。删默认值后 build 失败 = 找到了漏点 → 补上 profileId。

#### R2. 可能存在的「marker = "" 的 init 用例」
比如某 stub / probe / migration 代码。如果有这种情况，实际给 profileId 传**当前 currentProfile.id** 还是 `""`？默认值消失会逼这个决策显式做出来，**好事**。

### 3.4 已存在的 orphan row 处理？

ultrareview 没要求清理 orphan。理论上可以 batch delete `FavoriteItem.profileId == ""` 的旧 row，但：
- 当前没人这么做（粟粟可能没用过这个入口，没有 orphan）
- 即使有，本次修复后新 row 都正确，旧 orphan 也无害（只占点空间）
- **不在本 fix scope** —— 备注末尾让粟粟决定是否 clean 一次

### 3.5 验证

- [ ] iOS Debug build 通过（**关键：删默认值后 build 不挂 = 所有 caller 都已正确**）
- [ ] macOS build 通过
- [ ] 模拟器/真机：sidebar 右键加标签 → 点对应 tag → 看到对话（之前看不到）

完成标准：build + 一次手动验证。

### 3.6 commit message

```
fix(ios,macOS): B18 Sidebar「加标签」漏 profileId 写孤儿 row

SidebarView.swift:410-414 创建 FavoriteItem 漏传 profileId，FavoriteItem.init
有 profileId: String = "" 默认值导致编译过但 row 写成 profileId=""，所有
按楼层 id 过滤的 fetch 永不匹配 → 加完标签看不到对话且 orphan 永远清不掉。

修：
1. SidebarView call site 加 profileId: profileId（SidebarView 已有 stored
   let profileId）
2. 删 FavoriteItem.init 的 profileId 默认值，强制所有 caller 显式传

ultrareview B18（bug_002）。roadmap 标 ✅。
```

---

## 4. B19 — `profileWillSwitch` 补 post

### 4.1 改动

`MemoryPalaceApp.swift` `switchTo` 函数（line 174-183）：

```diff
  func switchTo(_ profile: Profile) {
      guard profile.id != currentProfile.id else { return }
+     // 通知所有 observer 即将切换：clear 持有的 SwiftData ref 防 race
+     // （ContentView.id(currentProfile.id) 重建 subtree 是主防御，这是 defense-in-depth）
+     NotificationCenter.default.post(name: .profileWillSwitch, object: nil)
      UserDefaults.standard.set(profile.id, forKey: "lastProfileId")
      UserDefaults.standard.set(profile.userName, forKey: "userName")
      UserDefaults.standard.set(profile.assistantName, forKey: "assistantName")
      // 路线 B：container 不动，只翻 currentProfile。@Observable 触发 SwiftUI
      // view rebuild（ContentView 的 .id(currentProfile.id) 识别变化后重建整棵
      // subtree，@Query 用新 profileId predicate refetch）。无 race。
      currentProfile = profile
  }
```

### 4.2 post 时机

post 应该**在 `currentProfile = profile` 之前**（`willSwitch` 语义就是"即将切换"）。这给 6 处 observer 在 SwiftData 实际切换前清掉持有的 stale ref。

### 4.3 风险与防守

#### R1. 6 处 observer 的 cleanup 是否会出 bug
现在写好但从没 fire 过，一旦 fire 起来可能暴露 cleanup 代码 bug。

**防守**：
- 看一下 6 处 observer 的代码——清的都是 `selectedConversation = nil` / `memories = []` / `placedStickers = []` 之类的**赋空操作**，没有副作用调用，安全
- ContentView.id(currentProfile.id) 紧跟着触发 subtree 重建——即使 observer 出 bug，重建也兜底
- 真机切楼层验证：切前后界面正常 / 没 crash / SwiftData 状态对

#### R2. observer 顺序 / queue: nil 同步执行
6 处都用 `queue: nil`（同步在 post 调用线程执行）。post 在 MainActor `switchTo` 里，所以 observer 也在 main → 安全。

#### R3. addProfile 也走 switchTo（line 190）
新增 profile 调 `switchTo(profile)` 切过去 → post 也会触发 → cleanup 跑一次 → 跟普通切楼层一致。**不是 bug，是预期行为**。

#### R4. deleteProfile 不走 switchTo？
确认一下：`deleteProfile`（line 207+）逻辑里如果删的是当前 profile，会切到别的 profile 吗？**先 read 看**。

### 4.4 验证

- [ ] iOS Debug build 通过
- [ ] macOS build 通过
- [ ] 真机切楼层（`ProfileSwitcher` UI）→ 切过去界面正常 + 无 crash + 没出现"上一个楼层的对话还没消失"残影
- [ ] 真机加新楼层 → 自动切到新楼层 → 一样正常

完成标准：build + 真机切楼层 +新建楼层各 1 次。

### 4.5 commit message

```
fix(profile): B19 switchTo 补 post .profileWillSwitch — 让 6 个 observer 真生效

PR 加了 Notification.Name.profileWillSwitch + 6 处 observer（清 SwiftData
stale ref），但 ProfileManager.switchTo 从来没 post 过通知，注释承诺的
defense-in-depth 是死代码。当前靠 ContentView.id(currentProfile.id) 重建
subtree 兜底，无 user-visible bug 但下个改 .id() 的人会撞坑。

修：switchTo 在 currentProfile = profile 之前 post .profileWillSwitch。
post 走同步（queue: nil + MainActor）让 6 处 observer 在 SwiftData 切换前
跑完 cleanup。

ultrareview B19（bug_005）。roadmap 标 ✅。
```

---

## 5. 影响范围

### 必改文件
- B17：`MemoryPalace/ViewModels/ConversationViewModel.swift` (1 行)
- B18：`MemoryPalace/Views/SidebarView.swift` (1 行) + `MemoryPalace/Models/ConversationTag.swift` (1 行)
- B19：`MemoryPalace/MemoryPalaceApp.swift` (1 行)

### 不改
- `triggerContextSummaryIfNeeded`（B17 ultrareview 提到的潜在隐患，不在 scope）
- 6 处 observer cleanup 代码（B19 已写好，不动）

### 新增文件
- `docs/research-ultrareview-followup.md`（已写）
- `docs/plan-ultrareview-followup.md`（本文件）

### 改 docs
- `docs/PROJECT_ROADMAP.md`（B17/B18/B19 三行标 ✅）

---

## 6. 实施步骤

### Step 1：B17 implement + commit + push
- [ ] `ConversationViewModel.swift:1024` `model` → `extractModel` + 加注释
- [ ] iOS + macOS build
- [ ] roadmap B17 标 ✅
- [ ] commit + push

### Step 2：B18 implement + commit + push
- [ ] `grep -rn "FavoriteItem(" MemoryPalace/` 扫所有 caller
- [ ] `SidebarView.swift:413` call site 加 `profileId: profileId`
- [ ] `ConversationTag.swift:50` 删 `profileId: String = ""` 默认值
- [ ] iOS + macOS build（**编译通过 = 所有 caller 都已正确**）
- [ ] roadmap B18 标 ✅
- [ ] commit + push

### Step 3：B19 implement + commit + push
- [ ] read `deleteProfile` 确认是否走 switchTo（plan §4.3 R4）
- [ ] `MemoryPalaceApp.swift:182` 之前加 `NotificationCenter.default.post(name: .profileWillSwitch, object: nil)`
- [ ] iOS + macOS build
- [ ] roadmap B19 标 ✅
- [ ] commit + push

### Step 4：真机验证（一并做）
- [ ] B17：跑一轮记忆提取，console 看 spent 增量是不是按 Haiku 算（可选）
- [ ] B18：sidebar 右键加标签 → tag 列表能看到对话
- [ ] B19：切楼层 + 新增楼层各一次，界面正常无 crash
- [ ] 不通过的 case 立刻 patch

---

## 7. 完成定义

1. B17/B18/B19 各自独立 commit + push 到 origin
2. iOS Debug + iOS Release + macOS 三种 build 全通过
3. roadmap B17/B18/B19 三行标 ✅
4. （可选）真机切楼层 + 加标签 + 记忆提取各 1 次手动验证

---

## 8. Todo Tracker

- [x] 1. B17 修 + build + commit + push（commit `89e1170`）
- [x] 2. B18 grep + 修 + 双 build + commit + push（commit `1f8da38`，4 caller 全 grep 验证）
- [x] 3. B19 read deleteProfile + 修 + build + commit + push（commit `8a929ae`，deleteProfile 走 switchTo(profiles[0]) 自动覆盖）
- [x] 4. roadmap 三行标 ✅
- [ ] 5. （可选）真机三场景验证 — 留给粟粟自测

---

## 9. 状态

✅ **关档 2026-04-25** — 三 commit 全 push，roadmap B17/B18/B19 全 ✅。可选真机验证留 Susu 自测。
