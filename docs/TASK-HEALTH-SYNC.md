# 任务：健康数据双向同步（App ↔ Gateway ↔ Caelum）

> 目标：你在 app 记录的、Caelum 用工具记录的，两边实时互通
> 参考架构审计：`docs/ARCHITECTURE-AUDIT.md`

---

## 现状（三份数据各说各话）

```
① App 本地 SwiftData    ② Gateway 药品柜        ③ Gateway vitals
   Medication              MedItem                 meds.taken
   timesOfDay 服药计划      remaining 库存           单个 bool
   MedicationLog 打卡       intake 摄入量            无历史
   → 健康面板 + Console     → Caelum meds_* 工具     → 老的简化版

你加药 → ① 有，②③ 不知道
Caelum 加药 → ② 有，①③ 不知道
```

**关键洞察**：① 和 ② 不是重复，是**互补** —— ① 管"几点该吃"，② 管"还剩几片"。合并后才是完整的药物管理。

---

## 目标架构

```
        本地 SwiftData（唯一真相源）
    Medication: name/dosage/timesOfDay/remaining/unit
    MedicationLog: 打卡记录
              ↕ 双向同步
        Gateway /api/meds（镜像 + Caelum 工具入口）
              ↓
        Caelum meds_list / meds_add / meds_take
```

---

## 改动清单

### 一、扩展本地 Medication 模型（加库存字段）

文件：`MemoryPalace/Models/HealthLog.swift`

```swift
@Model
final class Medication {
    // ... 现有字段 ...
    
    /// 库存：剩余数量（跟 Gateway 药品柜同步）
    var remaining: Double = 0
    /// 单位：片/粒/mg
    var unit: String = "片"
    /// 每次剂量
    var perDose: Double = 1
    /// Gateway 侧 id（同步用，本地新建时为 nil）
    var gatewayId: String? = nil
    /// 最后同步时间
    var lastSyncedAt: Date? = nil
}
```

SwiftData 加可选/带默认值字段是安全的，旧数据自动填默认值。

### 二、新建 HealthSyncService

文件：`MemoryPalace/Services/HealthSyncService.swift`（新建）

```swift
import Foundation
import SwiftData

/// 健康数据双向同步：本地 SwiftData ↔ Gateway /api/meds
/// 
/// 上行：本地增删改 → POST/PATCH/DELETE Gateway
/// 下行：拉 Gateway 列表 → 合并进本地（gatewayId 匹配）
/// 冲突策略：last-write-wins（比 lastSyncedAt）
enum HealthSyncService {
    
    /// 全量同步：先推本地未同步的，再拉远端
    @MainActor
    static func sync(context: ModelContext, profileId: String) async {
        await pushLocal(context: context, profileId: profileId)
        await pullRemote(context: context, profileId: profileId)
    }
    
    /// 上行：本地新增/修改的药推给 Gateway
    @MainActor
    private static func pushLocal(context: ModelContext, profileId: String) async {
        let pid = profileId
        let desc = FetchDescriptor<Medication>(predicate: #Predicate { $0.profileId == pid && !$0.isArchived })
        let localMeds = (try? context.fetch(desc)) ?? []
        
        for med in localMeds {
            if med.gatewayId == nil {
                // 本地新建的，推到 Gateway
                if let remoteId = await MedsClient.add(
                    name: med.name,
                    remaining: med.remaining,
                    unit: med.unit,
                    perDose: med.perDose,
                    note: med.note
                ) {
                    med.gatewayId = remoteId
                    med.lastSyncedAt = Date()
                }
            }
            // 已同步的暂不做 PATCH（避免覆盖 Caelum 的改动），后续可加 lastWriteWins
        }
        try? context.save()
    }
    
    /// 下行：拉 Gateway 药品柜，合并进本地
    @MainActor
    private static func pullRemote(context: ModelContext, profileId: String) async {
        guard let snap = await MedsClient.fetch() else { return }
        let pid = profileId
        let desc = FetchDescriptor<Medication>(predicate: #Predicate { $0.profileId == pid })
        let localMeds = (try? context.fetch(desc)) ?? []
        
        for remote in snap.meds {
            if let local = localMeds.first(where: { $0.gatewayId == remote.id }) {
                // 已有：更新库存（Caelum 可能 restock 过）
                local.remaining = remote.remaining
                local.unit = remote.unit
                local.perDose = remote.perDose
                local.lastSyncedAt = Date()
            } else if let byName = localMeds.first(where: { $0.name == remote.name && $0.gatewayId == nil }) {
                // 同名但没绑定：认领
                byName.gatewayId = remote.id
                byName.remaining = remote.remaining
                byName.lastSyncedAt = Date()
            } else {
                // Caelum 新加的药，本地不存在 → 创建
                let m = Medication(
                    profileId: profileId,
                    name: remote.name,
                    dosage: "\(remote.perDose)\(remote.unit)",
                    timesOfDay: []   // Caelum 加的药没有时刻计划，用户可后补
                )
                m.remaining = remote.remaining
                m.unit = remote.unit
                m.perDose = remote.perDose
                m.gatewayId = remote.id
                m.lastSyncedAt = Date()
                context.insert(m)
            }
        }
        
        // 同步今日打卡：Gateway intake → 本地 MedicationLog
        for intake in snap.today {
            guard let local = localMeds.first(where: { $0.gatewayId == intake.medId }) else { continue }
            let ts = ISO8601DateFormatter().date(from: intake.ts) ?? Date()
            // 去重：同药同时间戳只记一次
            let logDesc = FetchDescriptor<MedicationLog>(
                predicate: #Predicate { $0.medicationId == local.id }
            )
            let existing = (try? context.fetch(logDesc)) ?? []
            let dup = existing.contains { abs($0.takenAt.timeIntervalSince(ts)) < 60 }
            if !dup {
                let log = MedicationLog(profileId: profileId, medicationId: local.id, minuteOfDay: minuteOf(ts), takenAt: ts)
                context.insert(log)
            }
        }
        
        try? context.save()
    }
    
    private static func minuteOf(_ d: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
```

