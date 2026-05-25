# Plan: 路线 B —— 单 ModelContainer + profileId filter

> 基于 `docs/research-unified-container.md`（含 .ai 三个洞的补丁）
> 分支：继续 `codex/theme-kelivo-settings`（路线 A 存档在 commit `4f84927`）
> 粟粟批注：不做迁移 UI / `.backup` 永久保留 / 集成 .ai 的三个洞

## 0. 核心约束 checklist

- [ ] 迁移只跑**一次**且**幂等**（粟粟唯一老用户，crash 后重跑安全）
- [ ] 切楼层**零 crash**（真机 + 模拟器 Debug build 都干净）
- [ ] 切楼层 UI 不卡（index 保证 < 50ms fetch）
- [ ] 老数据零丢失（legacy store `.backup` 永久保留）
- [ ] 代码可读性不倒退（scoped fetch helper，grep 找漏点）

## 1. 改动地图

| 类别 | 文件数 | 工时 |
|---|---|---|
| A. Schema 加 profileId + #Index | 12 个 Model | 30 min |
| B. Fetch scoped helper + ScopedFetch 扩展 | 1 个新文件 | 30 min |
| C. 50+ FetchDescriptor 加 predicate | 11 个文件 | 2 h |
| D. 7 个 @Query 改 dynamic profileId | 5 个文件 | 1 h |
| E. ProfileManager 简化 switchTo | 1 个文件 | 15 min |
| F. 撤路线 A 残留（isSwitching / retainedOld / sheet guard / .id hack 等） | 8 个文件 | 45 min |
| G. Migration 脚本 (2-pass + 幂等 clearProfileData) | 1 个新文件 | 3 h |
| H. App 启动触发 migration | MemoryPalaceApp.swift | 30 min |
| I. 测试（build + 模拟器 + 真机切 20 次 + 数据完整性） | — | 2 h |
| **总计** | | **~10.5 h** |

## 2. Step A：Schema 加 profileId + #Index（Day 1）

### A.1 7 个未加 profileId 的 @Model 加字段

文件 & 改动：

**`MemoryPalace/Models/Conversation.swift`**

```swift
@Model
final class Conversation {
    #Index<Conversation>(
        [\.profileId],
        [\.profileId, \.lastOpenedAt],
        [\.profileId, \.isDeleted, \.lastOpenedAt]
    )
    var id: String = ""
    var profileId: String = ""      // ← 新增
    var title: String = ""
    var createTime: Date = Date()
    var lastOpenedAt: Date = Date()
    var isFavorite: Bool = false
    var isDeleted: Bool = false
    // ... 其他现有字段不变

    init(id: String, profileId: String, title: String, /* ... */) {
        self.id = id
        self.profileId = profileId   // ← 必填
        self.title = title
        // ...
    }
}

@Model
final class MessageNode {
    #Index<MessageNode>(
        [\.profileId],
        [\.profileId, \.conversationId],
        [\.profileId, \.conversationId, \.isDeleted]
    )
    var id: String = ""
    var profileId: String = ""      // ← 新增
    var conversationId: String = ""
    // ...

    init(id: String, profileId: String, conversationId: String, /* ... */) {
        self.profileId = profileId
        // ...
    }
}

@Model
final class UserCard {
    #Index<UserCard>([\.profileId], [\.profileId, \.attachedToNodeId])
    var id: UUID = UUID()
    var profileId: String = ""      // ← 新增
    // ...
}
```

**`MemoryPalace/Models/ConversationTag.swift`**

```swift
@Model
final class ConversationTag {
    #Index<ConversationTag>([\.profileId], [\.profileId, \.order])
    var id: String = ""
    var profileId: String = ""      // ← 新增
    var order: Int = 0
    // ...
}

@Model
final class FavoriteItem {
    #Index<FavoriteItem>([\.profileId], [\.profileId, \.conversationId])
    var id: UUID = UUID()
    var profileId: String = ""      // ← 新增
    var conversationId: String
    var tagId: String
    // ...
}
```

**`MemoryPalace/Models/ImportRecord.swift`**

```swift
@Model
final class ImportRecord {
    #Index<ImportRecord>([\.profileId, \.importDate])
    var id: UUID = UUID()
    var profileId: String = ""      // ← 新增
    var importDate: Date = Date()
    // ...
}
```

**`MemoryPalace/Models/ImportConversationChange.swift`**

```swift
@Model
final class ImportConversationChange {
    #Index<ImportConversationChange>([\.profileId, \.recordId])
    var id: UUID = UUID()
    var profileId: String = ""      // ← 新增
    var recordId: UUID
    // ...
}
```

### A.2 已有 profileId 的 5 个 @Model 只补 #Index

**`MemoryPalace/Models/Memory.swift`**

