# Research: 切楼层 crash 路线 B —— 单 ModelContainer + profileId filter

> 2026-04-22 · 路线 A (commit `4f84927`) 验证：**真机 17 Air Debug build 表面 OK，模拟器仍 fatal** → race 本质没修，只是真机 timing 侥幸。
> 粟粟反馈："别的真机我还没试过呢，万一也出问题了怎么办"
> 决策：走架构重构彻底根治。

## 1. 为什么路线 A 不彻底

- 路线 A 核心修法：`ProfileManager.isSwitchingProfile` 过渡期替身 + `retainedOldContainers` 保活旧 container 5 秒
- 模拟器 iOS 26.4 Debug build 仍 crash：`_SwiftData_SwiftUI → EmbeddedDynamicPropertyBox.update → DynamicViewList.updateValue` fatal
- stack trace 表明 **SwiftUI view graph update 路径里，@Query-backed ForEach 访问已 reset 的 @Model**
- 即使 `retainedOldContainers` 强引用旧 container，**SwiftData 的 `.modelContainer(newContainer)` env swap 仍会 reset 旧 context 的 instances**（不依赖 ARC）
- 真机 17 Air 没 crash = race window 窄到赶上 dismount；**不代表其他真机 / iOS 小版本也窄**

**本质根因**：多 ModelContainer 切换与 SwiftUI + SwiftData env update cycle **结构性不兼容**。Apple 的 SwiftData 设计假设 app lifetime 内 container 相对稳定，frequent swap 踩的都是未记载的 timing bug。

xcdoc / Apple 官方**没有** "如何安全切 ModelContainer" 的指南。

## 2. 路线 B 架构：单 container + profileId filter

### 2.1 核心思路

- App 启动后创建 **1 个** `ModelContainer`，覆盖 app lifetime 不 swap
- 所有 `@Model` entity 加 `profileId: String` 字段（已有 5 个 + 要加 7 个）
- 所有 `FetchDescriptor<X>` / `@Query<X>` 在 predicate 里加 `$0.profileId == currentProfileId`
- 所有 `modelContext.insert(obj)` 时设 `obj.profileId = currentProfileId`
- `ProfileManager.switchTo` 改为**只翻 `currentProfile`**，container / modelContext 不动
- SwiftUI view graph 连续 stable —— 切楼层只是 `@Observable currentProfile.id` 变，`@Query` refetch（带 new profileId predicate），**无 container teardown，无 @Model reset，无 race**

### 2.2 Master 已经是半成品

- `Memory.profileId`、`MemoryNote.profileId`、`PlacedSticker.profileId`、`StickerAsset.profileId`、`WorldBook.profileId` **已有**
- 当前架构下这几个 profileId 字段**冗余**（每 profile 自己 store 自己 profileId，filter 是 no-op）
- 路线 B 只是把已有的 profileId 字段真正用起来 + 给缺的 entity 也加

### 2.3 改动清单

#### A. `@Model` schema 加字段（7 个 entity）

| Entity | 当前状态 | 改动 |
|---|---|---|
| `Memory` | ✅ 已有 profileId | — |
| `MemoryNote` | ✅ 已有 | — |
| `PlacedSticker` | ✅ 已有 | — |
| `StickerAsset` | ✅ 已有 | — |
| `WorldBook` | ✅ 已有 | — |
| **`Conversation`** | ❌ | 加 `var profileId: String = ""` |
| **`MessageNode`** | ❌ | 加 `var profileId: String = ""` |
| **`UserCard`** | ❌ | 加 `var profileId: String = ""` |
| **`ConversationTag`** | ❌ | 加 `var profileId: String = ""` |
| **`FavoriteItem`** | ❌ | 加 `var profileId: String = ""` |
| **`ImportRecord`** | ❌ | 加 `var profileId: String = ""` |
| **`ImportConversationChange`** | ❌ | 加 `var profileId: String = ""` |

SwiftData 对现有 store 加字段：set default value 就是自动 lightweight migration（不用手写 migration plan）。**但** 合并 store 还是要写逻辑（见 2.4）。