### 三、MedsClient 补上 add 返回 id

文件：`MemoryPalace/Services/MedsClient.swift`

现有的 `add` 可能不返回 id，改成返回新建药的 id：

```swift
static func add(name: String, remaining: Double, unit: String, perDose: Double, note: String?) async -> String? {
    // POST /api/meds → 返回 { id: "..." }
    // 解析 id 返回
}
```

### 四、本地打卡时推给 Gateway

文件：`MemoryPalace/Services/HealthLogStore.swift`

在 `logIntake` 函数末尾加：

```swift
// 同步到 Gateway（Caelum 能看到）
if let gid = medication.gatewayId {
    Task { await MedsClient.take(id: gid, amount: medication.perDose) }
}
```

### 五、触发同步的时机

在 `ConsoleView` 和 `HealthPanelView` 的 `.task` 里加：

```swift
.task {
    await HealthSyncService.sync(context: modelContext, profileId: profileId)
}
```

以及 app 回前台时（`ScenePhase` 变化）。

### 六、废弃 vitals_meds（老的简化版）

文件：`gateway/src/vitals.ts`

`vitals_meds` 工具改成转发给药品柜，或直接删掉工具定义（保留 API 兼容）：

```typescript
// vitals_meds 已废弃，统一用 meds_* 工具
// 保留 API 但标记 deprecated
```

Console 的 `VitalsClient` 里 meds 字段不再使用（已改读本地）。

---

## 验证清单

1. [ ] 编译通过
2. [ ] 在健康面板加一种药 → Gateway `/api/meds` 能看到
3. [ ] 让 Caelum "帮我加一种药：维生素D，30片" → 打开 app 健康面板能看到
4. [ ] 在健康面板打卡 → 让 Caelum "我今天吃药了吗" → 他知道
5. [ ] 让 Caelum "记录我吃了拉莫三嗪" → app 健康面板打卡状态更新
6. [ ] 库存：Caelum `meds_restock` 补货 → app 显示新库存
7. [ ] 断网时本地记录不丢，联网后自动同步

---

## 注意

1. **不要碰 CLAUDE.md**
2. 同步是「最终一致」不是「实时」，用户可能需要下拉刷新
3. 冲突策略先用简单的：库存以 Gateway 为准（Caelum 管补货），时刻计划以本地为准（用户设的）
4. 经期/体重暂不同步（Gateway 没有对应存储），后续可加
5. commit message：`feat(health-sync): ...`