```swift
#Index<Memory>(
    [\.profileId],
    [\.profileId, \.decayWeight],
    [\.profileId, \.updatedAt]
)
```

**`MemoryPalace/Models/MemoryNote.swift`**

```swift
#Index<MemoryNote>([\.profileId])
```

**`MemoryPalace/Models/PlacedSticker.swift`**

```swift
#Index<PlacedSticker>(
    [\.profileId, \.conversationId],
    [\.profileId, \.conversationId, \.zIndex]
)
```

**`MemoryPalace/Models/StickerAsset.swift`**

```swift
#Index<StickerAsset>([\.profileId, \.createdAt])
```

**`MemoryPalace/Models/WorldBook.swift`**

```swift
#Index<WorldBook>([\.profileId])
```

### A.3 必做 checklist

- [ ] **A1** Conversation 加 profileId + #Index
- [ ] **A2** MessageNode 加 profileId + #Index
- [ ] **A3** UserCard 加 profileId + #Index
- [ ] **A4** ConversationTag 加 profileId + #Index
- [ ] **A5** FavoriteItem 加 profileId + #Index
- [ ] **A6** ImportRecord 加 profileId + #Index
- [ ] **A7** ImportConversationChange 加 profileId + #Index
- [ ] **A8** Memory 补 #Index（profileId 已有）
- [ ] **A9** MemoryNote 补 #Index
- [ ] **A10** PlacedSticker 补 #Index
- [ ] **A11** StickerAsset 补 #Index
- [ ] **A12** WorldBook 补 #Index
- [ ] **build**：`xcodebuild` 过，Schema 迁移不抛错

注：加默认值 `""` 让 SwiftData lightweight migration 自动处理 —— 老 store 现存数据升 schema 时 profileId 自动填 `""`，**下一步 B 的 migration 脚本会覆盖这个 `""`**。

## 3. Step B：ScopedFetch helper（保证不漏）

**新文件**：`MemoryPalace/Services/ScopedFetch.swift`

```swift
import SwiftData

extension FetchDescriptor where T: PersistentModel {
    /// 构造 profileId-scoped 的 FetchDescriptor。路线 B 全局单 container + profileId
    /// filter，**所有 fetch 必须走这个 helper**，避免漏 predicate 跨楼层捞数据。
    ///
    /// 用法：`FetchDescriptor<Conversation>.scoped(to: currentProfileId, predicate: ...)`
    /// 组合 predicate 会自动 AND profileId。
    static func scoped<T: PersistentModel>(
        _ type: T.Type,
        profileId: String,
        predicate additional: Predicate<T>? = nil,
        sortBy: [SortDescriptor<T>] = []
    ) -> FetchDescriptor<T> where T: HasProfileId {
        // 由于 Swift 泛型限制，这个函数不能完美写成 extension。见实际实现使用独立函数或 wrapper
        // 具体实现见 plan 下方 B.2
        fatalError("implementation")
    }
}
```

**实际实现思路**（Swift 泛型限制，做成工厂函数）：

```swift
/// 所有 profile-scoped entity 都 conform 此 protocol
protocol HasProfileId: PersistentModel {
    var profileId: String { get }
}

extension Conversation: HasProfileId {}
extension MessageNode: HasProfileId {}
extension UserCard: HasProfileId {}
extension ConversationTag: HasProfileId {}
extension FavoriteItem: HasProfileId {}
extension ImportRecord: HasProfileId {}
extension ImportConversationChange: HasProfileId {}
extension Memory: HasProfileId {}
extension MemoryNote: HasProfileId {}
extension PlacedSticker: HasProfileId {}
extension StickerAsset: HasProfileId {}
extension WorldBook: HasProfileId {}

/// 全局 helper：构造 profileId-scoped FetchDescriptor
@inlinable
func scopedFetch<T: HasProfileId>(
    _ type: T.Type,
    profileId: String,
    matching extra: Predicate<T>? = nil,
    sortBy: [SortDescriptor<T>] = []
) -> FetchDescriptor<T> {
    var desc: FetchDescriptor<T>
    if let extra = extra {
        desc = FetchDescriptor<T>(
            predicate: #Predicate<T> { obj in
                obj.profileId == profileId && extra.evaluate(obj)
            },
            sortBy: sortBy
        )
    } else {
        desc = FetchDescriptor<T>(
            predicate: #Predicate<T> { obj in
                obj.profileId == profileId
            },
            sortBy: sortBy
        )
    }
    return desc
}
```

注：`Predicate.evaluate` 组合可能被 macro 限制 —— 如果不 work，改成**函数接收现成的 `Predicate<T>` 参数，返回新的 `Predicate<T>` 包装**，或者调用方自己拼 `#Predicate { $0.profileId == pid && 其他条件 }` 全写出来。Plan 阶段保留灵活性，Implement 阶段根据编译器反馈调整。