#### B. 所有 fetch / @Query 加 profileId predicate

grep 覆盖面（已搜）：

- `@Query` 用法：SidebarView ×2、CardFlowView (FolderPickerSheet)、CalendarPanelView、ContentView (EmptyStateView)、ImportHistoryView
- `FetchDescriptor` 用法：~30 处，分布 in WorldBookPanelView / DataSettingsTab / SidebarView / GeneralSettingsTab / PersonaSettingsTab / StickerSettingsTab / MemoryService / StickerViewModel / ImportSupport

**每处都要加 `predicate: #Predicate<X> { $0.profileId == currentProfileId }`**。

为了保证不漏：加一层 helper `FetchDescriptor<X>.scoped(to profileId: String)` 扩展，强制走 scoped API。grep `FetchDescriptor<` 找所有直接构造点，逐个替换成 scoped。

#### C. ProfileManager.switchTo 重构

```swift
func switchTo(_ profile: Profile) {
    guard profile.id != currentProfile.id else { return }
    UserDefaults.standard.set(profile.id, forKey: "lastProfileId")
    UserDefaults.standard.set(profile.userName, forKey: "userName")
    UserDefaults.standard.set(profile.assistantName, forKey: "assistantName")
    // 单 container 不变，只翻 currentProfile
    currentProfile = profile
}
```

- 去掉 isSwitchingProfile 替身、retainedOldContainers、notify 同步清、任何 async 过渡
- SwiftUI `@Query` / `FetchDescriptor` 用 `currentProfile.id` 做 predicate，依赖 `@Observable currentProfile` 的变化自动 refetch

### 2.4 数据迁移策略

**迁移触发时机**：首次启动新版本 app，检测到老多 store 文件存在 → 迁移 → 标 `hasUnifiedContainerMigration = true` UserDefaults → 下次启动 skip。

**迁移步骤**：

```
for profile in allProfiles:
    legacyStoreURL = profile.storeURL   // 老 per-profile store 路径
    if legacy file exists:
        let legacyContainer = ModelContainer(configurations: [ModelConfiguration(url: legacyStoreURL)])
        let legacyCtx = legacyContainer.mainContext
        // 读所有 entity
        let conversations = try legacyCtx.fetch(FetchDescriptor<Conversation>())
        for conv in conversations:
            // 复制到新 unified container
            let newConv = Conversation(id: conv.id, title: conv.title, ..., profileId: profile.id)
            unifiedCtx.insert(newConv)
        // 同理：MessageNode / UserCard / ConversationTag / FavoriteItem / ImportRecord /
        // ImportConversationChange / Memory / MemoryNote / WorldBook / StickerAsset / PlacedSticker
        try unifiedCtx.save()
        // 不立即删 legacy，保留 .backup 扩展名
        rename(legacyStoreURL, legacyStoreURL.path + ".backup-2026-04-22")
UserDefaults.set(true, forKey: "hasUnifiedContainerMigration")
```

**风险点**：
- 20 万+ MessageNode：一次 insert 太多可能 OOM。分 profile 分批 save，内部分 batch 每 1000 条 autorelease 一次
- MessageNode → Conversation 关系保持（relationship by id 不变，profileId 都设同一值）
- UserCard → attachedToNodeId 关系保持（都在同 profile）
- 迁移失败 → 保留 legacy .backup，不破坏原数据

**迁移 UI**：启动时 app splash 上 show "首次升级中，合并楼层数据..." progress bar（能看到数量 / 百分比）。不 block 粟粟焦虑。

### 2.5 老 app 里不是每个 entity 都有 profileId

迁移时给老数据补 profileId。新数据 insert 时总是写。

但 `@Model` 字段加默认值 `""`：如果新 app 装到老 store 上，SwiftData lightweight migration 把现存 entity 的 profileId 填 `""`。**此时 filter 就把所有老数据过滤没了**。

→ **合并 migration 必须在 app 可用前跑完**。否则粟粟看到"空楼层"会 panic。

## 3. 工时估算

