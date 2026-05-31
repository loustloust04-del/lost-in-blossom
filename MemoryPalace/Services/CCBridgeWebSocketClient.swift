import Foundation
import Observation

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
    @ObservationIgnored private var reconnectDelay: TimeInterval = 1
    @ObservationIgnored private var reconnectTimer: Timer?
    @ObservationIgnored private var manualClose = false
    @ObservationIgnored private var replyHandlers: [String: (String) -> Void] = [:]
    @ObservationIgnored private let handlersQueue = DispatchQueue(label: "cc.bridge.handlers")
    /// tool_event 回调：(chatId, toolName, inputJSON, result)
    /// CCBridgeProvider 在发起请求前设置，reply 到达后清除。
    @ObservationIgnored var toolEventHandler: ((String, String, String, String) -> Void)?

    // MARK: - Public API

    /// 开始连接。重复 connect 同一个 URL 且已连接时是 no-op。
    func connect(url: URL) {
        // 已连接 or 正在连接（task 非 nil）且 URL 相同 → no-op，避免叠 task
        if (isConnected || task != nil), self.url == url { return }
        manualClose = false
        self.url = url
        startTask()
    }

    /// 手动断开，禁用自动重连。
    func disconnect() {
        manualClose = true
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        // disconnect() 默认来自主线程 UI；直接同步更新，避免 stale window
        if Thread.isMainThread {
            isConnected = false
        } else {
            DispatchQueue.main.sync { self.isConnected = false }
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
            task.send(.string(str)) { err in completion(err) }
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
                handlersQueue.async { [weak self] in
                    guard let handler = self?.replyHandlers[chatId] else { return }
                    DispatchQueue.main.async { handler(content) }
                }
            }
        case "tool_event":
            // CCBridgeProvider 发起请求时注册，reply 到达后清除
            if let chatId = obj["chat_id"] as? String,
               let toolName = obj["tool_name"] as? String {
                let inputJSON = obj["input_json"] as? String ?? "{}"
                let result    = obj["result"]     as? String ?? ""
                DispatchQueue.main.async { [weak self] in
                    self?.toolEventHandler?(chatId, toolName, inputJSON, result)
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
            self?.isConnected = true
            self?.lastError = nil
            self?.reconnectDelay = 1  // 连接成功后重置退避计数
        }
    }

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        let r = reason.flatMap { String(data: $0, encoding: .utf8) }
        handleDisconnect(error: r ?? "closed (\(closeCode.rawValue))")
    }

    // Trust self-signed certificates (VPS nginx)
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
