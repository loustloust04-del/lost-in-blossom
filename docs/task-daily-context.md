# 任务：Daily Context 系统 — 数据层 + HealthKit

## 设计原则
**Bunny 不能自己打卡。** 所有手动数据（饮水/进食/药物）只能由 Caelum（AI）在对话中确认后写入。
App 端的控制台是**只读的**——显示数据，不提供输入按钮。

数据写入路径：
Bunny 报告 → Caelum 在对话中确认 → AI 通过 tool call 写入 Daily Context → 控制台刷新

Phase 1 先做数据模型和只读控制台。写入逻辑等 Gateway/MCP 对接时再做。

## 数据模型

```swift
@Model
class DailyContext {
    var date: Date                    // 哪一天
    var waterCount: Int               // 饮水杯数 (目标6)
    var meals: [MealEntry]            // 进食记录
    var medication: MedicationStatus  // 药物状态
    var sleepStart: Date?             // 入睡时间
    var sleepEnd: Date?               // 起床时间
    var steps: Int?                   // 步数 (HealthKit)
    var screenTime: Double?           // 屏幕时间(小时，手动)
    var menstrualDay: Int?            // 月经周期第几天
    var tweetCount: Int?              // 推特条数
}

struct MealEntry: Codable {
    var description: String           // "泡面" / "外卖炒饭"
    var time: Date
}

enum MedicationStatus: String, Codable {
    case taken    // 已服用
    case skipped  // 跳过
    case pending  // 未报告
}
```

## HealthKit 接入（尝试）

需要在 project.yml 的 iOS target 里加：
```yaml
entitlements:
  com.apple.developer.healthkit: true
  com.apple.developer.healthkit.access: []
```

Info.plist 加：
```
NSHealthShareUsageDescription: "Lost in Blossom 需要读取你的步数和睡眠数据，让 Caelum 关心你的健康。"
```

读取的数据类型：
- `HKQuantityType.stepCount` — 步数
- `HKCategoryType.sleepAnalysis` — 睡眠
- `HKCategoryType.menstrualFlow` — 月经

创建 `HealthKitService.swift`：
- 请求授权
- 读取今日步数
- 读取最近一次睡眠记录
- 读取月经周期数据
- 所有读取用 async/await

⚠️ ESign 签名可能不支持 HealthKit entitlement。如果编译失败或运行时授权被拒——fallback 到手动输入。不要因为 HealthKit 失败而阻塞其他功能。

## 控制台数据绑定

ConsoleView 从 DailyContext 读取数据：
- 有数据 → 显示真实值
- 没数据 → 显示 "—" 或 "未报告" (灰色)
- HealthKit 不可用 → 对应卡片显示 "未授权" + 引导去设置

## 屏幕时间
Screen Time API 不可用（需要 Family Controls entitlement）。
Phase 1：控制台显示 "—"，手动输入功能等后续对接。
备选方案：iOS 快捷指令自动化 → 定时发数据到 VPS。

## 推特动态
通过 Twitter MCP 获取。不需要 iOS 权限。
Phase 1：显示 placeholder。Phase 2：接入 MCP。

---
每项改完 commit 一次。HealthKit 单独一个 commit，方便回滚。