| 阶段 | 改动 | 时间 |
|---|---|---|
| A. Schema 字段 | 加 7 个 entity 的 profileId 字段 | 30 min |
| B. Fetch scoped helper | 写 helper + grep 替换所有 FetchDescriptor | 2 h |
| C. @Query profileId predicate | 重写 SidebarView / CardFlowView / etc. | 1.5 h |
| D. ProfileManager 简化 | switchTo 改最简 | 15 min |
| E. 清理路线 A 残留 | 撤 isSwitchingProfile / retainedOldContainers / App.body 替身等 | 30 min |
| F. Migration 脚本 | 读老 store → 写新 store，12 个 entity 每种 | 4 h |
| G. Migration UI | 进度条 + 错误兜底 | 1 h |
| H. 测试（模拟器 + 真机） | 切楼层 × 20、数据完整性、性能 | 2 h |
| **总计** | | **~12 h** |

如果不做 migration（直接清老数据让粟粟重新导入 conversations.json），可省 5 h。但粟粟 20 万 节点是真实数据，不能清。

## 4. 风险 / 回退 plan

### 风险

- **R1 Migration 失败破坏数据**：保留 legacy `.backup` 文件，UserDefaults 标记迁移状态；失败不写新 store，让老 app 逻辑 fallback
- **R2 性能回归**：20 万 MessageNode 全在一个 store，某些全表扫描变慢。mitigation：FetchDescriptor 强制加 profileId predicate，sqlite index on profileId
- **R3 Relationship 数据丢**：migration 要确保 MessageNode.parent / Conversation 的引用正确映射
- **R4 新字段 profileId 默认 "" 误 match**：严防 predicate 写错（`==` vs `!=`），写一个 integration test 跑一轮 insert/fetch 确认隔离

### 回退

- 把 UserDefaults `hasUnifiedContainerMigration` 清掉 + 老 `.backup` 文件 rename 回原路径 → 回到路线 A `commit 4f84927` 状态
- 保留 `codex/theme-kelivo-settings` 当前分支作为路线 A 存档，路线 B 开新分支 `codex/unified-container`

## 5. 对路线 C 重构（route C UIHostingController）的影响

无关。路线 C 下的 PagingViewController / UIHostingController 嵌套**跟 modelContainer swap 无关**。它们解决的是 UIKit paging + wallpaper + keyboard。只要 container 稳定，路线 C 本身没问题。路线 B 让 container 稳定后，路线 C 的 race 附属问题全部消失。

## 6. .ai review 补 3 个洞（2026-04-22 粟粟二审）

.ai 深井审这版 research，方向 95% 确信，实施细节三处含糊：

### 洞 1：@Query 动态 profileId 具体怎么写

**问题**：SwiftUI `@Query` 是 macro，predicate 在 view init 里展开。如果 `currentProfileId` 变化但 view instance 不 re-init，@Query 不 refetch → 看到旧楼层数据。

**xcdoc 事实**：`@Query(filter: #Predicate)` 的 predicate 表达式在 view 的 `init` 里 capture，**不是 reactive 重算**。要换 predicate 必须 view re-init（struct 重建 + 新 init 参数）。

**可靠做法**：用 SwiftUI 的 `.id(profile.id)` 在 parent 强制 re-init child view。

```swift
// Parent (ContentView or App level)
SidebarView(profileId: profileManager.currentProfile.id)
    .id(profileManager.currentProfile.id)   // profile 变 → SidebarView 整个 re-init

// Child
struct SidebarView: View {
    let profileId: String
    @Query private var conversations: [Conversation]

    init(profileId: String) {
        self.profileId = profileId
        _conversations = Query(
            filter: #Predicate<Conversation> { $0.profileId == profileId },
            sort: \.lastOpenedAt, order: .reverse
        )
    }
    ...
}
```

**这里 `.id()` 跟路线 A 的 `.id` 不一样**：路线 A 的 `.id` 触发 container + env swap 引发 race；路线 B 的 `.id` 只 re-init view struct，**container 不变**，新 view 的 @Query 在**同一 container** 上带新 predicate fetch，无 race。