**兜底**：如果 helper 写不出来，就每处 FetchDescriptor 里**手动**加 `$0.profileId == profileId &&` 条件，grep `FetchDescriptor<` 逐个检查。

checklist：

- [ ] **B1** 新建 `MemoryPalace/Services/ScopedFetch.swift`，定义 `HasProfileId` protocol
- [ ] **B2** 让 12 个 entity conform `HasProfileId`
- [ ] **B3** 实现 `scopedFetch<T>` 工厂函数（或替代方案）
- [ ] **build** 验证

## 4. Step C：50+ FetchDescriptor 加 profileId predicate

grep 到的 fetch 点分类：

### C.1 已有 profileId filter（不用改，review 确认）

- `ConversationViewModel.swift:764` ✅ `WorldBook profileId`
- `WorldBookPanelView.swift:681` ✅
- `GeneralSettingsTab.swift:95/242` ✅
- `StickerSettingsTab.swift:102/107/286/291` ✅（sticker assets / placed）
- `StickerPackExporter.swift:50/56` ✅
- `ImportSupport.swift:183/214` ✅ favoriteDescriptor by profileId
- `StickerViewModel.swift:102/112/317` ✅

### C.2 需要加 profileId predicate

**`MemoryPalace/Views/SidebarView.swift`**（14 处）

- line 1027 `FavoriteItem` fetch — 加 profileId
- line 1045, 1059, 1258, 1311, 1348, 1394, 1439, 1656, 1700 — 全部 `FetchDescriptor<Conversation>`，加 profileId
- line 1068, 1086 — `FetchDescriptor<MessageNode>`，加 profileId
- line 1265, 1419 — `FetchDescriptor<FavoriteItem>`，加 profileId
- line 1427 — `FetchDescriptor<Conversation>`

**`MemoryPalace/ViewModels/ConversationViewModel.swift`**（9 处）

- line 184, 217, 322, 333, 396, 663 — MessageNode，加 profileId
- line 673, 695 — FavoriteItem，加 profileId

**`MemoryPalace/Views/WorldBookPanelView.swift`**（2 处）

- line 731, 750 — `FetchDescriptor<Conversation>`，加 profileId

**`MemoryPalace/Views/DataSettingsTab.swift`**（3 处）

- line 292, 314, 375 — Conversation，加 profileId

**`MemoryPalace/Views/ImportHistoryView.swift`**（2 处）

- line 87 `ImportConversationChange` — 加 profileId
- line 123 `ImportRecord` — 加 profileId

**`MemoryPalace/Services/ConversationImporter.swift`**（2 处）

- line 45, 154 — `FetchDescriptor<Conversation>`，加 profileId（**危险点**：原来跨 profile 找"重复"对话，改后只在当前楼层找 → 不同楼层允许同 id conversation，行为变化，但合理）

**`MemoryPalace/Services/ClaudeImporter.swift`**（grep 可能漏）

- 同 ConversationImporter，加 profileId filter

**`MemoryPalace/Services/ImportSupport.swift`**（2 处）

- line 26 MessageNode — 加 profileId
- line 193 UserCard — 加 profileId

**`MemoryPalace/MemoryPalaceApp.swift`**

- line 391 MemoryNote fetch in migration code — 加 profileId

**`MemoryPalace/Views/StickerSettingsTab.swift`**（C.1 里 ✅，但 predicate 写法核对）

**`MemoryPalace/Views/SidebarView.swift` 的 getConversationNodeCounts 类 helper**（~line 1030/1050 批量 id 查找）

- `FetchDescriptor<Conversation>()` 无 predicate（line 1059）— **严重漏**：跨 profile 捞全表，加 profileId

checklist：

- [ ] **C1** SidebarView 14 处加 profileId
- [ ] **C2** ConversationViewModel 9 处加 profileId
- [ ] **C3** WorldBookPanelView 2 处加 profileId
- [ ] **C4** DataSettingsTab 3 处加 profileId
- [ ] **C5** ImportHistoryView 2 处加 profileId
- [ ] **C6** ConversationImporter 2 处加 profileId
- [ ] **C7** ClaudeImporter 相应位置加 profileId
- [ ] **C8** ImportSupport 2 处加 profileId
- [ ] **C9** MemoryPalaceApp migration code 点加 profileId
- [ ] **grep 兜底**：`grep -rn "FetchDescriptor<" MemoryPalace/` 逐行 review，凡 entity 是 HasProfileId 的必须有 `profileId ==` predicate
- [ ] **build** 过

## 5. Step D：7 个 @Query 改动态 profileId

### D.1 简单 view：保留 @Query + init 参数 + `.id(profileId)` 强制 re-init

**`MemoryPalace/Views/ContentView.swift:877` EmptyStateView**

