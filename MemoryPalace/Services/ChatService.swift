import Foundation

// MARK: - Chat Provider Protocol

@Observable
class BaseChatProvider: NSObject {
    var isStreaming = false
    var streamingContent = ""
    var error: String?

    fileprivate var currentTask: URLSessionDataTask?
    fileprivate var urlSession: URLSession?
    fileprivate var buffer = ""
    fileprivate var errorBody = ""
    fileprivate var httpStatusCode: Int = 0
    fileprivate var receivedDone = false
    fileprivate var onToken: ((String) -> Void)?
    fileprivate var onComplete: ((String, TokenUsage?) -> Void)?
    fileprivate var onError: ((String) -> Void)?
    /// 流式过程中累积的 token 用量。usage 信息常在 stream 末尾或分事件到来。
    fileprivate var accumulatedInputTokens: Int = 0
    fileprivate var accumulatedOutputTokens: Int = 0
    fileprivate var gotUsage = false

    fileprivate var finalUsage: TokenUsage? {
        gotUsage ? TokenUsage(inputTokens: accumulatedInputTokens, outputTokens: accumulatedOutputTokens) : nil
    }

    func sendStreaming(
        messages: [(role: String, content: String)],
        model: String,
        systemPrompt: String?,
        apiKey: String,
        baseURL: String,
        extraHeaders: [String: String],
        samplingParams: SamplingParams? = nil,
        onToken: @escaping (String) -> Void,
        onComplete: @escaping (String, TokenUsage?) -> Void,
        onError: @escaping (String) -> Void
    ) {
        fatalError("Subclass must implement")
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        urlSession = nil
        isStreaming = false
    }

    fileprivate func resetState(onToken: @escaping (String) -> Void, onComplete: @escaping (String, TokenUsage?) -> Void, onError: @escaping (String) -> Void) {
        cancel()
        self.onToken = onToken
        self.onComplete = onComplete
        self.onError = onError
        self.streamingContent = ""
        self.error = nil
        self.isStreaming = true
        self.buffer = ""
        self.errorBody = ""
        self.httpStatusCode = 0
        self.receivedDone = false
        self.accumulatedInputTokens = 0
        self.accumulatedOutputTokens = 0
        self.gotUsage = false
    }

    fileprivate func startRequest(_ request: URLRequest) {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.urlSession = session
        let task = session.dataTask(with: request)
        currentTask = task
        task.resume()
    }

    fileprivate func handleErrorBody() -> String {
        var msg = "API 错误 (\(httpStatusCode))"
        if let data = errorBody.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let err = obj["error"] as? [String: Any], let detail = err["message"] as? String {
                msg = detail
            } else if let err = obj["error"] as? String {
                msg = err
            }
        }
        return msg
    }

    /// 非流式调用 — 用于 memory agent 等后台任务
    func sendNonStreaming(
        messages: [(role: String, content: String)],
        model: String,
        systemPrompt: String?,
        apiKey: String,
        baseURL: String,
        extraHeaders: [String: String]
    ) async throws -> (String, TokenUsage?) {
        fatalError("Subclass must implement")
    }

    /// 从非流式响应体中提取错误信息
    fileprivate static func extractError(from data: Data, statusCode: Int) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let err = obj["error"] as? [String: Any], let msg = err["message"] as? String {
                return msg
            } else if let err = obj["error"] as? String {
                return err
            }
        }
        return "API 错误 (\(statusCode))"
    }
}

extension BaseChatProvider: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        processData(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        DispatchQueue.main.async { [self] in
            let wasStreaming = isStreaming
            isStreaming = false
            urlSession = nil

            if let error = error as? NSError, error.code != NSURLErrorCancelled {
                let msg = error.localizedDescription
                self.error = msg
                onError?(msg)
                return
            }

            if receivedDone { return }

            if httpStatusCode != 0 && httpStatusCode != 200 {
                let msg = handleErrorBody()
                self.error = msg
                onError?(msg)
                return
            }

            if wasStreaming {
                if streamingContent.isEmpty {
                    let msg = "未收到回复"
                    self.error = msg
                    onError?(msg)
                } else {
                    onComplete?(streamingContent, finalUsage)
                }
            }
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse {
            httpStatusCode = http.statusCode
        }
        completionHandler(.allow)
    }

    /// Override in subclass for provider-specific SSE parsing
    @objc func processData(_ data: Data) {
        // default: no-op
    }
}

