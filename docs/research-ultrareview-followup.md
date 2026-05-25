# Research: B17 / B18 / B19 ultrareview 后续 3 bug

> 日期：2026-04-25
> 工作树：`.claude/worktrees/theme-kelivo-settings`
> 触发：ultrareview `bug_004` `bug_002` `bug_005`，3 个独立小 bug 合并 research。

---

## B17 — 记忆提取按主模型价钱算

### 现状（已核对源码）

`ConversationViewModel.swift:982-1066` `extractMemoriesIfNeeded`：

| 行号 | 代码 | 用的 model |
|------|------|-----------|
| L989 | `let extractModel = cheapModel(providerManager:fallback: model)` | 廉价（Haiku）|
| L1000 | `backendAgentBlockedByBudget(model: model, ...)` 预算 gate | **主模型 Opus**（粗算 OK）|
| **L1011-1016** | `router.sendNonStreaming(model: extractModel, ...)` | **廉价 Haiku 实际跑** |
| **L1024** | `commitBudgetSpend(providerManager:..., model: model, usage: usage)` | **主模型 Opus 写账** ❌ |

`commitBudgetSpend` (L1312-1325) → `BudgetCalculator.actualCost(modelId: model.modelId, usage: usage)` → `PricingCatalog.price(for: modelId)` 按 modelId 查价。

**实际调用是廉价模型，记账查的是主模型单价**，token 数 × 主模型价 → 写虚高的 spend。

### 数学（Opus 主 + Haiku 提取，参考 ultrareview）

`Models/ModelPricing.swift`：
- `claude-opus-4-7`: input $15/MTok, output $75/MTok
- `claude-haiku-4-5`: input $0.8/MTok, output $4/MTok

某次提取 `usage = (input: 3000, output: 800)`：
- 真实成本（Haiku）：3000/1e6 × 0.8 + 800/1e6 × 4 = $0.0056
- 当前记账（按 Opus 价）：3000/1e6 × 15 + 800/1e6 × 75 = $0.105
- **18.75× 超收**

### 影响

- 5 块预算用户 **5% 实际成本 → 触发安全闸**
- API 设置里"已花费"显示约 **20× 实际 Anthropic 账单**
- 每轮对话都触发记忆提取 → 误差累加

### 修法（一行）

```swift
// L1024 ConversationViewModel.swift
self?.commitBudgetSpend(providerManager: providerManager, model: extractModel, usage: usage)
//                                                          ^^^^^^^^^^^^^^^^^^^^^^^ 改这里
```

L1000 的预算 gate 用 `model` 不动（提交前粗估，按主模型保守估值合理）。

### 预算 gate 的注释 vs. 行为

L1021 注释："Spent 累加到主对话 provider（共用一个预算；和 gate 保持一致）"

**注释跟现实矛盾**：`GlobalBudgetStore.shared.commitSpend(amount)` (APIProvider.swift:564) 已经是全局池，不分 provider id。"共用预算"是 GlobalBudgetStore 的职责，不是 commitBudgetSpend 用哪个 model 决定的。L1024 改 `extractModel` 后预算还是全局共用，注释依然成立。

### ultrareview 还提到的潜在隐患

L1069+ `triggerContextSummaryIfNeeded` 走 `cheapModel(...)` 但**没 commit spend**（只调 `ContextSummarizer.summarize`）。如果以后给它加 commitBudgetSpend，要避免同样的坑——**当前不在 B17 scope，要做时单独修**。

---

## B18 — Sidebar「加标签」漏 profileId

### 现状（已核对源码）

`Views/SidebarView.swift:407-420`：
```swift
Menu("加标签") {
    ForEach(tags) { tag in
        Button(action: {
            let item = FavoriteItem(
                conversationId: conversation.id,
                tagId: tag.id,
                contentPreview: conversation.title
                // ↑ 漏 profileId ↓ 用 init 默认值 ""
            )
            modelContext.insert(item)
        }) { ... }
    }
}
```

`Models/ConversationTag.swift:50` `FavoriteItem.init`：
```swift
init(nodeId: String? = nil, conversationId: String, tagId: String, contentPreview: String, profileId: String = "")
//                                                                                          ^^^^^^^^^^^^^^^^^^^^^ 默认空串
```

→ 写入的 row `profileId == ""`。

### 所有 FavoriteItem fetch 都按 profileId 过滤（路线 B）

| 文件 | 行号 | predicate |
|------|------|-----------|
| SidebarView.swift | 1043-1045 | `item.tagId == id && item.profileId == pid` |
| SidebarView.swift | 1289-1290 | `item.profileId == pid` |
| SidebarView.swift | 1447-1450 | `item.profileId == pid && item.tagId == tid` |
| ConversationViewModel.swift | 680, 703 | profileId 过滤 |
| ImportSupport.swift | 196, 235 | profileId 过滤 |
| MemoryPalaceApp.swift | 220 | profileId 过滤（`deleteProfile` cascade）|

→ orphan row（`profileId == ""`）跟所有 fetch 永不匹配 → **加完标签看不到对话** + **永远清不掉**（删楼层 cascade 也按 profileId 过滤）。

### 其他 tagging 入口对照（已正确）

- `CardFlowView.swift:1456` FolderPickerSheet → 传 `profileId: profileId` ✅
- `CardFlowView.swift:1708` TagPickerPopover → 传 `profileId: profileId` ✅

→ **只有 SidebarView 这一处漏**。

### SidebarView 自己有 profileId 吗？

`SidebarView.swift:37` `let profileId: String`，init 接收（line 49+57）。**call site 直接拿 `profileId` 即可**。

### 修法

#### 主修复（一行）：call site 加 profileId