```swift
struct EmptyStateView: View {
    @Binding var showImporter: Bool
    let profileId: String
    @Query private var conversations: [Conversation]

    init(showImporter: Binding<Bool>, profileId: String) {
        self._showImporter = showImporter
        self.profileId = profileId
        _conversations = Query(
            filter: #Predicate<Conversation> { $0.profileId == profileId }
        )
    }
    // body 不变
}
```

Parent 改：`EmptyStateView(showImporter: $showImporter, profileId: profileManager?.currentProfile.id ?? "")`
+ `.id(profileManager?.currentProfile.id ?? "")` 触发 profile 变化时 re-init（得到新 @Query）。

**`MemoryPalace/Views/ImportHistoryView.swift:6`**

同理改 init 接收 profileId。

**`MemoryPalace/Views/CalendarPanelView.swift:9` allConversations**

同理。

### D.2 简单 view：ConversationTag 的 @Query

`SidebarView.swift:36 + 1737`、`CardFlowView.swift:1414` 的 `@Query tags: [ConversationTag]` —— ConversationTag 加了 profileId 字段后，也要 scoped。

```swift
init(profileId: String, /* ... other params */) {
    self.profileId = profileId
    _tags = Query(
        filter: #Predicate<ConversationTag> { $0.profileId == profileId },
        sort: \ConversationTag.order
    )
}
```

### D.3 复杂 view SidebarView：放弃 @Query，走 FetchDescriptor + @State + onChange

SidebarView 已经在用 FetchDescriptor + @State pattern（conversations 是 @State 不是 @Query），所以改动只是 C.1 里的 fetch 加 profileId。

CardFlowView 有 `@Query tags`，也是简单情况。

checklist：

- [ ] **D1** EmptyStateView 改 init(profileId:) + Query filter
- [ ] **D2** ImportHistoryView 同上
- [ ] **D3** CalendarPanelView 同上
- [ ] **D4** SidebarView 的 @Query tags 改 scoped（2 处）
- [ ] **D5** CardFlowView 的 @Query tags 改 scoped
- [ ] **D6** NewTagSheet / FolderPickerSheet 的 @Query tags 改 scoped
- [ ] Parent view 全部传 `profileId: profileManager.currentProfile.id` + `.id(profileId)`

## 6. Step E：ProfileManager 简化

**`MemoryPalace/MemoryPalaceApp.swift`**

```swift
@Observable
final class ProfileManager {
    var profiles: [Profile]
    var currentProfile: Profile
    var container: ModelContainer   // 唯一，app lifetime 不换

    // ❌ 删除：isSwitchingProfile, retainedOldContainers

    init() {
        self.profiles = Self.loadProfiles()
        let lastId = UserDefaults.standard.string(forKey: "lastProfileId") ?? "ghost-lily"
        self.currentProfile = profiles.first { $0.id == lastId } ?? profiles.first!
        // 关键：统一 container 指向**单一 unified store**，不再 per-profile
        self.container = Self.makeUnifiedContainer()
    }

    func switchTo(_ profile: Profile) {
        guard profile.id != currentProfile.id else { return }
        UserDefaults.standard.set(profile.id, forKey: "lastProfileId")
        UserDefaults.standard.set(profile.userName, forKey: "userName")
        UserDefaults.standard.set(profile.assistantName, forKey: "assistantName")
        currentProfile = profile   // @Observable → view 自动 refetch
    }

    static func makeUnifiedContainer() -> ModelContainer {
        let schema = Schema([ /* 12 entity types */ ])
        // 固定存储路径（不按 profile 分），Application Support 下 unified.store
        let url = URL.applicationSupportDirectory
            .appendingPathComponent("MemoryPalace", isDirectory: true)
            .appendingPathComponent("unified.store")
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create unified container: \(error)")
        }
    }
}
```

App.body 简化：

```swift
var body: some Scene {
    WindowGroup {
        ContentView()
            .preferredColorScheme(themeManager.preferredColorScheme)
            .environment(themeManager)
            .environment(profileManager)
            .environment(providerManager)
            // ...
            .modelContainer(profileManager.container)
            .id(profileManager.currentProfile.id)   // 保留：profile 变化时强制 re-init ContentView，
                                                     // 让 @Query 带新 predicate 重新 fetch。
                                                     // 这次 .id 改变**不会触发 container swap**，
                                                     // 所以无 SwiftData reset race。
    }
}
```

checklist：

- [ ] **E1** 删 `isSwitchingProfile` / `retainedOldContainers` 等路线 A 残留
- [ ] **E2** `makeUnifiedContainer` 替代 `makeContainer(for:)`
- [ ] **E3** `switchTo` 改最简 3 行
- [ ] **E4** App.body 的 if/else 替身分支删掉，还原为单 ContentView + `.id(profile.id)`

## 7. Step F：撤路线 A 残留