**复杂 view 兜底**（SidebarView / CardFlowView 有大量 @State）：放弃 @Query，改手动 FetchDescriptor + `.onChange(of: profileId) { refetch() }` + @State 存结果。代码量多但可控性高，避开 @Query reactive 不明朗的 edge case。

**决策**：SidebarView / CardFlowView / CalendarPanelView 走 FetchDescriptor + @State 路线；EmptyStateView / ImportHistoryView / FolderPickerSheet / NewTagSheet 等简单 view 保留 @Query + `.id()`。plan 阶段每处明确标注。

### 洞 2：profileId 索引是 Day 1 必做

**问题**：单 store 下 20 万+ MessageNode 合并后，每次切楼层 fetch 全表扫 profileId 字段。iPhone 上 20 万行全表扫约 200-500ms → UI 卡 → 比切楼层 crash 还糟。

**xcdoc 事实**：SwiftData 从 iOS 18 开始支持 `#Index` macro 显式声明索引。iOS 26 sdk 稳定支持。

**必做**：每个 `@Model` 声明 `#Index` 覆盖 profileId。高频联合查询加 compound index。

```swift
@Model
final class Conversation {
    #Index<Conversation>(
        [\.profileId],                         // 切楼层用：profileId 单字段
        [\.profileId, \.lastOpenedAt],         // sidebar 列表用：profileId 过滤 + time 排序
        [\.profileId, \.isDeleted, \.lastOpenedAt]  // 回收站过滤用
    )
    var id: String = ""
    var profileId: String = ""
    var lastOpenedAt: Date?
    var isDeleted: Bool = false
    // ...
}
```

`#Index` 在 schema migration 时自动生成 SQLite `CREATE INDEX`。迁移前只需 `Conversation`/`MessageNode`/`Memory` 等高频实体加上。

**plan 把索引写进 Step A（schema 字段）里，和加 profileId 字段一批做，不能延后**。

### 洞 3：Migration relationship + 幂等性

**问题 a**：SwiftData `@Relationship` 跨 container **不能直接 insert 对象**。旧 ctx fetch 出的 MessageNode 对象，它的 `.parent` relationship 绑在旧 ctx 的 backing store 上。直接 `unifiedCtx.insert(oldObj)` 会坏。必须**新建对象 + 逐字段 copy + 用 id 重建 relationship**。

**问题 b**：迁移中途 crash（OOM、断电、杀 app），unified store 有半截数据，`hasUnifiedContainerMigration` 还是 false，下次启动再跑 migration 会**重复 insert**。

**修法 a：MessageNode 树 2-pass 复制**

```swift
func migrateMessageNodes(profile: Profile, legacyCtx: ModelContext, unifiedCtx: ModelContext) throws {
    let oldNodes = try legacyCtx.fetch(FetchDescriptor<MessageNode>())

    // Pass 1: insert 所有节点（不设 parent 关系）
    var nodeMap: [String: MessageNode] = [:]   // 旧 id → 新对象
    for old in oldNodes {
        let new = MessageNode(
            id: old.id,
            conversationId: old.conversationId,
            role: old.role,
            content: old.content,
            // ... 所有值字段
            profileId: profile.id   // ← 新字段
        )
        unifiedCtx.insert(new)
        nodeMap[old.id] = new

        // 每 500 条 save 一次避免内存堆积
        if nodeMap.count % 500 == 0 {
            try unifiedCtx.save()
        }
    }
    try unifiedCtx.save()

    // Pass 2: 通过 nodeMap 重建 parent relationship
    for old in oldNodes {
        guard let oldParent = old.parent,
              let newSelf = nodeMap[old.id],
              let newParent = nodeMap[oldParent.id] else { continue }
        newSelf.parent = newParent
    }
    try unifiedCtx.save()
}
```

Conversation / UserCard / ConversationTag / FavoriteItem 等无 @Relationship 的或用 String id 引用的直接 1-pass copy 即可。

**修法 b：幂等迁移 = 先清脏数据再迁**