// MARK: - OpenAI Compatible Provider

final class OpenAICompatibleProvider: BaseChatProvider {
    /// DeepSeek reasoning_content 流式 buffer（其他模型为空）
    private var streamingThinking: String = ""
    /// 流式结束时若有 thinking 内容则调用（构造 MessageSegment 列表）
    var onSegmentsCallback: (([MessageSegment]) -> Void)?
    /// 实时发送每个 reasoning_content chunk（逐字显示思考链用）
    var onThinkingToken: ((String) -> Void)?

    override func sendStreaming(
        messages: [(role: String, content: String)],
        model: String,
        systemPrompt: String?,
        apiKey: String,
        baseURL: String,
        extraHeaders: [String: String],
        samplingParams: SamplingParams? = nil,
        onToken: @escaping (String) -> Void,
        onComplete: @escaping (String, TokenUsage?) -> Void,
        onError: @escaping (String) -> Void
    ) {
        resetState(onToken: onToken, onComplete: onComplete, onError: onError)
        streamingThinking = ""

        var apiMessages: [[String: String]] = []
        if let sys = systemPrompt, !sys.isEmpty {
            apiMessages.append(["role": "system", "content": sys])
        }
        for msg in messages {
            apiMessages.append(["role": msg.role, "content": msg.content])
        }

        var body: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "stream": true,
            // 让流式响应最后一个 chunk 带上 usage 字段（保险闸回填用）
            "stream_options": ["include_usage": true],
        ]
        if let p = samplingParams {
            if p.temperature != 1.0 { body["temperature"] = p.temperature }
            if p.topP != 1.0 { body["top_p"] = p.topP }
            if p.maxTokens != 4096 { body["max_tokens"] = p.maxTokens }
            if p.frequencyPenalty != 0 { body["frequency_penalty"] = p.frequencyPenalty }
            if p.presencePenalty != 0 { body["presence_penalty"] = p.presencePenalty }
            if p.seed >= 0 { body["seed"] = p.seed }
            if p.reasoningEffort != "auto" { body["reasoning_effort"] = p.reasoningEffort }
            body["stream"] = p.streaming
        }

        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            onError("无效的 API 地址: \(baseURL)")
            isStreaming = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        startRequest(request)
    }

    override func sendNonStreaming(
        messages: [(role: String, content: String)],
        model: String,
        systemPrompt: String?,
        apiKey: String,
        baseURL: String,
        extraHeaders: [String: String]
    ) async throws -> (String, TokenUsage?) {
        var apiMessages: [[String: String]] = []
        if let sys = systemPrompt, !sys.isEmpty {
            apiMessages.append(["role": "system", "content": sys])
        }
        for msg in messages {
            apiMessages.append(["role": msg.role, "content": msg.content])
        }

        let body: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "stream": false,
        ]

        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw NSError(domain: "ChatService", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的 API 地址"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard statusCode == 200 else {
            throw NSError(domain: "ChatService", code: statusCode,
                          userInfo: [NSLocalizedDescriptionKey: Self.extractError(from: data, statusCode: statusCode)])
        }

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "ChatService", code: -2, userInfo: [NSLocalizedDescriptionKey: "无法解析响应"])
        }

        var usage: TokenUsage? = nil
        if let u = obj["usage"] as? [String: Any],
           let pt = u["prompt_tokens"] as? Int,
           let ct = u["completion_tokens"] as? Int {
            usage = TokenUsage(inputTokens: pt, outputTokens: ct)
        }

        return (content, usage)
    }

    override func processData(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }

        if httpStatusCode != 0 && httpStatusCode != 200 {
            errorBody += text
            return
        }

        buffer += text

        while let lineEnd = buffer.firstIndex(of: "\n") {
            let line = String(buffer[buffer.startIndex..<lineEnd])
            buffer = String(buffer[buffer.index(after: lineEnd)...])

            if line.hasPrefix("data: ") {
                let payload = String(line.dropFirst(6))
                if payload == "[DONE]" {
                    receivedDone = true
                    DispatchQueue.main.async { [self] in
                        isStreaming = false
                        // DeepSeek reasoning：将思考链用标记包裹后拼入 content
                        var finalContent = streamingContent
                        if !streamingThinking.isEmpty {
                            finalContent = "[thinking]\(streamingThinking)[/thinking]\n\(streamingContent)"
                        }
                        onComplete?(finalContent, finalUsage)
                    }
                    return
                }
                parseOpenAIChunk(payload)
            }
        }
    }

    private func parseOpenAIChunk(_ json: String) {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        // usage 字段可能出现在任何 chunk（通常是最后一个，include_usage=true 时）
        if let u = obj["usage"] as? [String: Any],
           let pt = u["prompt_tokens"] as? Int,
           let ct = u["completion_tokens"] as? Int {
            accumulatedInputTokens = pt
            accumulatedOutputTokens = ct
            gotUsage = true
        }

        guard let choices = obj["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any]
        else {
            if let err = obj["error"] as? [String: Any],
               let message = err["message"] as? String {
                DispatchQueue.main.async { [self] in
                    isStreaming = false
                    error = message
                    onError?(message)
                }
            }
            return
        }

        // DeepSeek reasoning model：思考链字段
        if let reasoning = delta["reasoning_content"] as? String, !reasoning.isEmpty {
            DispatchQueue.main.async { [self] in
                streamingThinking += reasoning
                onThinkingToken?(reasoning)  // 实时推送每个 chunk
            }
        }

        if let content = delta["content"] as? String {
            DispatchQueue.main.async { [self] in
                streamingContent += content
                onToken?(content)
            }
        }
    }
}

