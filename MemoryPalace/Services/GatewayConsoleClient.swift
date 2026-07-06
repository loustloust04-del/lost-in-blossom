import Foundation

/// 网关控制台数据客户端（只读 + 添加记忆）。
/// 复用 App 统一的 gatewayBaseURL / gatewayAuthToken（与 VitalsClient 同一约定）。
/// 端点对应 gateway/src/app.ts：/health /v1/models /api/memories(+dreams/desires/sync) /api/mcp/tools
enum GatewayConsoleClient {

    static var baseURL: String {
        UserDefaults.standard.string(forKey: "gatewayBaseURL") ?? "https://blossom.amberrib.com"
    }
    private static var token: String {
        UserDefaults.standard.string(forKey: "gatewayAuthToken") ?? ""
    }

    private static func get(_ path: String, timeout: TimeInterval = 8) async throws -> Data {
        guard let url = URL(string: baseURL + path) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        return data
    }

    /// Supabase 主键有的表是 uuid（String）有的是 int8——统一解码成 String
    struct FlexID: Codable, Hashable {
        let value: String
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) { value = s }
            else if let i = try? c.decode(Int.self) { value = String(i) }
            else { value = UUID().uuidString }
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            try c.encode(value)
        }
    }

    // MARK: - Health

    struct HealthInfo {
        let ok: Bool
        let memoryConnected: Bool
        let latencyMs: Int
    }
    private struct HealthResp: Codable { let status: String; let memory: String }

    static func health() async -> HealthInfo? {
        let start = Date()
        guard let data = try? await get("/health", timeout: 5),
              let h = try? JSONDecoder().decode(HealthResp.self, from: data) else { return nil }
        return HealthInfo(
            ok: h.status == "ok",
            memoryConnected: h.memory == "connected",
            latencyMs: Int(Date().timeIntervalSince(start) * 1000)
        )
    }

    // MARK: - Models

    struct GatewayModel: Codable, Identifiable {
        let id: String
        let owned_by: String
    }
    private struct ModelsResp: Codable { let data: [GatewayModel] }

    static func models() async -> [GatewayModel] {
        guard let data = try? await get("/v1/models"),
              let r = try? JSONDecoder().decode(ModelsResp.self, from: data) else { return [] }
        return r.data
    }

    // MARK: - Memories

    struct GatewayMemory: Codable, Identifiable {
        let id: String
        let content: String
        let tier: Int?
        let category: String?
        let is_pinned: Bool?
        let source: String?
        let created_at: String?
    }
    private struct MemoriesResp: Codable {
        let memories: [GatewayMemory]
        let total: Int?
    }

    static func memories(limit: Int = 50, offset: Int = 0, category: String? = nil) async -> (items: [GatewayMemory], total: Int) {
        var path = "/api/memories?limit=\(limit)&offset=\(offset)"
        if let category, !category.isEmpty,
           let enc = category.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&category=\(enc)"
        }
        guard let data = try? await get(path),
              let r = try? JSONDecoder().decode(MemoriesResp.self, from: data) else { return ([], 0) }
        return (r.memories, r.total ?? r.memories.count)
    }

    /// 手动添加一条记忆（POST /api/memories/sync，网关侧标 source='manual' 并查重）。
    /// 返回 true = 已入库；false = 被查重跳过或失败。
    static func addMemory(content: String, category: String?, tier: Int = 3) async -> Bool {
        guard let url = URL(string: baseURL + "/api/memories/sync") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 8
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var mem: [String: Any] = ["content": content, "tier": tier]
        if let category, !category.isEmpty { mem["category"] = category }
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["memories": [mem]])
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
        return (obj["added"] as? Int ?? 0) > 0
    }

    // MARK: - Dreams / Desires

    struct GatewayDream: Codable, Identifiable {
        let id: FlexID
        let date: String?
        let layer: String?
        let summary: String?
        let created_at: String?
    }
    private struct DreamsResp: Codable { let dreams: [GatewayDream] }

    static func dreams() async -> [GatewayDream] {
        guard let data = try? await get("/api/memories/dreams"),
              let r = try? JSONDecoder().decode(DreamsResp.self, from: data) else { return [] }
        return r.dreams
    }

    struct GatewayDesire: Codable, Identifiable {
        let id: String
        let content: String
        let created_at: String?
    }
    private struct DesiresResp: Codable { let desires: [GatewayDesire] }

    static func desires(limit: Int = 20) async -> [GatewayDesire] {
        guard let data = try? await get("/api/memories/desires?limit=\(limit)"),
              let r = try? JSONDecoder().decode(DesiresResp.self, from: data) else { return [] }
        return r.desires
    }

    // MARK: - MCP 工具

    struct GatewayTool: Codable, Identifiable {
        let name: String
        let description: String?
        let source: String?
        var id: String { name }
    }
    private struct ToolsResp: Codable {
        let tools: [GatewayTool]
        let count: Int?
    }

    static func mcpTools() async -> [GatewayTool] {
        guard let data = try? await get("/api/mcp/tools", timeout: 12),
              let r = try? JSONDecoder().decode(ToolsResp.self, from: data) else { return [] }
        return r.tools
    }
}
