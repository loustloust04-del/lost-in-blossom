import Foundation

/// 从网关 /api/vitals 读取生活数据（只读，兔兔不许造假）
struct VitalsResponse: Codable {
    struct Water: Codable { let count: Int; let goal: Int; let lastUpdated: String }
    struct Food: Codable { let count: Int; let goal: Int; let meals: [String]; let lastUpdated: String }
    struct Meds: Codable { let taken: Bool; let name: String; let lastUpdated: String }
    let water: Water
    let food: Food
    let meds: Meds
    let date: String
}

enum VitalsClient {
    static func fetch() async -> VitalsResponse? {
        let base = UserDefaults.standard.string(forKey: "gatewayBaseURL") ?? "https://blossom.amberrib.com"
        let token = UserDefaults.standard.string(forKey: "gatewayToken") ?? ""
        guard let url = URL(string: "\(base)/api/vitals") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 5
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        return try? JSONDecoder().decode(VitalsResponse.self, from: data)
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
    let apps: [ScreenTimeApp]
}

enum ScreenTimeClient {
    static func fetch() async -> ScreenTimeResponse? {
        guard let url = URL(string: "http://127.0.0.1:3501/api/screentime/today") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("caelumbunny@gmail.com", forHTTPHeaderField: "X-Forwarded-Email")
        req.timeoutInterval = 5
        // 走网关代理（App不能直连VPS内网）
        let base = UserDefaults.standard.string(forKey: "gatewayBaseURL") ?? "https://blossom.amberrib.com"
        let token = UserDefaults.standard.string(forKey: "gatewayToken") ?? ""
        guard let proxyUrl = URL(string: "\(base)/api/screentime") else { return nil }
        var proxyReq = URLRequest(url: proxyUrl)
        proxyReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        proxyReq.timeoutInterval = 5
        guard let (data, _) = try? await URLSession.shared.data(for: proxyReq) else { return nil }
        return try? JSONDecoder().decode(ScreenTimeResponse.self, from: data)
    }
}