// MARK: - Anthropic Provider

/// 在 content_block_start 时创建，在 content_block_stop 时 finalize.
private struct ActiveBlock {
    enum Kind {
        case text
        case toolUse(id: String, name: String)
        case toolResult(toolUseId: String)
    }
    var kind: Kind
    var accumulated: String = ""
}

final class AnthropicProvider: BaseChatProvider {
    private var currentEventType = ""

    /// 由 ProviderRouter 在调用 sendStreaming() 前设置. 为空则不使用 MCP.
    var mcpServersToInject: [MCPServerConfig] = []

    /// 流式完成后仅在存在 tool 段时调用. ConversationViewModel 用于 setSegments().
    var onSegmentsCallback: (([MessageSegment]) -> Void)?

    /// index → 进行中的 content block 状态
    private var activeBlocks: [Int: ActiveBlock] = [:]

    /// content_block_stop 时已完成的段（text + tool，保持顺序）
    private var pendingSegments: [MessageSegment] = []

    override func sendStreaming(
        messages: [(role: String, content: String)],
        model: String,
        systemPrompt: String?,
        apiKey: String,
        baseURL: String,
        extraHeaders: [String: String],
        samplingParams: SamplingParams? = nil,
        onToken: @escaping (String) -> Void,
        onComplete: @escaping (String, TokenUsage?) -> Void,
        onError: @escaping (String) -> Void
    ) {
        resetState(onToken: onToken, onComplete: onComplete, onError: onError)
        currentEventType = ""
        activeBlocks = [:]
        pendingSegments = []

        // Build Anthropic Messages API format
        var apiMessages: [[String: Any]] = []
        for msg in messages {
            apiMessages.append(["role": msg.role, "content": msg.content])
        }

        let maxTok = samplingParams?.maxTokens ?? 4096
        var body: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "max_tokens": maxTok,
            "stream": true,
        ]
        if let sys = systemPrompt, !sys.isEmpty {
            body["system"] = sys
        }
        if let p = samplingParams {
            if p.temperature != 1.0 { body["temperature"] = p.temperature }
            if p.topP != 1.0 { body["top_p"] = p.topP }
            if p.topK > 0 { body["top_k"] = p.topK }
            body["stream"] = p.streaming
        }

