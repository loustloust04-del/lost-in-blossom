# 任务：健康模块搬运（本地 SwiftData + 统计详情页）

> 参考：`/root/projects/SusuPalace` origin/master
> 分两步：第一步搬模块，第二步接入 Console
> 用到 Swift Charts（系统框架，不需要额外 SPM）

---

## 第一步：搬运健康模块（独立面板）

### 1a. 复制文件

```bash
cd /root/projects/SusuPalace && git checkout origin/master

# Models（2 文件）
cp MemoryPalace/Models/HealthLog.swift \
   MemoryPalace/Models/HealthSnapshot.swift \
   /root/projects/BunnyPalace/MemoryPalace/Models/

# Services（5 文件）
cp MemoryPalace/Services/HealthCycleStore.swift \
   MemoryPalace/Services/HealthLogIntentWriter.swift \
   MemoryPalace/Services/HealthLogStore.swift \
   MemoryPalace/Services/HealthStatsStore.swift \
   /root/projects/BunnyPalace/MemoryPalace/Services/

# Views（4 文件）
mkdir -p /root/projects/BunnyPalace/MemoryPalace/Views/Health
cp MemoryPalace/Views/Health/HealthDetailSheets.swift \
   MemoryPalace/Views/Health/HealthGatesSections.swift \
   MemoryPalace/Views/Health/HealthPanelView.swift \
   MemoryPalace/Views/HealthSettingsTab.swift \
   /root/projects/BunnyPalace/MemoryPalace/Views/Health/
# 注意 HealthSettingsTab 放 Health/ 子目录
```

### 1b. SwiftData schema 注册

`MemoryPalaceApp.swift` 的 ModelContainer schema 数组加 5 个新 Model：
```swift
WeightEntry.self,
Medication.self,
MedicationLog.self,
CycleDay.self,
IntimacyEntry.self,
```

查找位置：
```bash
grep -n "Schema\|modelContainer\|\.self" /root/projects/BunnyPalace/MemoryPalace/MemoryPalaceApp.swift | head -10
```

### 1c. 接入 Page 2 dock

`RightPanelPlugin.swift` 的 `builtInTools` 加：
```swift
RightPanelTool(id: "health", name: "健康", icon: "heart.fill", order: 3),
```
order 靠前（排在日历后面）。

`MemoryPanelView.swift` 的 `panelContent` switch 加：
```swift
case "health":
    HealthPanelView(profileId: profileManager?.currentProfile.id ?? "")
```

### 1d. 编译适配

**HealthService 依赖**：粟粟的 HealthPanelView 可能引用 `HealthService.shared`（苹果健康读取）。我们已有 `HealthKitService`，需要做映射：
```bash
grep "HealthService\." /root/projects/BunnyPalace/MemoryPalace/Views/Health/HealthPanelView.swift | head -10
```
把 `HealthService.shared` 改成我们的 `HealthKitService` 对应方法，或者直接把粟粟的 `HealthService.swift`（204 行）也复制过来替换我们的。

**import Charts**：HealthDetailSheets 和 HealthPanelView 用了 `import Charts`（iOS 16+ 系统框架），不需要额外 SPM。

**macOS 代码**：所有 `#if os(macOS)` 块删掉。

**CycleFlow / WeightUnit**：定义在 `HealthCycleStore.swift` 和 `HealthLogStore.swift` 里，复制了就有。

**HealthLogIntentWriter**：这个让 AI 用 ```health-log 块记录健康数据（跟 voice 块同族）。如果编译有依赖缺失，先注释掉，后续补。

### 1e. 验证

1. [ ] 编译通过
2. [ ] Page 2 dock 出现 ❤️「健康」
3. [ ] 点进去看到四张卡：吃药（空）+ 月经（空）+ 体重（空）+ 最近流水（空）
4. [ ] 点"添加药物" → 填写药名/剂量/时间 → 保存 → 药卡出现
5. [ ] 点药卡上的打卡按钮 → 状态变"已服"
6. [ ] 体重输入框输入数字 → 点记录 → 体重卡出现折线图
7. [ ] 经期 toggle 点击 → 记录今日经期
8. [ ] 四张卡都可以整卡点击进入详情 sheet
9. [ ] 吃药详情：月热图 + 依从率
10. [ ] 体重详情：90天/一年/全部折线图

---

## 第二步：Console 改读本地数据

等第一步跑稳后再做。

### 2a. Console 药物卡改数据源

`ConsoleView.swift` 里的药物卡目前读 `VitalsResponse.meds`（Gateway），改成读本地：

```swift
// 旧：
let medsTaken = vitals?.meds.taken ?? false
let medsName = vitals?.meds.name ?? ""

// 新：
let todayMeds = HealthLogStore.todayMedStates(meds: localMeds, logs: todayLogs, now: Date())
let allTaken = todayMeds.allSatisfy { $0.value == .taken }
```

需要在 ConsoleView 加 `@Query` 拉本地 Medication 和 MedicationLog。

### 2b. Console 经期卡改数据源

```swift
// 旧：从某处手动计算
// 新：
let periods = HealthCycleStore.periods(cycleDays: Array(localCycleDays))
let status = HealthCycleStore.statusLine(todayFlow: todayFlow, periods: periods, now: Date())
```

### 2c. Console 体重卡（新增）

如果 Console 之前没有体重卡，加一张：
```swift
// 读最近一条
if let latest = localWeights.first {
    smallWidget(title: "体重", icon: "scalemass", value: "\(formatted(latest.weightKg))", unit: unit.symbol, sub: latest.date.formatted(.dateTime.month().day()))
}
```

### 2d. Gateway vitals 降级

不删 VitalsClient，但改成"只用于 AI 注入"：
- Console 显示用本地 SwiftData
- Gateway 的 `/api/vitals` 改成从 App POST 上去的同步数据（可选，以后做）

### 2e. 验证

1. [ ] Console 药物卡显示本地数据（不依赖 Gateway 连接）
2. [ ] Console 经期卡显示本地数据
3. [ ] 断网时 Console 仍正常显示（本地数据）
4. [ ] 在健康面板打卡 → Console 卡片实时更新

---

## 通用红线

1. **不要碰 CLAUDE.md**
2. 第一步和第二步分开 commit，第一步完成后先 push 等 CI
3. 第一步不改 Console（并存），第二步才改
4. 健康数据是隐私敏感数据，亲密记录默认双开关关闭
5. commit message：`feat(health): ...`
6. 我们已有的 `HealthKitService.swift`（步数/睡眠/屏幕时间）保留不动，它跟粟粟的健康模块是互补的（她读 HealthKit 同样的几项）