遍历 commit `4f84927` 的改动，回退**非必要**部分，保留"有正面价值的"：

| 路线 A 改动 | 路线 B 处理 |
|---|---|
| ConversationViewModel profileSwitchObserver queue:nil | **保留** + **加注释**（见下）|
| ConversationViewModel profileSwitchObserver 存 token + 显式 removeObserver | **保留**（修 observer 泄漏 bug） |
| StickerViewModel profileSwitchObserver | **保留** + **加注释**（见下）|
| PagingViewController handleProfileWillSwitch 换 Color.clear | **删除**（container 不变后不需要） |
| SidebarView .onReceive 清 @State 数组 | **保留**（切楼层清 searchResults / renamingConversationId 等语义上正确，避免看到跨楼层的 search 残留） |
| SidebarView `.id(ObjectIdentifier(modelContext.container))` | **删除**（container 不变，这个 id 永远不变 no-op） |
| MemoryPanelView `.task(id:)` + 300ms delay | **改为** `.onAppear { refreshMemories() }`（回退，300ms delay 不再需要） |
| MemorySettingsTab 同上 | **改回** `.onAppear` |
| GeneralSettingsTab body isSwitchingProfile guard | **删除** |
| EmptyStateView `.id(ObjectIdentifier(modelContext.container))` | **删除** |
| ContentView iOSLayout 里 `.id(containerId)` 挂 PagingContainerView | **删除** |
| ContentView EmptyStateView `.id(...)` | **删除**（D.1 里用 profileId .id 替代） |
| MemoryPalaceApp 的 isSwitchingProfile 替身 if/else | **删除** |
| Notification.profileWillSwitch 定义 | **保留**（VM observer 用） |

### F.observer-comment (.ai L6 审计)

路线 B 下 `.id(profileId)` 在 ContentView / VM 重建时会让 @State VM re-init，observer
也跟着重新注册，VM 的 @State 自然清空 —— 所以 VM observer 从 **主路径防御**降级为
**belt-and-suspenders**（多一层兜底，比如 notification post 在 ContentView
remount 之前 fire，observer 提前清）。保留是"不减分"，但要加注释防维护者困惑。

```swift
// MARK: - Profile Switch State Clear (defense-in-depth)
//
// 路线 B 下，切楼层通过 ProfileManager.switchTo → @Observable currentProfile 变化 →
// ContentView.id(profile.id) 触发 SwiftUI destroy + recreate 整棵 ContentView → VM
// 随 @State 一起 recreate，@State 自然清 —— **不需要显式 clear**。
//
// 这个 observer 保留原因：ConversationViewModel 不是 ContentView 直属 @State（某些
// sub-view 可能持 VM 独立实例 or VM 作 @Environment 注入），re-init 机制不保证 cover
// 100%。保留 observer 作 defense-in-depth，即使主路径 re-init 不触发，clear 逻辑也跑一遍。
//
// 保留 = 不减分；如确认所有 VM 都是 ContentView 直 @State 则可删。
```

同样注释贴 `StickerViewModel.profileSwitchObserver`。

checklist：

- [ ] **F1** PagingViewController handleProfileWillSwitch 删
- [ ] **F2** SidebarView `.id(ObjectIdentifier(container))` 删
- [ ] **F3** MemoryPanelView .task(id:) 回退 onAppear
- [ ] **F4** MemorySettingsTab 同
- [ ] **F5** GeneralSettingsTab isSwitchingProfile guard 删
- [ ] **F6** ContentView page-level `.id(containerId)` 删
- [ ] **F7** ContentView EmptyStateView `.id(container)` 删（D.1 的 profileId 替代）
- [ ] **F8** MemoryPalaceApp body 的 if/else 替身 删
- [ ] **F9** ProfileManager 的 isSwitchingProfile + retainedOldContainers 删（已在 E.1）
- [ ] **F10** ConversationViewModel profileSwitchObserver 加 defense-in-depth 注释
- [ ] **F11** StickerViewModel profileSwitchObserver 加同样注释

## 8. Step G：Migration 脚本

**新文件**：`MemoryPalace/Services/UnifiedContainerMigration.swift`