        // MCP servers injection (Anthropic mcp_servers beta)
        let enabledMCP = mcpServersToInject.filter(\.isEnabled)
        if !enabledMCP.isEmpty {
            body["mcp_servers"] = enabledMCP.map { s -> [String: Any] in
                ["type": "url", "url": s.url, "name": s.name]
            }
        }

        guard let url = URL(string: "\(baseURL)/messages") else {
            onError("无效的 API 地址: \(baseURL)")
            isStreaming = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        // MCP beta header (only when MCP servers are active)
        if !enabledMCP.isEmpty {
            request.setValue("mcp-client-0.1", forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        startRequest(request)
    }

    override func sendNonStreaming(
        messages: [(role: String, content: String)],
        model: String,
        systemPrompt: String?,
        apiKey: String,
        baseURL: String,
        extraHeaders: [String: String]
    ) async throws -> (String, TokenUsage?) {
        var apiMessages: [[String: Any]] = []
        for msg in messages {
            apiMessages.append(["role": msg.role, "content": msg.content])
        }

        var body: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "max_tokens": 1024,
        ]
        if let sys = systemPrompt, !sys.isEmpty {
            body["system"] = sys
        }

        guard let url = URL(string: "\(baseURL)/messages") else {
            throw NSError(domain: "ChatService", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的 API 地址"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard statusCode == 200 else {
            throw NSError(domain: "ChatService", code: statusCode,
                          userInfo: [NSLocalizedDescriptionKey: Self.extractError(from: data, statusCode: statusCode)])
        }

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentArray = obj["content"] as? [[String: Any]],
              let text = contentArray.first?["text"] as? String else {
            throw NSError(domain: "ChatService", code: -2, userInfo: [NSLocalizedDescriptionKey: "无法解析响应"])
        }

        var usage: TokenUsage? = nil
        if let u = obj["usage"] as? [String: Any],
           let it = u["input_tokens"] as? Int,
           let ot = u["output_tokens"] as? Int {
            usage = TokenUsage(inputTokens: it, outputTokens: ot)
        }

        return (text, usage)
    }

    override func processData(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }

        if httpStatusCode != 0 && httpStatusCode != 200 {
            errorBody += text
            return
        }

        buffer += text

        while let lineEnd = buffer.firstIndex(of: "\n") {
            let line = String(buffer[buffer.startIndex..<lineEnd])
            buffer = String(buffer[buffer.index(after: lineEnd)...])

            if line.hasPrefix("event: ") {
                currentEventType = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data: ") {
                let payload = String(line.dropFirst(6))
                handleAnthropicEvent(type: currentEventType, data: payload)
            }
        }
    }

    private func handleAnthropicEvent(type: String, data: String) {
        guard let jsonData = data.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else { return }

        switch type {
        case "message_start":
            // { "type": "message_start", "message": { "usage": { "input_tokens": N } } }
            if let msg = obj["message"] as? [String: Any],
               let u = msg["usage"] as? [String: Any],
               let it = u["input_tokens"] as? Int {
                accumulatedInputTokens = it
                gotUsage = true
            }

        case "content_block_start":
            // 新的 content block 开始. 共三种类型：text / tool_use / tool_result.
            let index = obj["index"] as? Int ?? 0
            let block = obj["content_block"] as? [String: Any]
            switch block?["type"] as? String {
            case "text":
                activeBlocks[index] = ActiveBlock(kind: .text)
            case "tool_use":
                let id = block?["id"] as? String ?? ""
                let rawName = block?["name"] as? String ?? ""
                activeBlocks[index] = ActiveBlock(kind: .toolUse(id: id, name: rawName))
            case "tool_result":
                let toolUseId = block?["tool_use_id"] as? String ?? ""
                var toolResultBlock = ActiveBlock(kind: .toolResult(toolUseId: toolUseId))
                // mcp_servers beta: tool_result 内容有时直接包含在 content_block_start 中
                if let content = block?["content"] as? String {
                    toolResultBlock.accumulated = content
                }
                activeBlocks[index] = toolResultBlock
            default:
                break
            }

        case "content_block_delta":
            let index = obj["index"] as? Int ?? 0
            let delta = obj["delta"] as? [String: Any]
            switch delta?["type"] as? String {
            case "text_delta":
                let text = delta?["text"] as? String ?? ""
                activeBlocks[index]?.accumulated += text
                // 只有 text block 才通过 onToken 实时更新
                if let block = activeBlocks[index], case .text = block.kind {
                    DispatchQueue.main.async { [self] in
                        streamingContent += text
                        onToken?(text)
                    }
                }
            case "input_json_delta":
                // 累积 tool_use block 的输入 JSON 片段
                let partial = delta?["partial_json"] as? String ?? ""
                activeBlocks[index]?.accumulated += partial
            default:
                if let text = delta?["text"] as? String, !text.isEmpty {
                    // fallback: 仅有 text 字段而无 type 的情况（兼容旧版 Anthropic API）
                    activeBlocks[index]?.accumulated += text
                    DispatchQueue.main.async { [self] in
                        streamingContent += text
                        onToken?(text)
                    }
                }
            }

        case "content_block_stop":
            // block 完成 → 生成 MessageSegment 后追加到 pendingSegments
            let index = obj["index"] as? Int ?? 0
            if let block = activeBlocks.removeValue(forKey: index) {
                finalizeBlock(block)
            }

        case "message_delta":
            // { "usage": { "output_tokens": N } }
            if let u = obj["usage"] as? [String: Any],
               let ot = u["output_tokens"] as? Int {
                accumulatedOutputTokens = ot
                gotUsage = true
            }

        case "message_stop":
            receivedDone = true
            let segments = pendingSegments
            let hasTool = segments.contains {
                if case .toolUse = $0 { return true }
                if case .toolResult = $0 { return true }
                return false
            }
            DispatchQueue.main.async { [self] in
                isStreaming = false
                // 仅在存在 tool 段时调用 onSegmentsCallback（纯文本走原有路径）
                if hasTool {
                    onSegmentsCallback?(segments)
                }
                onComplete?(streamingContent, finalUsage)
            }

        case "error":
            if let err = obj["error"] as? [String: Any],
               let message = err["message"] as? String {
                DispatchQueue.main.async { [self] in
                    isStreaming = false
                    error = message
                    onError?(message)
                }
            }

        default:
            break
        }
    }

    /// block 完成时转换为 MessageSegment 并追加到 pendingSegments。
    private func finalizeBlock(_ block: ActiveBlock) {
        switch block.kind {
        case .text:
            // 文本已实时累积到 streamingContent。非空时也追加到 segments。
            let text = block.accumulated
            if !text.isEmpty {
                pendingSegments.append(.text(text))
            }
        case .toolUse(let id, let rawName):
            // Q2: 去除 server name 前缀 ("imprint-memory__memory_remember" → "memory_remember")
            let parts = rawName.components(separatedBy: "__")
            let displayName = parts.count > 1 ? parts.dropFirst().joined(separator: "__") : rawName
            let serverName = parts.count > 1 ? parts[0] : nil
            pendingSegments.append(.toolUse(
                id: id,
                name: displayName,
                inputJSON: block.accumulated.isEmpty ? "{}" : block.accumulated,
                integrationName: serverName,
                iconName: nil
            ))
        case .toolResult(let toolUseId):
            pendingSegments.append(.toolResult(
                toolUseId: toolUseId,
                text: block.accumulated,
                isError: false,
                integrationName: nil
            ))
        }
    }
}

// MARK: - Provider Router

@Observable
final class ProviderRouter {
    private var openAIProvider = OpenAICompatibleProvider()
    private var anthropicProvider = AnthropicProvider()
    private var ccBridgeProvider = CCBridgeProvider()

