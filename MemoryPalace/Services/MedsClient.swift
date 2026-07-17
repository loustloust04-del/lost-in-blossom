import Foundation

/// 药箱 — 网关同一份数据（Caelum 的 meds_* 工具管的就是它）。
/// GET /api/meds · POST /api/meds · POST /:id/take · POST /:id/restock · PATCH /:id · DELETE /:id
enum MedsClient {
    struct Med: Decodable, Identifiable, Hashable {
        let id: String
        let name: String
        let remaining: Double
        let unit: String
        let perDose: Double
        let note: String?
    }
    struct Intake: Decodable, Identifiable, Hashable {
        let date: String
        let medId: String
        let name: String
        let amount: Double
        let ts: String
        var id: String { ts + medId }
    }
    struct Snapshot: Decodable {
        let meds: [Med]
        let today: [Intake]
    }

    private static var baseURL: String {
        UserDefaults.standard.string(forKey: "gatewayBaseURL") ?? "https://blossom.amberrib.com"
    }
    private static var token: String {
        UserDefaults.standard.string(forKey: "gatewayAuthToken") ?? ""
    }

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

    static func fetch() async -> Snapshot? {
        guard let req = request("/api/meds") else { return nil }
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    @discardableResult
    static func add(name: String, count: Double, unit: String, perDose: Double) async -> Bool {
        guard let req = request("/api/meds", method: "POST",
                                body: ["name": name, "count": count, "unit": unit, "perDose": perDose]) else { return false }
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    @discardableResult
    static func take(id: String, amount: Double? = nil) async -> Bool {
        var body: [String: Any] = [:]
        if let amount { body["amount"] = amount }
        guard let req = request("/api/meds/\(id)/take", method: "POST", body: body) else { return false }
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    @discardableResult
    static func restock(id: String, count: Double) async -> Bool {
        guard let req = request("/api/meds/\(id)/restock", method: "POST", body: ["count": count]) else { return false }
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    @discardableResult
    static func update(id: String, patch: [String: Any]) async -> Bool {
        guard let req = request("/api/meds/\(id)", method: "PATCH", body: patch) else { return false }
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    @discardableResult
    static func remove(id: String) async -> Bool {
        guard let req = request("/api/meds/\(id)", method: "DELETE") else { return false }
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    /// 数量显示：去掉多余小数（19.0 → "19"）。
    static func numText(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}