```swift
import SwiftData
import Foundation

enum UnifiedContainerMigration {
    private static let migrationKey = "hasUnifiedContainerMigration"
    private static let inProgressKey = "unifiedContainerMigrationInProgressProfileId"

    /// 返回是否需要迁移（UserDefaults 里没标完成 + 至少一个 legacy store 存在）
    static func needsMigration(profiles: [Profile]) -> Bool {
        if UserDefaults.standard.bool(forKey: migrationKey) { return false }
        return profiles.contains { FileManager.default.fileExists(atPath: $0.legacyStoreURL.path) }
    }

    /// 主入口。粟粟场景：启动时检测 → 同步跑（~数十秒对 20 万节点）→ 完成后 app 正常启动
    /// 中途 crash 保证幂等：每个 profile 开头先 clearProfileData，重跑不重复 insert
    static func runMigration(profiles: [Profile], unifiedCtx: ModelContext) throws {
        for profile in profiles {
            let legacyURL = profile.legacyStoreURL
            guard FileManager.default.fileExists(atPath: legacyURL.path) else {
                print("[migration] skip \(profile.id) — no legacy store")
                continue
            }

            UserDefaults.standard.set(profile.id, forKey: inProgressKey)
            print("[migration] start profile=\(profile.id)")

            // 读 legacy —— **必须 allowsSave: true**！
            // 原因（.ai L4 审计风险点）：用**新 schema**（含 profileId + #Index）打开老 store
            // 时 SwiftData 需要 lightweight migration 给老表加 `profileId TEXT DEFAULT ""` 列 +
            // 建索引。read-only（allowsSave: false）模式下 SwiftData 无法写 migration → 可能
            // 抛 error 直接 fail。allowsSave: true 让 SwiftData 正常做 migration 写入老 store，
            // 反正迁完就 rename 成 .backup-2026-04-22 备份，多一列 profileId="" 无害。
            // xcdoc 未明确 read-only 模式下的 schema mismatch 行为，保守做法用 true。
            let legacyContainer = try ModelContainer(
                for: Schema.fullSchema,   // 12 entity types
                configurations: [ModelConfiguration(url: legacyURL, allowsSave: true)]
            )
            let legacyCtx = ModelContext(legacyContainer)

            // 幂等：先清 unified 里这 profile 的残留
            try clearProfileData(profileId: profile.id, ctx: unifiedCtx)

            // 按依赖顺序迁移
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

            // 重命名 legacy → .backup-2026-04-22 保留（粟粟批注永久保留）
            let backupURL = legacyURL.appendingPathExtension("backup-2026-04-22")
            if !FileManager.default.fileExists(atPath: backupURL.path) {
                try FileManager.default.moveItem(at: legacyURL, to: backupURL)
                // sidecar -wal / -shm 同样处理
                let wal = legacyURL.appendingPathExtension("wal")
                let shm = legacyURL.appendingPathExtension("shm")
                if FileManager.default.fileExists(atPath: wal.path) {
                    try? FileManager.default.moveItem(at: wal, to: wal.appendingPathExtension("backup-2026-04-22"))
                }
                if FileManager.default.fileExists(atPath: shm.path) {
                    try? FileManager.default.moveItem(at: shm, to: shm.appendingPathExtension("backup-2026-04-22"))
                }
            }
            print("[migration] done profile=\(profile.id)")
        }

        UserDefaults.standard.removeObject(forKey: inProgressKey)
        UserDefaults.standard.set(true, forKey: migrationKey)
        print("[migration] all profiles done")
    }

    // MARK: - 幂等 clear

    private static func clearProfileData(profileId: String, ctx: ModelContext) throws {
        try ctx.delete(model: Conversation.self, where: #Predicate { $0.profileId == profileId })
        try ctx.delete(model: MessageNode.self, where: #Predicate { $0.profileId == profileId })
        try ctx.delete(model: UserCard.self, where: #Predicate { $0.profileId == profileId })
        try ctx.delete(model: ConversationTag.self, where: #Predicate { $0.profileId == profileId })
        try ctx.delete(model: FavoriteItem.self, where: #Predicate { $0.profileId == profileId })
        try ctx.delete(model: Memory.self, where: #Predicate { $0.profileId == profileId })
        try ctx.delete(model: MemoryNote.self, where: #Predicate { $0.profileId == profileId })
        try ctx.delete(model: WorldBook.self, where: #Predicate { $0.profileId == profileId })
        try ctx.delete(model: StickerAsset.self, where: #Predicate { $0.profileId == profileId })
        try ctx.delete(model: PlacedSticker.self, where: #Predicate { $0.profileId == profileId })
        try ctx.delete(model: ImportRecord.self, where: #Predicate { $0.profileId == profileId })
        try ctx.delete(model: ImportConversationChange.self, where: #Predicate { $0.profileId == profileId })
        try ctx.save()
        // .ai L2 审计：20 万行 delete + 后续 insert 可能交替 IO spike。flush pending changes
        // 让 SwiftData 把 delete 落盘 + 释放 undo / object cache，再开始 insert 更稳。
        ctx.processPendingChanges()
    }

    // MARK: - 2-pass MessageNode

    private static func migrateMessageNodes(profile: Profile, legacyCtx: ModelContext, unifiedCtx: ModelContext) throws {
        let oldNodes = try legacyCtx.fetch(FetchDescriptor<MessageNode>())
        print("[migration] \(profile.id) message nodes: \(oldNodes.count)")

        var nodeMap: [String: MessageNode] = [:]   // oldId → 新对象 ref
        var parentMap: [String: String] = [:]      // .ai L5 优化：用 string id 而非 object ref
                                                    // 避免 Pass 2 还得持 legacyCtx 的对象 → 双倍内存峰值

        // Pass 1: insert 全部节点（不设 parent）+ 同时记录 oldId → oldParentId string 映射
        for old in oldNodes {
            let new = MessageNode(
                id: old.id,
                profileId: profile.id,
                conversationId: old.conversationId,
                role: old.role,
                content: old.content,
                createTime: old.createTime,
                // ... 所有值字段逐个 copy（看 MessageNode 定义）
                isFavorite: old.isFavorite,
                isDeleted: old.isDeleted,
                isPinned: old.isPinned,
                pinnedAt: old.pinnedAt,
                deletedAt: old.deletedAt
            )
            unifiedCtx.insert(new)
            nodeMap[old.id] = new

            // 记下 parent id（string）用于 Pass 2，不保 legacyCtx 的 object ref
            if let parentId = old.parent?.id {
                parentMap[old.id] = parentId
            }

            if nodeMap.count % 500 == 0 {
                try unifiedCtx.save()
                unifiedCtx.processPendingChanges()
            }
        }
        try unifiedCtx.save()

        // Pass 2: 通过 parentMap[childId] = parentId 查表重建 relationship
        // 此时 legacyCtx 的 oldNodes 可以被 ARC 回收（没人持有），内存峰值降一半
        for (childId, parentId) in parentMap {
            guard let child = nodeMap[childId],
                  let parent = nodeMap[parentId] else { continue }
            child.parent = parent
        }
        try unifiedCtx.save()
        unifiedCtx.processPendingChanges()
    }

    private static func migrateConversations(profile: Profile, legacyCtx: ModelContext, unifiedCtx: ModelContext) throws {
        let olds = try legacyCtx.fetch(FetchDescriptor<Conversation>())
        for old in olds {
            let new = Conversation(
                id: old.id,
                profileId: profile.id,
                title: old.title,
                // ... 值字段
                createTime: old.createTime,
                lastOpenedAt: old.lastOpenedAt,
                isFavorite: old.isFavorite,
                isDeleted: old.isDeleted,
                memoryEnabled: old.memoryEnabled,
                currentNodeId: old.currentNodeId,
                nodeCount: old.nodeCount,
                updateTime: old.updateTime
            )
            unifiedCtx.insert(new)
        }
        try unifiedCtx.save()
    }

    // ... migrateUserCards / migrateConversationTags / migrateFavoriteItems /
    //     migrateMemories / migrateMemoryNotes / migrateWorldBooks /
    //     migrateStickerAssets / migratePlacedStickers /
    //     migrateImportRecords / migrateImportConversationChanges
    //     每个 entity 照抄，只要记得设 profileId = profile.id
}
```

