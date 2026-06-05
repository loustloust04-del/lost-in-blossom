import Foundation
import Observation

struct ChatroomSession: Codable, Identifiable {
    let id: String
    let topic: String
    let ai_a_model: String
    let ai_a_name: String
    let ai_b_model: String
    let ai_b_name: String
    let status: String
    let rounds: Int
    let created_at: String
    let ended_at: String?
}

struct ChatroomMessage: Codable, Identifiable {
    let id: Int
    let role: String      // "ai_a" / "ai_b" / "user"
    let content: String
    let model: String?
    let created_at: String
}

@Observable
final class ChatroomService {
    static let shared = ChatroomService()

    // 编排器地址（从 UserDefaults 读，默认用 VPS IP）
    var baseURL: String {
        UserDefaults.standard.string(forKey: "chatroomBaseURL")
            ?? "http://172.245.88.103:3300"
    }

    private(set) var sessions: [ChatroomSession] = []
    private(set) var currentMessages: [ChatroomMessage] = []
    private(set) var isStreaming = false
    private(set) var streamingRole: String? = nil
    private(set) var streamingContent: String = ""

    // 创建聊天室
    func startSession(
        topic: String,
        aiAModel: String, aiAName: String, aiASystem: String,
        aiBModel: String, aiBName: String, aiBSystem: String
    ) async throws -> String {
        let url = URL(string: "\(baseURL)/chatroom/start")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "topic": topic,
            "ai_a_model": aiAModel, "ai_a_name": aiAName, "ai_a_system": aiASystem,
            "ai_b_model": aiBModel, "ai_b_name": aiBName, "ai_b_system": aiBSystem,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        let result = try JSONDecoder().decode([String: String].self, from: data)
        return result["id"] ?? ""
    }

    // 继续下一轮
    func continueRound(sessionId: String) async throws {
        let url = URL(string: "\(baseURL)/chatroom/continue")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["session_id": sessionId])
        let _ = try await URLSession.shared.data(for: req)
    }

    // 用户发消息
    func sendMessage(sessionId: String, content: String) async throws {
        let url = URL(string: "\(baseURL)/chatroom/send")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "session_id": sessionId, "content": content
        ])
        let _ = try await URLSession.shared.data(for: req)
    }

    // 结束聊天室
    func endSession(sessionId: String) async throws {
        let url = URL(string: "\(baseURL)/chatroom/end")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["session_id": sessionId])
        let _ = try await URLSession.shared.data(for: req)
    }

    // 获取消息历史
    func fetchHistory(sessionId: String) async throws {
        let url = URL(string: "\(baseURL)/chatroom/history/\(sessionId)")!
        let (data, _) = try await URLSession.shared.data(for: URLRequest(url: url))
        struct Resp: Codable { let messages: [ChatroomMessage] }
        let resp = try JSONDecoder().decode(Resp.self, from: data)
        await MainActor.run { self.currentMessages = resp.messages }
    }

    // 获取所有聊天室列表
    func fetchSessions() async throws {
        let url = URL(string: "\(baseURL)/chatroom/sessions")!
        let (data, _) = try await URLSession.shared.data(for: URLRequest(url: url))
        struct Resp: Codable { let sessions: [ChatroomSession] }
        let resp = try JSONDecoder().decode(Resp.self, from: data)
        await MainActor.run { self.sessions = resp.sessions }
    }

    // SSE 流式订阅
    func subscribeStream(sessionId: String) {
        guard let url = URL(string: "\(baseURL)/chatroom/stream/\(sessionId)") else { return }
        isStreaming = true
        streamingContent = ""

        Task {
            let (bytes, _) = try await URLSession.shared.bytes(from: url)
            var eventType = ""

            for try await line in bytes.lines {
                if line.hasPrefix("event: ") {
                    eventType = String(line.dropFirst(7))
                } else if line.hasPrefix("data: ") {
                    let jsonStr = String(line.dropFirst(6))
                    guard let data = jsonStr.data(using: .utf8),
                          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    else { continue }

                    await MainActor.run {
                        switch eventType {
                        case "turn_start":
                            self.streamingRole = obj["role"] as? String
                            self.streamingContent = ""
                        case "ai_speaking":
                            if let delta = obj["delta"] as? String {
                                self.streamingContent += delta
                            }
                        case "ai_done":
                            let role = obj["role"] as? String ?? ""
                            let msg = ChatroomMessage(
                                id: self.currentMessages.count + 1,
                                role: role,
                                content: self.streamingContent,
                                model: obj["model"] as? String,
                                created_at: ""
                            )
                            self.currentMessages.append(msg)
                            self.streamingContent = ""
                            self.streamingRole = nil
                        case "round_complete":
                            self.isStreaming = false
                        case "session_ended":
                            self.isStreaming = false
                        default:
                            break
                        }
                    }
                }
            }
        }
    }
}