```swift
func migrateProfile(_ profile: Profile, legacyURL: URL) async throws {
    let legacyContainer = try ModelContainer(
        for: fullSchema,
        configurations: [ModelConfiguration(url: legacyURL, allowsSave: false)]  // read-only
    )
    let legacyCtx = ModelContext(legacyContainer)
    let unifiedCtx = ModelContext(unifiedContainer)

    // 幂等：先清 unified 里这个 profile 的所有残留（上轮半截迁移）
    try clearProfileData(profileId: profile.id, ctx: unifiedCtx)

    // 依序迁（parent-type 先、child-type 后，遵循 relationship 依赖）
    try migrateConversations(profile: profile, legacyCtx: legacyCtx, unifiedCtx: unifiedCtx)
    try migrateMessageNodes(profile: profile, legacyCtx: legacyCtx, unifiedCtx: unifiedCtx)
    try migrateUserCards(profile: profile, legacyCtx: legacyCtx, unifiedCtx: unifiedCtx)
    try migrateConversationTags(profile: profile, legacyCtx: legacyCtx, unifiedCtx: unifiedCtx)
    try migrateFavoriteItems(profile: profile, legacyCtx: legacyCtx, unifiedCtx: unifiedCtx)
    try migrateMemories(profile: profile, legacyCtx: legacyCtx, unifiedCtx: unifiedCtx)
    try migrateMemoryNotes(profile: profile, legacyCtx: legacyCtx, unifiedCtx: unifiedCtx)
    try migrateWorldBooks(profile: profile, legacyCtx: legacyCtx, unifiedCtx: unifiedCtx)
    try migrateStickerAssets(profile: profile, legacyCtx: legacyCtx, unifiedCtx: unifiedCtx)
    try migratePlacedStickers(profile: profile, legacyCtx: legacyCtx, unifiedCtx: unifiedCtx)
    try migrateImportRecords(profile: profile, legacyCtx: legacyCtx, unifiedCtx: unifiedCtx)
    try migrateImportConversationChanges(profile: profile, legacyCtx: legacyCtx, unifiedCtx: unifiedCtx)
}

func clearProfileData(profileId: String, ctx: ModelContext) throws {
    // 对每个 entity 跑 delete predicate
    try ctx.delete(model: Conversation.self, where: #Predicate { $0.profileId == profileId })
    try ctx.delete(model: MessageNode.self, where: #Predicate { $0.profileId == profileId })
    try ctx.delete(model: UserCard.self, where: #Predicate { $0.profileId == profileId })
    // ... 全部 12 个 entity
    try ctx.save()
}
```

**OOM 缓解**：migrate 每 profile 用独立 background ModelContext（不走 mainContext），每 500 条 save + 主动 `ctx.processPendingChanges()` 释放内存。迁完一个 profile 再开下一个 context。

**crash 后重跑保证幂等**：`clearProfileData` 在每次 migrate 开头跑，把该 profile 的残留先清掉。加上 UserDefaults `migrationInProgressProfileId: String?` 记录当前正在迁哪个 profile，crash 后知道从哪个开始继续（之前已完成的 profile 不重跑）。

## 7. 粟粟批注 v1（2026-04-22）

- [x] 走路线 B ✅
- [x] 分支：**继续当前 `codex/theme-kelivo-settings`** ✅（不开新分支）
- [x] 迁移 UI：**不做进度条 / splash**。粟粟是唯一要迁移的老用户，启动时 console print 一下进度就够了。新用户从 0 开始，根本不触发 migration。
- [x] `.backup` 文件：**永久保留** ✅（不自动清）
- [x] .ai 三个洞：全部纳入 plan（洞 1 @Query 分流、洞 2 `#Index` Day 1、洞 3 2-pass migration + clearProfileData 幂等）

## 8. 下一步

进 plan 阶段（`docs/plan-unified-container.md`），按本 research 的 8 步骤清单写 checklist，每步对照 .ai 的三个洞细化到可执行粒度。粟粟再过一遍 plan 进 implement。

