import Foundation

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
            // Detect multimodal content (JSON array string starting with "[{")
            if msg.role == "user", msg.content.hasPrefix("[{"),
               let data = msg.content.data(using: .utf8),
               let blocks = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
                apiMessages.append(["role": msg.role, "content": blocks])
            } else {
                apiMessages.append(["role": msg.role, "content": msg.content])
            }
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
                var server: [String: Any] = ["type": "url", "url": s.url, "name": s.name]
                if !s.authorizationToken.isEmpty {
                    server["authorization_token"] = s.authorizationToken
                }
                return server
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
            if msg.role == "user", msg.content.hasPrefix("[{"),
               let data = msg.content.data(using: .utf8),
               let blocks = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
                apiMessages.append(["role": msg.role, "content": blocks])
            } else {
                apiMessages.append(["role": msg.role, "content": msg.content])
            }
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