**Profile.legacyStoreURL** —— 原 `Profile.storeURL` 改名为 `legacyStoreURL` 保留（它指原来 per-profile store 路径，只给 migration 用）。ProfileManager 新逻辑不用它。

checklist：

- [ ] **G1** 新建 `UnifiedContainerMigration.swift` 骨架
- [ ] **G2** 实现 `clearProfileData`（12 entity delete by predicate）
- [ ] **G3** 实现 `migrateConversations`
- [ ] **G4** 实现 `migrateMessageNodes` (2-pass)
- [ ] **G5** 实现 `migrateUserCards`
- [ ] **G6** 实现 `migrateConversationTags`
- [ ] **G7** 实现 `migrateFavoriteItems`
- [ ] **G8** 实现 `migrateMemories`
- [ ] **G9** 实现 `migrateMemoryNotes`
- [ ] **G10** 实现 `migrateWorldBooks`
- [ ] **G11** 实现 `migrateStickerAssets`
- [ ] **G12** 实现 `migratePlacedStickers`
- [ ] **G13** 实现 `migrateImportRecords`
- [ ] **G14** 实现 `migrateImportConversationChanges`
- [ ] **G15** 500-条分批 save + `processPendingChanges`（OOM 缓解）
- [ ] **G16** legacy store 重命名 `.backup-2026-04-22`（包括 `-wal` / `-shm` sidecar）
- [ ] **G17** UserDefaults `hasUnifiedContainerMigration` / `inProgressProfileId` 状态管理

## 9. Step H：App 启动触发 Migration

**`MemoryPalace/MemoryPalaceApp.swift`**

