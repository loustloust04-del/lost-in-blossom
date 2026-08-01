import Foundation
import SwiftData

/// 从网关 /api/vitals 读取生活数据（只读，兔兔不许造假）
struct VitalsResponse: Codable {
    struct Water: Codable { let count: Int; let goal: Int; let lastUpdated: String }
    struct Food: Codable { let count: Int; let goal: Int; let meals: [String]; let lastUpdated: String }
    struct Meds: Codable { let taken: Bool; let name: String; let lastUpdated: String }
    /// 控制台备注（Caelum 经 console_write 记的），可选=旧网关兼容
    struct Note: Codable, Hashable { let text: String; let by: String; let ts: String }
    let water: Water
    let food: Food
    let meds: Meds
    let notes: [Note]?
    let date: String
}

enum VitalsClient {
    static func fetch() async -> VitalsResponse? {
        let base = UserDefaults.standard.string(forKey: "gatewayBaseURL") ?? "https://blossom.amberrib.com"
        let token = UserDefaults.standard.string(forKey: "gatewayAuthToken") ?? ""
        guard let url = URL(string: "\(base)/api/vitals") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 5
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        return try? JSONDecoder().decode(VitalsResponse.self, from: data)
    }

    /// 把 App 本地记的饮水/进食推给网关合并（取两边较大者，meals 追加未见过的）。
    /// 返回合并后的服务端状态，供调用方回写本地——一次往返完成双向同步。
    static func merge(waterCount: Int, foodCount: Int, meals: [String]) async -> VitalsResponse? {
        let base = UserDefaults.standard.string(forKey: "gatewayBaseURL") ?? "https://blossom.amberrib.com"
        let token = UserDefaults.standard.string(forKey: "gatewayAuthToken") ?? ""
        guard let url = URL(string: "\(base)/api/vitals/merge") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 8
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "water_count": waterCount, "food_count": foodCount, "meals": meals,
        ])
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        // merge 返回 {ok, water, food}，补上 notes/date 后复用 VitalsResponse 解码
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let water = obj["water"], let food = obj["food"] else { return nil }
        let shaped: [String: Any] = [
            "water": water, "food": food,
            "meds": ["taken": false, "name": "", "lastUpdated": ""],
            "notes": [], "date": "",
        ]
        guard let d2 = try? JSONSerialization.data(withJSONObject: shaped) else { return nil }
        return try? JSONDecoder().decode(VitalsResponse.self, from: d2)
    }
}

/// 饮水/进食双向同步：App 本地 DailyContext ↔ Gateway vitals。
/// 药物走 HealthSyncService（实体列表），这两个是当日计数器，语义不同故独立：
/// 合并取较大者 + meals 并集，谁记的都不丢，然后把合并结果回写本地——
/// 双方从此看到同一份数字，ConsoleView/CareView 的 max() 创可贴可以退休。
enum VitalsSyncService {
    private static let lastKey = "vitalsSync.lastRun"
    private static let throttle: TimeInterval = 45

    @MainActor
    static func sync(context: ModelContext, profileId: String, force: Bool = false) async {
        if !force {
            let last = UserDefaults.standard.double(forKey: lastKey)
            guard Date().timeIntervalSince1970 - last > throttle else { return }
        }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastKey)

        let today = Calendar.current.startOfDay(for: Date())
        let desc = FetchDescriptor<DailyContext>(
            predicate: #Predicate { $0.profileId == profileId && $0.date == today })
        guard let ctx = try? context.fetch(desc).first else { return }

        let localMeals = ctx.meals.map(\.description).filter { !$0.isEmpty }
        guard let merged = await VitalsClient.merge(
            waterCount: ctx.waterCount, foodCount: ctx.meals.count, meals: localMeals
        ) else { return }

        // 回写：服务端合并后的数更大 = Caelum 记过我们没有的，补进本地
        var changed = false
        if merged.water.count > ctx.waterCount { ctx.waterCount = merged.water.count; changed = true }
        for name in merged.food.meals where !localMeals.contains(name) {
            ctx.meals.append(MealEntry(description: name))
            changed = true
        }
        // 服务端餐数更多但没给出名字（Caelum 用了 vitals_food 未填 meal）：补占位保证计数一致
        while ctx.meals.count < merged.food.count {
            ctx.meals.append(MealEntry(description: "未记录"))
            changed = true
        }
        if changed { try? context.save() }
    }
}


// MARK: - Screen Time（从 Memory Palace 读取）

struct ScreenTimeApp: Codable {
    let app: String
    let sessions: Int
    let minutes: Double
}

struct ScreenTimeResponse: Codable {
    let date: String
    let total_minutes: Double
    let social_minutes: Double
    let apps: [ScreenTimeApp]
}

enum ScreenTimeClient {
    static func fetch() async -> ScreenTimeResponse? {
        // 只走网关代理；token 用 App 统一的 gatewayAuthToken（gatewayToken 是历史空键）
        let base = UserDefaults.standard.string(forKey: "gatewayBaseURL") ?? "https://blossom.amberrib.com"
        let token = UserDefaults.standard.string(forKey: "gatewayAuthToken") ?? ""
        guard let url = URL(string: "\(base)/api/screentime") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 5
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        return try? JSONDecoder().decode(ScreenTimeResponse.self, from: data)
    }
}