```swift
let item = FavoriteItem(
    conversationId: conversation.id,
    tagId: tag.id,
    contentPreview: conversation.title,
    profileId: profileId            // ← 加这行
)
```

#### 顺手防再撞（推荐）：删 init 的默认值

```swift
// Models/ConversationTag.swift:50
init(nodeId: String? = nil, conversationId: String, tagId: String, contentPreview: String, profileId: String) {
//                                                                                          ↑ 删掉 = "" 默认值
```

让所有 caller 强制传 profileId，编译期捕获遗漏。

**风险**：删默认值是 breaking change，要扫所有 caller 一遍补 profileId。

### 扫一下 FavoriteItem.init 全部 caller

```bash
grep -rn "FavoriteItem(" MemoryPalace/ | grep -v "\.swift:"
```

需要我跑这个 grep 才能列出全部 caller。Plan 阶段执行。

---

## B19 — `profileWillSwitch` 死代码（nit）

### 现状（已核对源码）

**定义**：`MemoryPalaceApp.swift:619` `static let profileWillSwitch = Notification.Name(...)`

**6 个 observer**：
- `ViewModels/StickerViewModel.swift:77`
- `ViewModels/ConversationViewModel.swift:52`
- `Views/SidebarView.swift:650`
- `Views/MemoryPanelView.swift:185`
- `Views/MemorySettingsTab.swift:198`
- `Views/MemorySettingsTab.swift:548`

**post site**：`grep -rn "post.*profileWillSwitch\|post(name: .profileWillSwitch" MemoryPalace/` → **0 处**。整个 codebase 没人 post 这个通知。

### `switchTo` 现状（MemoryPalaceApp.swift:174-183）

```swift
func switchTo(_ profile: Profile) {
    guard profile.id != currentProfile.id else { return }
    UserDefaults.standard.set(profile.id, forKey: "lastProfileId")
    UserDefaults.standard.set(profile.userName, forKey: "userName")
    UserDefaults.standard.set(profile.assistantName, forKey: "assistantName")
    // 路线 B：container 不动，只翻 currentProfile。@Observable 触发 SwiftUI
    // view rebuild（ContentView 的 .id(currentProfile.id) 识别变化后重建整棵
    // subtree，@Query 用新 profileId predicate refetch）。无 race。
    currentProfile = profile
}
```

**没 post 通知**。靠 `@Observable` + `ContentView.id(currentProfile.id)` 重建 subtree 兜底——目前实际有效。

### 注释 vs. 现实矛盾

- `MemoryPalaceApp.swift:614-617` 注释："ProfileManager.switchTo 即将切换 currentProfile + container 之前发出" — **谎言**
- `ConversationViewModel.swift:40` 注释："切楼层前 post .profileWillSwitch，这里 observer 把 VM 持有的所有 SwiftData 实例 ref 清空" — **未实施**
- `StickerViewModel.swift:69` 注释："post .profileWillSwitch 时同步清所有 @Model ref" — **未实施**

### 当前无 user-visible bug

路线 B 重构后 `ContentView.id(currentProfile.id)` 触发 subtree 全重建，所有 `@State` / `@Query` 自然重置。observer 是 dead defense-in-depth。

### 风险

下一个改 `.id(currentProfile.id)` 的人（觉得是 over-rendering 优化）会撞上原本被 observer 应该防住的 race，注释又说"已经防住"——**误导陷阱**。

### 修法 2 选 1

**Option a：补一行 post（推荐）**

```swift
// MemoryPalaceApp.swift switchTo 内，在 currentProfile = profile 之前
NotificationCenter.default.post(name: .profileWillSwitch, object: nil)
currentProfile = profile
```

- 优点：注释承诺的行为生效，**真正的 defense-in-depth**
- 优点：6 处 observer 不再是死代码，将来若 `.id(...)` 改了，race 仍被防住
- 改动：1 行

**Option b：删死基础设施**

- 删 `Notification.Name.profileWillSwitch` 定义（1 处）
- 删 6 处 observer（每处 ~10 行的 cleanup block + 注释）
- 改 4 处误导注释（说明实际机制是 `ContentView.id(currentProfile.id)` 重建）
- 改动：~50 行

倾向 **a**——成本 1 行 vs. b 的 50 行，且实际加固 race 防御不会是负担（observer 已写好，post 触发它们就生效）。粟粟选。

---

## 三 bug 互相独立

| Bug | 改文件 | 改动量 |
|-----|--------|--------|
| B17 | `ConversationViewModel.swift:1024` | 1 行（`model` → `extractModel`） |
| B18 | `SidebarView.swift:413` + `ConversationTag.swift:50` | 主修 1 行；顺手 1 个默认值删 |
| B19 | `MemoryPalaceApp.swift:182` (option a) 或全删 (option b) | 1 行 (a) / ~50 行 (b) |

可以**串行 implement** 各自 commit，也可**单 commit 收三件**。Plan 阶段决定。

---

## 文件参考

- `MemoryPalace/ViewModels/ConversationViewModel.swift:982-1066, 1024, 1312-1325` — B17
- `MemoryPalace/Views/SidebarView.swift:407-420, 37, 1043-1450` — B18
- `MemoryPalace/Models/ConversationTag.swift:50` — B18 init 默认值
- `MemoryPalace/MemoryPalaceApp.swift:174-183, 619` — B19 switchTo / 通知名
- `MemoryPalace/ViewModels/{StickerViewModel,ConversationViewModel}.swift` `Views/{SidebarView,MemoryPanelView,MemorySettingsTab}.swift` — B19 6 处 observer

---

*research-only。粟粟拍板：B19 选 a 还是 b？三 bug 单 commit 还是分 commit？*