    var isStreaming: Bool {
        openAIProvider.isStreaming || anthropicProvider.isStreaming || ccBridgeProvider.isStreaming
    }

    var streamingContent: String {
        if openAIProvider.isStreaming || !openAIProvider.streamingContent.isEmpty {
            return openAIProvider.streamingContent
        }
        if anthropicProvider.isStreaming || !anthropicProvider.streamingContent.isEmpty {
            return anthropicProvider.streamingContent
        }
        return ccBridgeProvider.streamingContent
    }

    var error: String? {
        openAIProvider.error ?? anthropicProvider.error ?? ccBridgeProvider.error
    }

    func sendStreaming(
        model: ProviderModel,
        messages: [(role: String, content: String)],
        systemPrompt: String?,
        providerManager: ProviderManager,
        samplingParams: SamplingParams? = nil,
        additionalHeaders: [String: String] = [:],
        onSegments: (([MessageSegment]) -> Void)? = nil,
        onThinkingToken: ((String) -> Void)? = nil,
        onToken: @escaping (String) -> Void,
        onComplete: @escaping (String, TokenUsage?) -> Void,
        onError: @escaping (String) -> Void
    ) {
        guard let provider = providerManager.provider(for: model) else {
            onError("找不到提供商: \(model.providerId)")
            return
        }

        // ccBridge 不要求 apiKey（WebSocket 本地连接，没有云端鉴权）
        let apiKey: String
        if provider.type == .ccBridge {
            apiKey = ""
        } else {
            guard let key = providerManager.apiKey(for: provider.id) else {
                onError("未设置 \(provider.name) 的 API Key")
                return
            }
            apiKey = key
        }

        let chatProvider: BaseChatProvider
        switch provider.type {
        case .openaiCompatible:
            openAIProvider.onSegmentsCallback = onSegments
            openAIProvider.onThinkingToken = onThinkingToken
            chatProvider = openAIProvider
        case .anthropic:
            // MCP 服务器注入：provider 为 anthropic 且 mcpEnabled 不为 false 时
            let mcpEnabled = samplingParams?.mcpEnabled ?? true
            anthropicProvider.mcpServersToInject = mcpEnabled ? provider.mcpServers.filter(\.isEnabled) : []
            anthropicProvider.onSegmentsCallback = onSegments
            chatProvider = anthropicProvider
        case .ccBridge:
            ccBridgeProvider.onSegmentsCallback = onSegments
            chatProvider = ccBridgeProvider
        }

        let mergedHeaders = provider.extraHeaders.merging(additionalHeaders) { _, new in new }
        chatProvider.sendStreaming(
            messages: messages,
            model: model.modelId,
            systemPrompt: systemPrompt,
            apiKey: apiKey,
            baseURL: provider.baseURL,
            extraHeaders: mergedHeaders,
            samplingParams: samplingParams,
            onToken: onToken,
            onComplete: onComplete,
            onError: onError
        )
    }

