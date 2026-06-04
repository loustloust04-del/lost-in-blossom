import Foundation
import Observation

/// hub 端返回的远程错误（spawn_cc_err / list 失败 / WS send err）。
/// 包成 Error 让 Result<T, CCBridgeRemoteError> 走 Swift Result idiom。
struct CCBridgeRemoteError: LocalizedError {
    let reason: String
    var errorDescription: String? { reason }
}

@Observable
final class CCBridgeWebSocketClient: NSObject {
    static let shared = CCBridgeWebSocketClient()

    // MARK: - Public observable state

    private(set) var isConnected: Bool = false
    private(set) var lastError: String?

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

    // MARK: - Public API

    /// 开始连接。重复 connect 同一个 URL（含 token）且已连接时是 no-op。
    func connect(url: URL, token: String? = nil) {
        connect(urls: [url], token: token)
    }

    /// 开始连接，支持多 URL fallback。优先连 urls[0]，失败 reconnect 时轮换到下一个。
    /// 典型用法：urls = [LAN URL, Tailscale URL]，在家走 LAN，出门走 Tailscale。
    func connect(urls inputURLs: [URL], token: String? = nil) {
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
        disconnect()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.connect(url: url, token: token)
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

    // MARK: - Internal

    private func startTask() {
        guard let url else { return }
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
                    guard let handler = self.replyHandlers[chatId] else { return }
                    DispatchQueue.main.async { handler(content) }
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
