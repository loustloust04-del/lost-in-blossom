import Foundation
import UIKit

// MARK: - OpenAI Compatible Provider

final class OpenAICompatibleProvider: BaseChatProvider {
    /// DeepSeek reasoning_content 流式 buffer（其他模型为空）
    private var streamingThinking: String = ""
    /// Gateway [thinking]...[/thinking] 标记追踪（Claude thinking via OpenAI format）
    private var isInGatewayThinking = false
    /// 流式结束时若有 thinking 内容则调用（构造 MessageSegment 列表）
    var onSegmentsCallback: (([MessageSegment]) -> Void)?
    /// 实时发送每个 reasoning_content chunk（逐字显示思考链用）
    var onThinkingToken: ((String) -> Void)?
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
        resetState(onToken: onToken, onComplete: onComplete, onError: onError)
        streamingThinking = ""
        isInGatewayThinking = false

        var apiMessages: [[String: Any]] = []
        if let sys = systemPrompt, !sys.isEmpty {
            apiMessages.append(["role": "system", "content": sys])
        }
        for msg in messages {
            // Detect multimodal content and convert to OpenAI vision format
            if msg.role == "user", msg.content.hasPrefix("[{"),
               let data = msg.content.data(using: .utf8),
               let blocks = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
                var visionContent: [[String: Any]] = []
                for block in blocks {
                    let type = block["type"] as? String ?? ""
                    if type == "image", let source = block["source"] as? [String: Any],
                       let b64 = source["data"] as? String,
                       let mediaType = source["media_type"] as? String {
                        visionContent.append(["type": "image_url", "image_url": ["url": "data:\(mediaType);base64,\(b64)"]])
                    } else if type == "text" {
                        visionContent.append(["type": "text", "text": block["text"] as? String ?? ""])
                    } else if type == "document" {
                        let title = block["title"] as? String ?? "document"
                        visionContent.append(["type": "text", "text": "[附件: \(title) — 此模型不支持文件，请用 Claude 查看]"])
                    }
                }
                apiMessages.append(["role": msg.role, "content": visionContent])
            } else {
                apiMessages.append(["role": msg.role, "content": msg.content])
            }
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
        var apiMessages: [[String: Any]] = []
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
                        // 6d: 回复完成 success 通知震
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
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
                // Gateway [thinking]...[/thinking] 标记路由：
                // thinking 标记之间的 token 走 onThinkingToken，其余走 onToken
                if content.contains("[thinking]") {
                    isInGatewayThinking = true
                    let after = content.components(separatedBy: "[thinking]").last ?? ""
                    let trimmed = after.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        streamingThinking += trimmed
                        onThinkingToken?(trimmed)
                    }
                } else if content.contains("[/thinking]") {
                    let parts = content.components(separatedBy: "[/thinking]")
                    let before = (parts.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !before.isEmpty {
                        streamingThinking += before
                        onThinkingToken?(before)
                    }
                    isInGatewayThinking = false
                    let after = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
                    if !after.isEmpty {
                        streamingContent += after
                        onToken?(after)
                    }
                } else if isInGatewayThinking {
                    streamingThinking += content
                    onThinkingToken?(content)
                } else {
                    streamingContent += content
                    onToken?(content)
                }
            }
        }
    }
}
