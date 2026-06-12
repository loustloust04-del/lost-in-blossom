import Foundation
import Observation

/// hub 端返回的远程错误（spawn_cc_err / list 失败 / WS send err）。
/// 包成 Error 让 Result<T, CCBridgeRemoteError> 走 Swift Result idiom。
struct CCBridgeRemoteError: LocalizedError {
    let reason: String
    var errorDescription: String? { reason }
}

/// CC 执行任务时推送过来的一段思考链（来自 hub 的 cc_thinking 广播）。
struct CCThinkingBlock: Identifiable {
    let id = UUID()
    let thinking: String
    let sessionId: String
    let timestamp: Date
}

@Observable
final class CCBridgeWebSocketClient: NSObject {
    static let shared = CCBridgeWebSocketClient()

    // MARK: - Public observable state

    private(set) var isConnected: Bool = false
    private(set) var lastError: String?

    /// CC thinking block 按 session_id 存储（hub 通过 cc_thinking 推送）。
    /// 改为字典后，每条会话各自保留自己的思考链，不会被后到的新 thinking 覆盖。
    private(set) var thinkingBlocks: [String: CCThinkingBlock] = [:]

    /// 最新一条 thinking 的快捷访问（向后兼容）。@Observable 计算属性，随 thinkingBlocks 变化更新。
    var latestThinking: CCThinkingBlock? {
        thinkingBlocks.values.max(by: { $0.timestamp < $1.timestamp })
    }

    /// 未被消费的最新 thinking（每轮回复来临时消费一次，嵌入 content）。
    @ObservationIgnored private var pendingThinking: CCThinkingBlock? = nil

    /// 取并清除 pending thinking（供 CCBridgeProvider 在 reply 到达时调用）。
    func consumePendingThinking() -> CCThinkingBlock? {
        let block = pendingThinking
        pendingThinking = nil
        return block
    }

    /// CC 终端的最新流式输出（hub 通过 cc_stream 推送）。
    private(set) var streamContent: String = ""
    /// CC 是否正在输出。
    private(set) var isCCStreaming: Bool = false
    /// CC 流式输出回调：每个 cc_stream token 到达时触发
    private var streamHandler: ((String) -> Void)?

    // MARK: - Private state

    @ObservationIgnored private var task: URLSessionWebSocketTask?
    @ObservationIgnored private var session: URLSession?
    @ObservationIgnored private var url: URL?
    /// 候选 URL 列表（含 token）。主 URL 为 urls[0]，断开时 reconnect 轮换到下一个。
    /// 这样在家 LAN 主 + 出门 Tailscale 备用，能自动 fallback。
    @ObservationIgnored private var urls: [URL] = []
    @ObservationIgnored private var currentIndex: Int = 0
    @ObservationIgnored private var reconnectDelay: TimeInterval = 1
    @ObservationIgnored private var reconnectTimer: Timer?
    @ObservationIgnored private var pingTimer: Timer?
    @ObservationIgnored private var manualClose = false
    @ObservationIgnored private var replyHandlers: [String: (String) -> Void] = [:]
    /// L2: spawn 结果回调，key = 请求时的 session_name
    @ObservationIgnored private var spawnHandlers: [String: (Result<Void, CCBridgeRemoteError>) -> Void] = [:]
    /// L2: list_sessions 回调队列（不带 key，每个 list 请求都会用最早注册的 handler 接收第一个结果）
    @ObservationIgnored private var listHandlers: [(Result<[String], CCBridgeRemoteError>) -> Void] = []
    @ObservationIgnored private let handlersQueue = DispatchQueue(label: "cc.bridge.handlers")
    /// 已 deliver 的 reply_id 缓存（hub 在 reconnect 时会 replay 最近 60s reply，
    /// client 端去重避免同一条投递两次）。5 分钟 TTL 足够长。
    @ObservationIgnored private var seenReplyIds: [String: Date] = [:]
    private let replyDedupTTL: TimeInterval = 300

