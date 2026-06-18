# 任务：ConsoleView 新增手机电量卡片

## 背景
Gateway 的 `GET /phone-data` 返回当天所有手机状态记录（电量、充电状态）。
ConsoleView 需要一张卡片展示最新电量和充电状态。

## 任务 1：VitalsClient.swift 新增 PhoneStatusClient

在 `MemoryPalace/Services/VitalsClient.swift` 末尾追加：

```swift
struct PhoneStatusRecord: Codable {
    let battery: Int
    let is_charging: Bool
    let received_at: String
}

struct PhoneStatusResponse: Codable {
    let date: String
    let total_records: Int
    let records: [PhoneStatusRecord]
}

enum PhoneStatusClient {
    static func fetch() async -> PhoneStatusResponse? {
        let base = UserDefaults.standard.string(forKey: "gatewayBaseURL")
            ?? "https://blossom.amberrib.com"
        guard let url = URL(string: "\(base)/phone-data") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        return try? JSONDecoder().decode(PhoneStatusResponse.self, from: data)
    }
}
```

## 任务 2：DailyContext 加字段

在 `MemoryPalace/Models/DailyContext.swift` 的 DailyContext 里加：

```swift
var phoneBattery: Int?
var phoneCharging: Bool?
```

## 任务 3：ConsoleView 加载 phone status

在 ConsoleView 的 `loadData()` 或 `.task {}` 里，ScreenTimeClient.fetch() 附近加：

```swift
if let ps = await PhoneStatusClient.fetch(), let ctx = todayCtx,
   let latest = ps.records.last {
    ctx.phoneBattery = latest.battery
    ctx.phoneCharging = latest.is_charging
    try? modelContext.save()
}
```

## 任务 4：ConsoleView 加电量卡片

在 `cardStack` 里 `screenTimeCard` 后面加 `phoneCard`：

```swift
private var phoneCard: some View {
    ConsoleCard(id: "phone", tappedCardId: $tappedCardId) {
        ConsoleTag(icon: "battery.75percent", label: "手机状态")
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                if let battery = todayCtx?.phoneBattery {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(battery)")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(Self.textPrimary)
                        Text("%")
                            .font(.system(size: 13))
                            .foregroundColor(Self.textUnit)
                    }
                    let charging = todayCtx?.phoneCharging == true ? "充电中" : "未充电"
                    Text(charging)
                        .font(.system(size: 12))
                        .foregroundColor(Self.textMuted)
                } else {
                    Text("—")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Self.textMuted)
                    Text("等待快捷指令上报")
                        .font(.system(size: 11))
                        .foregroundColor(Self.textMuted)
                }
            }
            Spacer()
        }
    }
}
```

## 验收
1. 快捷指令发送手机状态后，刷新 ConsoleView，电量卡片显示最新电量和充电状态
2. 没有数据时显示"等待快捷指令上报"