    /// 非流式调用 — 用于 memory agent 等后台任务
    func sendNonStreaming(
        model: ProviderModel,
        messages: [(role: String, content: String)],
        systemPrompt: String?,
        providerManager: ProviderManager
    ) async throws -> (String, TokenUsage?) {
        guard let provider = providerManager.provider(for: model) else {
            throw NSError(domain: "ProviderRouter", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "找不到提供商: \(model.providerId)"])
        }

        // ccBridge 不要求 apiKey（WebSocket 本地连接，没有云端鉴权）
        let apiKey: String
        if provider.type == .ccBridge {
            apiKey = ""
        } else {
            guard let key = providerManager.apiKey(for: provider.id) else {
                throw NSError(domain: "ProviderRouter", code: -2,
                              userInfo: [NSLocalizedDescriptionKey: "未设置 \(provider.name) 的 API Key"])
            }
            apiKey = key
        }

        let chatProvider: BaseChatProvider
        switch provider.type {
        case .openaiCompatible:
            chatProvider = OpenAICompatibleProvider() // 独立实例，避免干扰流式
        case .anthropic:
            chatProvider = AnthropicProvider()
        case .ccBridge:
            chatProvider = CCBridgeProvider() // 独立实例（内部用 shared WS singleton）
        }

        return try await chatProvider.sendNonStreaming(
            messages: messages,
            model: model.modelId,
            systemPrompt: systemPrompt,
            apiKey: apiKey,
            baseURL: provider.baseURL,
            extraHeaders: provider.extraHeaders
        )
    }

