# 群聊前端 — App 端 UI

> 猫按顺序做，每个 commit 做完 push。不要一次全做。
> 后端编排器已跑在 VPS 端口 3300。

---

## Commit 1: ChatroomService（网络层）

创建 `MemoryPalace/Services/ChatroomService.swift`

```swift
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
                            // 把完成的消息加入 currentMessages
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
```

---

## Commit 2: ChatroomView（对话界面）

创建 `MemoryPalace/Views/ChatroomView.swift`

一个简单的聊天界面：
- 顶部显示话题和两个 AI 名字
- 消息列表（ScrollView + LazyVStack）
- AI A 的消息：左侧，蓝色气泡
- AI B 的消息：左侧，绿色气泡
- User 的消息：右侧，跟主线一样的颜色
- 正在说话的 AI：底部显示流式文字 + 打字指示器
- 底部栏：
  - TextField 输入框
  - 输入框为空 → 「继续」按钮（调 continueRound）
  - 输入框有字 → 「发送」按钮（调 sendMessage）
- 右上角「结束」按钮

关键点：
- 进入页面时调 `subscribeStream(sessionId:)` 开始接收 SSE
- 每次 round_complete 后调 `fetchHistory` 刷新完整消息列表
- 滚动到底部用 `ScrollViewReader` + `scrollTo`

颜色方案：
- AI A 气泡：`Color.blue.opacity(0.12)`，文字 `Theme.textPrimary`
- AI B 气泡：`Color.green.opacity(0.12)`，文字 `Theme.textPrimary`
- User 气泡：跟主线聊天一样（`Theme.userBubble`）
- 名字标签：气泡上方小字显示 AI 名字

---

## Commit 3: CreateChatroomView（创建页面）

创建 `MemoryPalace/Views/CreateChatroomView.swift`

一个表单页面：
- 话题输入框（TextField，placeholder: "给 AI 们一个话题..."）
- AI A 区域：
  - 名字输入框（默认 "Caelum"）
  - 模型选择器（Picker：deepseek/deepseek-chat, anthropic/claude-sonnet-4, anthropic/claude-opus-4 等）
  - System prompt 输入框（TextEditor，可选）
- AI B 区域：同上（默认名字 "DeepSeek"）
- 「开始」按钮 → 调 startSession → 导航到 ChatroomView

---

## Commit 4: 入口集成

在侧边栏或设置页面加一个「群聊」入口：
- 点击后显示聊天室列表（ChatroomListView）
- 列表每行显示：话题、两个 AI 名字、轮次、状态
- 右上角「+」按钮 → CreateChatroomView
- 点击某个 session → ChatroomView
- 活跃的 session 显示绿色指示器，已结束的显示灰色

入口位置：侧边栏底部，Almond 和 Amber 上面，图标用 `bubble.left.and.bubble.right`

---

## 注意事项

- 编排器地址硬编码 `http://172.245.88.103:3300`，不走 HTTPS（内网直连）
- iOS App Transport Security 需要在 Info.plist 里允许 HTTP（检查是否已配置）
- SSE 用 URLSession.shared.bytes 异步迭代，iOS 15+ 支持
- 不要用 WebSocket，用 SSE（单向推流，更简单）
- 每个独立改动单独 commit，commit message 用英文
