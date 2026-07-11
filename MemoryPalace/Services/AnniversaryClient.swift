import Foundation

/// 纪念日/倒计时 — 网关同一份数据（Caelum 的 remember_anniversary 工具写的就是它）。
/// GET/POST/DELETE {gatewayBaseURL}/api/anniversaries
/// 复用控制台约定：UserDefaults "gatewayBaseURL" / "gatewayAuthToken"。
enum AnniversaryClient {
    struct Item: Identifiable, Decodable {
        let id: String
        let name: String
        let date: String          // YYYY-MM-DD
        let type: String          // "anniversary" | "countdown"
    }

    private static var baseURL: String {
        UserDefaults.standard.string(forKey: "gatewayBaseURL") ?? "https://blossom.amberrib.com"
    }
    private static var token: String {
        UserDefaults.standard.string(forKey: "gatewayAuthToken") ?? ""
    }
    static var isConfigured: Bool { !token.isEmpty }

    private static func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) -> URLRequest? {
        guard !token.isEmpty, let url = URL(string: baseURL + path) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 12
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return req
    }

    static func fetch() async -> [Item] {
        guard let req = request("/api/anniversaries") else { return [] }
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = json["anniversaries"] else { return [] }
        guard let itemsData = try? JSONSerialization.data(withJSONObject: arr) else { return [] }
        return (try? JSONDecoder().decode([Item].self, from: itemsData)) ?? []
    }

    static func add(name: String, date: String, type: String) async -> Bool {
        guard let req = request("/api/anniversaries", method: "POST",
                                body: ["name": name, "date": date, "type": type]) else { return false }
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    static func remove(id: String) async -> Bool {
        guard let req = request("/api/anniversaries/\(id)", method: "DELETE") else { return false }
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    // MARK: - 本地日期计算（展示用，与网关口径一致：北京自然日）

    private static let ymd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// 每条的展示状态。countdown 过期返回 nil（卡片上不显示）。
    /// highlight = 周年当天 / 倒计时 ≤7 天（卡片金色高亮）。
    static func display(for item: Item) -> (text: String, highlight: Bool)? {
        guard let d = ymd.date(from: item.date) else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start = cal.startOfDay(for: d)
        let days = cal.dateComponents([.day], from: start, to: today).day ?? 0
        if item.type == "countdown" {
            let left = -days
            if left < 0 { return nil }
            if left == 0 { return ("就是今天", true) }
            return ("还有 \(left) 天", left <= 7)
        }
        let comps = cal.dateComponents([.month, .day], from: d)
        let years = cal.component(.year, from: today) - cal.component(.year, from: d)
        let isAnniToday = cal.component(.month, from: today) == comps.month
            && cal.component(.day, from: today) == comps.day && years > 0
        if isAnniToday { return ("\(years) 周年 · 第 \(days) 天", true) }
        if days >= 0 { return ("第 \(days) 天", false) }
        return nil
    }
}