    func cancel() {
        openAIProvider.cancel()
        anthropicProvider.cancel()
        ccBridgeProvider.cancel()
    }
}

// MARK: - CC Bridge Provider

final class CCBridgeProvider: BaseChatProvider {
    @ObservationIgnored private let wsClient = CCBridgeWebSocketClient.shared
    /// ProviderRouter 在发起请求前注入，用于把 tool_event 段回传给 ViewModel
    var onSegmentsCallback: (([MessageSegment]) -> Void)?

    override func sendStreaming(
        messages: [(role: String, content: String)],
        model: String,
        systemPrompt: String?,
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
        let user      = extraHeaders["X-MP-User"]      ?? "tianyi"

        // 3. 积累 tool_event 段（CC 调用 imprint-memory 后通过 reply tool_calls 上报）
        //    pendingToolSegments 被 toolEventHandler 和 replyHandler 两个闭包共享捕获；
        //    两者均在 main thread 调用，无竞争。
        var pendingToolSegments: [MessageSegment] = []
        let capturedOnSegments = onSegmentsCallback  // 快照，避免 sendStreaming 返回后被覆盖

        wsClient.toolEventHandler = { [chatId] (evtChatId, toolName, inputJSON, result) in
            guard evtChatId == chatId else { return }
            // Q2：不显示 server 前缀，直接用 toolName（CC 已自动去前缀或 mcp-server.ts 直接传工具名）
            let toolUseSeg = MessageSegment.toolUse(
                id: UUID().uuidString,
                name: toolName,
                inputJSON: inputJSON.isEmpty ? "{}" : inputJSON,
                integrationName: "imprint-memory",
                iconName: nil
            )
            let toolResultSeg = MessageSegment.toolResult(
                toolUseId: "",    // CCBridge 路径 toolUseId 无意义，置空
                text: result,
                isError: false,
                integrationName: nil
            )
            pendingToolSegments.append(toolUseSeg)
            if !result.isEmpty { pendingToolSegments.append(toolResultSeg) }
        }

        // 4. 先注册 reply handler（即便 WS 还没连上也无妨，dict 里等 reply 到达再触发）
        wsClient.registerReplyHandler(chatId: chatId) { [weak self] replyText in
            guard let self else { return }
            self.wsClient.toolEventHandler = nil           // 清除 tool_event 监听
            self.wsClient.unregisterReplyHandler(chatId: chatId)
            self.isStreaming = false
            self.streamingContent = replyText
            // 若有 tool segments，组合后回传 ViewModel 写入 node.segments
            if !pendingToolSegments.isEmpty {
                var segs = pendingToolSegments
                segs.append(.text(replyText))
                capturedOnSegments?(segs)
            }
            onComplete(replyText, nil)  // CC 不上报 token 用量
        }

        // 5. 触发连接（如未连接）
        if !wsClient.isConnected, let url = URL(string: baseURL) {
            wsClient.connect(url: url)
        }

        // 6. 发送 send 帧；若 WS 未连接，send 立即回调 error，走 failNow 分支
        let payload: [String: Any] = [
            "type":       "send",
            "chat_id":    chatId,
            "message_id": messageId,
            "content":    lastUser.content,
            "user":       user,
        ]
        wsClient.send(payload) { [weak self] err in
            guard let self else { return }
            if let err {
                self.wsClient.toolEventHandler = nil
                self.wsClient.unregisterReplyHandler(chatId: chatId)
                self.failNow("CC Bridge WS 发送失败：\(err.localizedDescription)", onError: onError)
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
        // CC 在 tmux 里处理，无法从外部中断；本地只清流式状态
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