    // MARK: - Terminal streaming (Phase 2)

    private struct TerminalHandlers {
        let onInit: (Data) -> Void
        let onChunk: (Data) -> Void
        let onError: (String) -> Void
    }
    @ObservationIgnored private var terminalHandlers: [String: TerminalHandlers] = [:]

    // MARK: - File exchange (Phase 4.2)

    /// Called when a reply arrives with a file attachment (CC→user). Fires on main queue.
    @ObservationIgnored private var replyAttachmentHandlers: [String: (PendingChatAttachment) -> Void] = [:]

    // MARK: - Push notifications

    @ObservationIgnored private var pushToken: String?

    static let pushPreviewKey = "ccPushPreview"
    private var pushPreview: String { UserDefaults.standard.string(forKey: Self.pushPreviewKey) ?? "full" }

    func sendAppState(_ state: String) {
        send(["type": "app_state", "state": state]) { _ in }
    }

    func sendPushToken(_ token: String) {
        pushToken = token
        send(["type": "register_device", "device_token": token, "env": "sandbox", "preview": pushPreview]) { _ in }
    }

    func updatePushPreview(_ mode: String) {
        UserDefaults.standard.set(mode, forKey: Self.pushPreviewKey)
        if let t = pushToken {
            send(["type": "register_device", "device_token": t, "env": "sandbox", "preview": mode]) { _ in }
        }
    }

    func sendCCConfig() {
        let d = UserDefaults.standard
        var payload: [String: Any] = [
            "type": "set_cc_config",
            "pushName": (d.string(forKey: "assistantName") ?? "助手"),
            "userName": (d.string(forKey: "userName") ?? "你"),
            "nudgeEnabled": (d.object(forKey: "ccNudgeEnabled") as? Bool) ?? true,
        ]
        if let v = d.object(forKey: "ccNudgeIdleMin") as? Int, v > 0 { payload["idleMinMin"] = v }
        if let v = d.object(forKey: "ccNudgeIdleMax") as? Int, v > 0 { payload["idleMaxMin"] = v }
        if let v = d.object(forKey: "ccNudgeQuietStartMin") as? Int { payload["quietStartMin"] = v }
        if let v = d.object(forKey: "ccNudgeQuietEndMin") as? Int { payload["quietEndMin"] = v }
        if let v = d.object(forKey: "ccNudgeCooldown") as? Int, v >= 0 { payload["cooldownMin"] = v }
        if let t = d.string(forKey: "ccNudgeTemplate"), !t.isEmpty { payload["nudgeTemplate"] = t }
        send(payload) { _ in }
    }

    // MARK: - Public API

    /// 开始连接。重复 connect 同一个 URL（含 token）且已连接时是 no-op。
    func connect(url: URL, token: String? = nil) {
        connect(urls: [url], token: token)
    }

    /// 开始连接，支持多 URL fallback。优先连 urls[0]，失败 reconnect 时轮换到下一个。
    /// 典型用法：urls = [LAN URL, Tailscale URL]，在家走 LAN，出门走 Tailscale。
    func connect(urls inputURLs: [URL], token: String? = nil) {
        print("[CCBridge] connect called, urls=\(inputURLs), isConnected=\(isConnected), hasTask=\(task != nil)")
        let finalURLs = inputURLs.map { url -> URL in
            guard let token, !token.isEmpty,
                  var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return url
            }
            var items = components.queryItems ?? []
            items.removeAll(where: { $0.name == "token" })  // 避免重复 token=
            items.append(URLQueryItem(name: "token", value: token))
            components.queryItems = items
            return components.url ?? url
        }