```swift
init() {
    // 1. 建 unified container（它保证 schema 升级 + #Index 建好）
    let unifiedContainer = ProfileManager.makeUnifiedContainer()
    let profiles = ProfileManager.loadProfiles()

    // 2. 如果需要迁移，同步跑（粟粟可接受一次性 ~数十秒启动慢）
    if UnifiedContainerMigration.needsMigration(profiles: profiles) {
        let ctx = ModelContext(unifiedContainer)
        do {
            try UnifiedContainerMigration.runMigration(profiles: profiles, unifiedCtx: ctx)
        } catch {
            print("[migration] FAILED: \(error)")
            // 不 fatalError；允许 app 继续（哪怕数据不全），保留 legacy store 供手动恢复
        }
    }

    // 3. 用 unified container 构造 ProfileManager
    _profileManager = State(wrappedValue: ProfileManager(container: unifiedContainer, profiles: profiles))
}
```

checklist：

- [ ] **H1** App init 先建 unified container
- [ ] **H2** needsMigration 检测
- [ ] **H3** runMigration 同步调用
- [ ] **H4** migration 失败 fail-safe（不 crash，让 app 启动，粟粟 log 能看到）

## 10. Step I：测试

### I.1 模拟器测试

- [ ] 删模拟器 app → 重装（全新用户路径，不触发 migration）
- [ ] 切楼层 × 20 回（来回 A/B/A/B），**零 crash**
- [ ] 导入 conversations.json，切楼层后数据显示正确
- [ ] 贴纸 / 记忆 / 世界书 / 角色卡在两个楼层独立
- [ ] 删楼层：数据跟着消失（`delete where profileId == ...`）

### I.2 粟粟真机 migration 测试

- [ ] 粟粟真机先 backup `Application Support/MemoryPalace` 整个目录
- [ ] 装新版 app → 启动 → console log 看 migration 进度
- [ ] migration 完成后，切楼层 × 20，**零 crash**
- [ ] 数据完整性 sanity：随便翻几个老对话看 message tree 完整，贴纸位置 / pin 状态 / world book / memory / character card 都在
- [ ] 如果有问题，删 app，恢复 backup，回到 4f84927 commit

### I.3 性能 sanity

- [ ] 首次启动 migration 时间：20 万节点预期 < 60s（console 打印各 profile 耗时）
- [ ] 切楼层后 sidebar 首屏 < 200ms（console `[PERF]` log）
- [ ] 加了 #Index 的 fetch 应该跟 legacy per-profile store 近似快

## 11. 回退 plan

如果 implement 中发现 block：
- git 切回 `4f84927`
- 或者：保留 schema 字段 + index 改动（low-risk），回退 ProfileManager 简化（保留 retain 方案）
- 或者：保留所有改动但 migration 脚本换成"新 app 只认新 schema，老数据用 ImportView 手动导入"—— 粟粟不可接受这个，最后兜底用

## 11.5 .ai 二轮审计的 4 个修补（2026-04-22）

.ai 深井二轮看实施细节，一个真风险 + 三个优化：

| # | .ai 提点 | 落地位置 | 决策 |
|---|---|---|---|
| L4 (blocker) | legacy store 用新 schema + `allowsSave:false` 打开时 lightweight migration 可能被拒，导致 fetch 失败 | Step G 的 `migrateProfile` | **`allowsSave: true`** — SwiftData 自由 migrate legacy store，反正迁完就 rename `.backup`，老 store 多一列 `profileId=""` 无害 |
| L2 | clearProfileData 删 20 万行后 + 下一步 insert 可能 IO / 内存 spike | Step G clearProfileData 末尾 | 加 `ctx.processPendingChanges()` flush pending changes |
| L5 | MessageNode 2-pass 的 Pass 2 用 `old.parent` object ref → legacyCtx 对象必须 Pass 2 期间还活着 → 双倍内存峰值 | Step G migrateMessageNodes | Pass 1 改成同时存 `parentMap: [childId: parentId]` string 映射，Pass 2 只用 `nodeMap` 查 |
| L6 | VM observer 保留但路线 B 下是 defense-in-depth 而非主路径，维护者会困惑 | Step F | 加长注释说明 re-init 机制 + observer 是多一层兜底 |

.ai 二轮结论：plan 可执行性从 85% → **92%**，剩 8% 是 SwiftData 未记载行为的固有风险（只能跑了才知道）。

## 12. 粟粟过目点

- [ ] 9 步 checklist 顺序 OK 吗？（A→B→C→D→E→F→G→H→I）
- [ ] .ai 的三个洞都落到具体 step：洞 1 在 Step D，洞 2 在 Step A（#Index Day 1），洞 3 在 Step G（2-pass + clearProfileData）
- [ ] 迁移中途如果真 OOM / crash，粟粟手动 relaunch app，migration 从头重跑（clearProfileData 幂等保证无重复）
- [ ] legacy store `.backup-2026-04-22` 永久保留
- [ ] 真机 migration 前**务必先 backup Application Support/MemoryPalace 整目录**（粟粟手动用 Finder 拷贝 or 用 Xcode Devices & Simulators 导出 app container）

批注完动手。
