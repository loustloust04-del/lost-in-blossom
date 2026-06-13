import Foundation

// MARK: - CC Bridge Provider

final class CCBridgeProvider: BaseChatProvider {
    @ObservationIgnored private let wsClient = CCBridgeWebSocketClient.shared
    /// 当前 in-flight 请求的 grace timer，等 reply 最长 60s；
    /// 期间网络抖动 / send err / reconnect 都不立即 fail，等 hub buffer 重放有机会兜底。
    @ObservationIgnored private var replyTimer: Timer?
    private let replyGracePeriod: TimeInterval = 120
    /// CC Bridge 暂不产生 segments，占位以满足 ChatService 统一赋值
    var onSegmentsCallback: (([MessageSegment]) -> Void)?

    override func sendStreaming(
        messages: [(role: String, content: String)],
        model: String,
        systemPrompt: String?,
        systemLayers: SystemPromptLayers? = nil,
        apiKey: String,
        baseURL: String,
        extraHeaders: [String: String],
        samplingParams: SamplingParams? = nil,
        onToken: @escaping (String) -> Void,
        onComplete: @escaping (String, TokenUsage?) -> Void,
        onError: @escaping (String) -> Void
    ) {
        // sendStreaming 由 ConversationViewModel（@MainActor）调用，整个方法在 main 上跑，
        // 直接写 @Observable 状态是安全的。
        // 重置状态（手动做，不走 resetState，因为我们不用 URLSession）
        self.streamingContent = ""
        self.error = nil
        self.isStreaming = true

        // 1. 取最后一条 user 消息
        //    Task 11 的 ConversationViewModel 已短路 PromptAssembler，messages 只有一条 user
        guard let lastUser = messages.last(where: { $0.role == "user" }) else {
            failNow("没有 user 消息可发", onError: onError)
            return
        }

        // 2. 从 extraHeaders 取路由信息（Task 11 注入），缺失时给防御性默认值
        //    UUID fallback 不会丢消息：我们把同一 id 写进 payload 发给 hub，CC 回复时
        //    带回这个 id，handler 仍能命中。只是这条对话跟 MP 的 MessageNode 失联。
        let chatId    = extraHeaders["X-MP-ChatId"]    ?? UUID().uuidString
        let messageId = extraHeaders["X-MP-MessageId"] ?? UUID().uuidString
        let user      = extraHeaders["X-MP-User"]      ?? "bunny"
        // L2：可选 tmux session（nil = hub 端 fallback 默认 mp-cc）
        let ccSession = extraHeaders["X-MP-CCSession"]

        // 3. 取消上一次的 grace timer（如果有），开始新 60s 计时
        replyTimer?.invalidate()
        replyTimer = nil

        // 4. 先注册 reply handler（即便 WS 还没连上也无妨，dict 里等 reply 到达再触发）
        wsClient.registerReplyHandler(chatId: chatId) { [weak self] replyText in
            guard let self else { return }
            self.replyTimer?.invalidate()
            self.replyTimer = nil
            self.wsClient.unregisterStreamHandler()
            self.isStreaming = false
            // 将本轮 pending thinking 嵌入 content，使历史消息也能展示思考链
            let contentToSave: String
            if let think = self.wsClient.consumePendingThinking(), !think.thinking.isEmpty {
                contentToSave = "[thinking]\(think.thinking)[/thinking]\(replyText)"
            } else {
                contentToSave = replyText
            }
            self.streamingContent = contentToSave
            onComplete(contentToSave, nil)  // CC 不上报 token 用量
        }

        // 4b. cc_stream 流式暂时关闭：capture-pane 无法区分回复文本和 terminal 噪音
        // （工具调用、文件操作、进度条全混在一起）。CC 回复走 replyHandler 一次性干净显示。
        // TODO: 后续用 MCP 工具的 streaming 回调做正确的聊天流式，再打开这里。
        // wsClient.registerStreamHandler { [weak self] token in
        //     guard let self else { return }
        //     self.streamingContent += token
        //     onToken(token)
        // }

        // 5. grace timer：60s 内仍没等到 reply 才 fail
        //    期间 send err / 网络抖动 / reconnect 都不立即 fail，给 hub buffer replay 机会
        replyTimer = Timer.scheduledTimer(withTimeInterval: replyGracePeriod, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.wsClient.unregisterReplyHandler(chatId: chatId)
            self.wsClient.unregisterStreamHandler()
            self.failNow("CC 60 秒内没回（可能 CC 思考超时 / hub 中断 / reply 真的丢了）",
                         onError: onError)
        }

        // 6. 触发连接（如未连）—— 优先用设置页保存的 URL，fallback 到 provider baseURL
        if !wsClient.isConnected {
            let hubURL = UserDefaults.standard.string(forKey: "ccBridgeHubURL") ?? baseURL
            if let url = URL(string: hubURL) {
                let token: String? = { let t = UserDefaults.standard.string(forKey: "ccBridgeHubToken") ?? ""; return t.isEmpty ? nil : t }()
                wsClient.connect(url: url, token: token)
            }
        }

        // 7. 发送 send 帧；send err 不立即 fail，让 grace timer 等 reply
        //    （网络抖动/reconnect 是常态，CC 那边大概率仍能收到我们发的消息且会回复）
        var payload: [String: Any] = [
            "type":       "chat",
            "chat_id":    chatId,
            "message_id": messageId,
            "content":    lastUser.content,
            "user":       user,
        ]
        if let ccSession, !ccSession.isEmpty {
            payload["session_name"] = ccSession
        }
        // CC↔API 上下文共享（正向）：附带本对话 API 侧已压缩的摘要，CC 接话时能看到历史。
        if let ctx = ContextSummarizer.load(conversationId: chatId)?.summary,
           !ctx.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["context"] = ctx
        }
        wsClient.send(payload) { err in
            if let err {
                // 不 unregister、不 failNow——把判定权交给 grace timer。
                // 实测：iPhone connection 抖动时 send 经常返回 error，但 hub 那边消息其实已收到。
                #if DEBUG
                print("[CCBridge] send err (keeping handler alive, grace timer 兜底): \(err.localizedDescription)")
                #endif
            }
        }
    }

    override func sendNonStreaming(
        messages: [(role: String, content: String)],
        model: String,
        systemPrompt: String?,
        apiKey: String,
        baseURL: String,
        extraHeaders: [String: String]
    ) async throws -> (String, TokenUsage?) {
        throw NSError(domain: "CCBridge", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "CC Bridge 不支持非流式调用"])
    }

    override func cancel() {
        // CC 在 tmux 里处理，无法从外部中断；本地只清流式状态 + 清 grace timer
        replyTimer?.invalidate()
        replyTimer = nil
        isStreaming = false
    }

    private func failNow(_ msg: String, onError: @escaping (String) -> Void) {
        DispatchQueue.main.async {
            self.isStreaming = false
            self.error = msg
            onError(msg)
        }
    }
}