        // 已连接 or 正在连接 且候选列表完全一致 → no-op，避免叠 task
        if (isConnected || task != nil), self.urls == finalURLs { return }
        manualClose = false
        self.urls = finalURLs
        self.currentIndex = 0
        self.url = finalURLs.first
        startTask()
    }

    /// 手动断开，禁用自动重连。
    func disconnect() {
        manualClose = true
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        pingTimer?.invalidate()
        pingTimer = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        urls = []
        url = nil
        // disconnect() 默认来自主线程 UI；直接同步更新，避免 stale window
        if Thread.isMainThread {
            isConnected = false
        } else {
            DispatchQueue.main.sync { self.isConnected = false }
        }
    }

    /// 强制重连：断开旧连接，等待底层 TCP 资源释放后重建。
    /// 给 UI 按钮用——比 disconnect()+connect() 更可靠。
    func forceReconnect(url: URL, token: String? = nil) {
        print("[CCBridge] forceReconnect called, url=\(url)")
        disconnect()
        print("[CCBridge] disconnected, scheduling connect in 0.3s")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { print("[CCBridge] self is nil after delay"); return }
            print("[CCBridge] connecting to \(url)")
            self.connect(url: url, token: token)
        }
    }

    /// JSON 序列化后以文本帧发出。
    func send(_ payload: [String: Any], completion: @escaping (Error?) -> Void) {
        guard let task else {
            completion(NSError(domain: "CCBridge", code: -10,
                               userInfo: [NSLocalizedDescriptionKey: "WebSocket 未连接"]))
            return
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            guard let str = String(data: data, encoding: .utf8) else {
                completion(NSError(domain: "CCBridge", code: -11,
                                   userInfo: [NSLocalizedDescriptionKey: "payload 编码失败"]))
                return
            }
            task.send(.string(str)) { err in
                completion(err)
            }
        } catch {
            completion(error)
        }
    }

    /// 注册一个 chat_id 对应的回复处理器（Task 9 的 CCBridgeProvider 使用）。
    /// handler 在 main queue 上调用。
    func registerStreamHandler(_ handler: @escaping (String) -> Void) {
        streamHandler = handler
    }
    func unregisterStreamHandler() {
        streamHandler = nil
    }

    func registerReplyHandler(chatId: String, handler: @escaping (String) -> Void) {
        handlersQueue.async { self.replyHandlers[chatId] = handler }
    }

    /// 取消注册（onComplete 后由 CCBridgeProvider 调用）。
    func unregisterReplyHandler(chatId: String) {
        handlersQueue.async { self.replyHandlers.removeValue(forKey: chatId) }
    }

    // MARK: - L2: spawn / list sessions

    /// 让 hub 在远端 tmux 起一个新 CC session（不 --continue）。
    /// 完成回调走 main queue。注意：CC 启动需要 ~3-5s，hub 是否成功 spawn 只看
    /// tmux new-session 是否成功；CC 本身起没起 / mcp-server 连没连这里不验证。
    func spawnSession(_ name: String, completion: @escaping (Result<Void, CCBridgeRemoteError>) -> Void) {
        handlersQueue.async { self.spawnHandlers[name] = completion }
        let payload: [String: Any] = ["type": "spawn_cc", "session_name": name]
        send(payload) { [weak self] err in
            guard let self, let err else { return }
            // send 即失败 → 立即 fail，不等 hub 回包
            self.handlersQueue.async {
                if let h = self.spawnHandlers.removeValue(forKey: name) {
                    DispatchQueue.main.async { h(.failure(CCBridgeRemoteError(reason: err.localizedDescription))) }
                }
            }
        }
    }

    /// 拉 hub 端当前 tmux mp-cc* sessions 列表。完成回调走 main queue。
    func listSessions(completion: @escaping (Result<[String], CCBridgeRemoteError>) -> Void) {
        handlersQueue.async { self.listHandlers.append(completion) }
        let payload: [String: Any] = ["type": "list_sessions"]
        send(payload) { [weak self] err in
            guard let self, let err else { return }
            self.handlersQueue.async {
                let hs = self.listHandlers
                self.listHandlers.removeAll()
                for h in hs {
                    DispatchQueue.main.async { h(.failure(CCBridgeRemoteError(reason: err.localizedDescription))) }
                }
            }
        }
    }

    // MARK: - File exchange public API (Phase 4.2)

    /// Send a chat message optionally carrying image/file attachments.
    /// Images → `images` array; other files → `files` array, each base64-encoded.
    func sendChat(
        chatId: String,
        messageId: String,
        content: String,
        attachments: [PendingChatAttachment] = [],
        completion: @escaping (Error?) -> Void
    ) {
        var images: [[String: String]] = []
        var files: [[String: String]] = []

        for att in attachments {
            if att.isImage, let data = att.imageData {
                images.append([
                    "b64": data.base64EncodedString(),
                    "mime": att.mimeType ?? "image/jpeg",
                ])
            } else if let data = att.fileData ?? att.imageData {
                files.append([
                    "b64": data.base64EncodedString(),
                    "name": att.name,
                    "mime": att.mimeType ?? "application/octet-stream",
                ])
            }
        }

        var payload: [String: Any] = [
            "type": "chat",
            "chat_id": chatId,
            "message_id": messageId,
            "content": content,
        ]
        if !images.isEmpty { payload["images"] = images }
        if !files.isEmpty  { payload["files"]  = files  }
        send(payload, completion: completion)
    }

    /// Register a handler for file attachments arriving in CC replies (fires on main queue).
    func registerReplyAttachmentHandler(chatId: String, handler: @escaping (PendingChatAttachment) -> Void) {
        handlersQueue.async { self.replyAttachmentHandlers[chatId] = handler }
    }

    func unregisterReplyAttachmentHandler(chatId: String) {
        handlersQueue.async { self.replyAttachmentHandlers.removeValue(forKey: chatId) }
    }

    // MARK: - Terminal streaming public API (Phase 2)

    /// Attach to a tmux session's terminal stream. Callbacks fire on main queue.
    func attachTerminal(
        session: String,
        cols: Int,
        rows: Int,
        onInit: @escaping (Data) -> Void,
        onChunk: @escaping (Data) -> Void,
        onError: @escaping (String) -> Void
    ) {
        handlersQueue.async {
            self.terminalHandlers[session] = TerminalHandlers(onInit: onInit, onChunk: onChunk, onError: onError)
        }
        let payload: [String: Any] = [
            "type": "terminal_attach",
            "session_name": session,
            "cols": cols,
            "rows": rows,
        ]
        send(payload) { [weak self] err in
            guard let self, let err else { return }
            DispatchQueue.main.async { onError(err.localizedDescription) }
            self.handlersQueue.async { self.terminalHandlers.removeValue(forKey: session) }
        }
    }

    /// Detach from a session's terminal stream.
    func detachTerminal(session: String) {
        handlersQueue.async { self.terminalHandlers.removeValue(forKey: session) }
        send(["type": "terminal_detach", "session_name": session]) { _ in }
    }

    /// Send raw input bytes (keystrokes, escape sequences) to the session.
    func sendTerminalInput(session: String, bytes: Data) {
        guard !bytes.isEmpty,
              let text = String(data: bytes, encoding: .utf8) else { return }
        send(["type": "terminal_input", "session_name": session, "data": text]) { _ in }
    }

    /// Notify hub that the terminal view resized.
    func sendTerminalResize(session: String, cols: Int, rows: Int) {
        let payload: [String: Any] = [
            "type": "terminal_resize",
            "session_name": session,
            "cols": cols,
            "rows": rows,
        ]
        send(payload) { _ in }
    }

    /// Request a fresh screen snapshot (re-sends terminal_attach to trigger terminal_init).
    func refreshTerminal(session: String) {
        send(["type": "terminal_attach", "session_name": session]) { _ in }
    }

    // MARK: - Internal

    private func startTask() {
        guard let url else { print("[CCBridge] startTask: url is nil"); return }
        print("[CCBridge] startTask: \(url)")
        session?.invalidateAndCancel()  // 释放旧 session（避免 reconnect 累积资源）
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        receiveLoop()
    }

    private func receiveLoop() {
        guard let currentTask = task else { return }
        currentTask.receive { [weak self] result in
            // 旧 task 完成后 self.task 已被替换，直接忽略以免触发 ghost reconnect
            guard let self, self.task === currentTask else { return }
            switch result {
            case .failure(let err):
                self.handleDisconnect(error: err.localizedDescription)
            case .success(.string(let text)):
                self.handleIncoming(text)
                self.receiveLoop()
            case .success(.data(let data)):
                if let text = String(data: data, encoding: .utf8) {
                    self.handleIncoming(text)
                }
                self.receiveLoop()
            @unknown default:
                self.receiveLoop()
            }
        }
    }

    private func handleIncoming(_ text: String) {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return }

        switch type {
        case "reply":
            if let chatId = obj["chat_id"] as? String,
               let content = obj["content"] as? String {
                // reply_id dedup（hub 在 reconnect 时会 replay 最近 60s reply）
                let replyId = obj["reply_id"] as? String
                // Parse optional file attachment (CC→user, Phase 4.2)
                let incomingFile: PendingChatAttachment? = {
                    guard let fileObj = obj["file"] as? [String: Any],
                          let b64  = fileObj["data"]     as? String,
                          let mime = fileObj["mime"]     as? String,
                          let name = fileObj["name"]     as? String,
                          let data = Data(base64Encoded: b64) else { return nil }
                    let isImg = (fileObj["is_image"] as? Bool) ?? mime.hasPrefix("image/")
                    if isImg {
                        return try? PendingChatAttachment.image(
                            name: name, typeDescription: mime, mimeType: mime, data: data)
                    }
                    return PendingChatAttachment.text(
                        name: name, typeDescription: mime, extractedText: "",
                        byteCount: data.count, fileData: data, fileMime: mime)
                }()
                handlersQueue.async { [weak self] in
                    guard let self else { return }
                    if let replyId {
                        if let lastSeen = self.seenReplyIds[replyId],
                           Date().timeIntervalSince(lastSeen) < self.replyDedupTTL {
                            return  // 重复，silently drop
                        }
                        self.seenReplyIds[replyId] = Date()
                        // 清理过期 entries
                        let cutoff = Date().addingTimeInterval(-self.replyDedupTTL)
                        self.seenReplyIds = self.seenReplyIds.filter { $0.value >= cutoff }
                    }
                    if let handler = self.replyHandlers[chatId] {
                        DispatchQueue.main.async { handler(content) }
                    }
                    if let att = incomingFile, let attHandler = self.replyAttachmentHandlers[chatId] {
                        DispatchQueue.main.async { attHandler(att) }
                    }
                }
            }
        case "ack":
            // v1 no-op；后续版本可用于确认送达
            break
        case "error":
            let reason = (obj["reason"] as? String) ?? "unknown"
            DispatchQueue.main.async { [weak self] in
                self?.lastError = reason
            }
        case "spawn_cc_ok":
            if let name = obj["session_name"] as? String {
                handlersQueue.async { [weak self] in
                    guard let self else { return }
                    if let h = self.spawnHandlers.removeValue(forKey: name) {
                        DispatchQueue.main.async { h(.success(())) }
                    }
                }
            }
        case "spawn_cc_err":
            let name = obj["session_name"] as? String ?? ""
            let reason = obj["reason"] as? String ?? "unknown"
            handlersQueue.async { [weak self] in
                guard let self else { return }
                if let h = self.spawnHandlers.removeValue(forKey: name) {
                    DispatchQueue.main.async { h(.failure(CCBridgeRemoteError(reason: reason))) }
                }
            }
        case "cc_thinking":
            if let thinking = obj["thinking"] as? String {
                let sessionId = obj["session_id"] as? String ?? ""
                let now = Date()
                let block = CCThinkingBlock(
                    thinking: thinking,
                    sessionId: sessionId,
                    timestamp: now
                )
                // 用时间戳做唯一 key，避免同一 session 多轮 thinking 互相覆盖
                let uniqueKey = "\(sessionId)_\(now.timeIntervalSince1970)"
                DispatchQueue.main.async { [weak self] in
                    self?.thinkingBlocks[uniqueKey] = block
                    self?.pendingThinking = block  // 等待下一条 reply 消费嵌入
                }
            }
        case "cc_stream":
            if let content = obj["content"] as? String {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if !self.isCCStreaming {
                        self.streamContent = ""  // 新一轮，先清空旧内容
                    }
                    self.streamContent += content
                    self.isCCStreaming = true
                    self.streamHandler?(content)
                }
            }
        case "cc_stream_end":
            DispatchQueue.main.async { [weak self] in
                self?.isCCStreaming = false
                // 不清空 streamContent，等下一次 cc_stream 开始时再清
            }
        case "list_sessions_result":
            let sessions = obj["sessions"] as? [String] ?? []
            handlersQueue.async { [weak self] in
                guard let self else { return }
                let hs = self.listHandlers
                self.listHandlers.removeAll()
                for h in hs {
                    DispatchQueue.main.async { h(.success(sessions)) }
                }
            }
        case "terminal_init":
            if let sessionName = obj["session_name"] as? String,
               let snapshot = obj["snapshot"] as? String {
                let data = snapshot.data(using: .utf8) ?? Data()
                handlersQueue.async { [weak self] in
                    guard let h = self?.terminalHandlers[sessionName] else { return }
                    DispatchQueue.main.async { h.onInit(data) }
                }
            }
        case "terminal_chunk":
            if let sessionName = obj["session_name"] as? String,
               let b64 = obj["bytes"] as? String,
               let data = Data(base64Encoded: b64) {
                handlersQueue.async { [weak self] in
                    guard let h = self?.terminalHandlers[sessionName] else { return }
                    DispatchQueue.main.async { h.onChunk(data) }
                }
            }
        default:
            break
        }
    }

    private func handleDisconnect(error: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isConnected = false
            self.lastError = error
            if !self.manualClose {
                self.scheduleReconnect()
            }
        }
    }

    private func scheduleReconnect() {
        reconnectTimer?.invalidate()
        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, 30)
        // 多 URL 时，每次 reconnect 轮换到下一个候选（fallback to backup URL）
        if urls.count > 1 {
            currentIndex = (currentIndex + 1) % urls.count
            self.url = urls[currentIndex]
        }
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.startTask()
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension CCBridgeWebSocketClient: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocolName: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // 老 session 在 invalidateAndCancel 后回调可能跟新 task didOpen race，
            // 只认当前 self.task 的回调，避免被替换掉的老 task 污染状态
            guard webSocketTask === self.task else { return }
            self.isConnected = true
            self.lastError = nil
            self.reconnectDelay = 1  // 连接成功后重置退避计数
            self.currentIndex = 0    // 下次断重连优先回主 URL
            self.startPingTimer()
        }
    }

    private func startPingTimer() {
        pingTimer?.invalidate()
        // iOS 上 URLSessionWebSocketTask 不自动 keepalive，长 idle 会被 OS 杀。
        // 每 5s 主动发 ping 保活。
        pingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let task = self?.task, task.state == .running else { return }
            task.sendPing { _ in /* 失败由 receive 路径反映为 disconnect */ }
        }
    }

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        // startTask() 里 invalidateAndCancel 老 session 会异步触发老 task 的 didClose，
        // 那次 close 是我们主动 cancel 的预期结果，不该再起一轮 ghost reconnect。
        // 只对当前 self.task 的真实关闭做 disconnect 处理。
        guard webSocketTask === self.task else { return }
        let r = reason.flatMap { String(data: $0, encoding: .utf8) }
        handleDisconnect(error: r ?? "closed (\(closeCode.rawValue))")
    }
}
