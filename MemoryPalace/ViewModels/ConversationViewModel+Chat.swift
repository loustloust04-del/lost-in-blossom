import Foundation
import SwiftData

// MARK: - Chat (API)

extension ConversationViewModel {

    /// 用 PromptAssembler 组装完整 prompt
    private func assemblePrompt(
        profile: Profile,
        preset: Preset,
        excludingNodeId: String? = nil,
        context: ModelContext,
        globalEntries: [WorldBookEntry] = []
    ) -> (systemPrompt: String?, messages: [(role: String, content: String)], sampling: SamplingParams) {
        // memoryEnabled=false 的对话不注入记忆
        let shouldInjectMemory = selectedConversation?.memoryEnabled ?? true
        let memories: [Memory] = shouldInjectMemory ? memoryStore.listHot(profileId: profile.id, context: context) : []
        let ids = memories.map(\.id)
        if !ids.isEmpty { try? memoryStore.recordAccess(ids: ids, context: context) }

        let chatHistory = buildAPIMessages(excluding: excludingNodeId, maxMessages: preset.sampling.contextDepth)

        // 查询当前楼层的世界书（过滤 conversation scope）
        let profileId = profile.id
        let wbDescriptor = FetchDescriptor<WorldBook>(predicate: #Predicate { $0.profileId == profileId })
        let allFloorBooks = (try? context.fetch(wbDescriptor)) ?? []
        let currentConvId = selectedConversation?.id ?? ""
        let worldBooks = allFloorBooks.filter { book in
            // nil = 楼层全体生效，有值 = 仅匹配的对话生效
            book.scopeConversationId == nil || book.scopeConversationId == currentConvId
        }

        // 读取上下文摘要
        let contextSummary = ContextSummarizer.load(conversationId: currentConvId)?.summary

        // 读取项目指令
        var projectInstructions: String? = nil
        if let projId = selectedConversation?.projectId, !projId.isEmpty {
            let pid = projId
            let projFetch = FetchDescriptor<Project>(predicate: #Predicate { $0.id == pid })
            if let proj = try? context.fetch(projFetch).first, !proj.instructions.isEmpty {
                projectInstructions = proj.instructions
            }
        }

        let result = PromptAssembler.assemble(
            preset: preset,
            profile: profile,
            memories: memories,
            chatHistory: chatHistory,
            worldBooks: worldBooks,
            globalEntries: globalEntries,
            contextSummary: contextSummary,
            projectInstructions: projectInstructions
        )

        // 宏替换：{{health}} {{date}} {{time}}
        var finalPrompt = result.systemPrompt
        if let prompt = finalPrompt {
            let df = DateFormatter()
            df.locale = Locale(identifier: "zh_CN")
            df.dateFormat = "yyyy年M月d日 EEEE"
            let tf = DateFormatter()
            tf.locale = Locale(identifier: "zh_CN")
            tf.dateFormat = "HH:mm"
            var expanded = prompt
                .replacingOccurrences(of: "{{health}}", with: HealthService.shared.injectedSummary)
                .replacingOccurrences(of: "{{date}}", with: df.string(from: Date()))
                .replacingOccurrences(of: "{{time}}", with: tf.string(from: Date()))
            // 如果替换后有空行（健康数据为空时），清理多余换行
            while expanded.contains("\n\n\n") {
                expanded = expanded.replacingOccurrences(of: "\n\n\n", with: "\n\n")
            }
            finalPrompt = expanded
        }

        return (systemPrompt: finalPrompt, messages: result.messages, sampling: preset.sampling)
    }

    /// ccBridge 路径：把 PromptAssembler 的输出后处理成只发 raw user 文字，
    /// 同时构造 router 的 additionalHeaders（chat_id/message_id/user）。
    /// 其他 provider 类型走原路（直接返回 assembled + 空 headers）。
    private func prepareRouterPayload(
        assembled: (systemPrompt: String?, messages: [(role: String, content: String)], sampling: SamplingParams),
        model: ProviderModel,
        conversation: Conversation,
        profile: Profile,
        providerManager: ProviderManager,
        messageNodeId: String
    ) -> (
        messages: [(role: String, content: String)],
        systemPrompt: String?,
        sampling: SamplingParams,
        additionalHeaders: [String: String]
    ) {
        guard let provider = providerManager.provider(for: model),
              provider.type == .ccBridge else {
            return (assembled.messages, assembled.systemPrompt, assembled.sampling, [:])
        }
        // ccBridge：只取最后一条 user 的 raw 文字，丢掉 system prompt 和历史
        let lastUser = assembled.messages.last(where: { $0.role == "user" })?.content ?? ""
        let userLabel = profile.userName.isEmpty ? "tianyi" : profile.userName
        let headers: [String: String] = [
            "X-MP-ChatId": conversation.id,
            "X-MP-MessageId": messageNodeId,
            "X-MP-User": userLabel,
        ]
        return (
            messages: [(role: "user", content: lastUser)],
            systemPrompt: nil,
            sampling: assembled.sampling,
            additionalHeaders: headers
        )
    }

    /// 主 provider id → 该 provider 下"便宜模型"的 modelId。粟粟批注：暂硬编码，
    /// 未来可扩展成配置。provider 不在表里就没 cheap 可用 → fallback 到主对话模型。
    private static let cheapModelIdByProvider: [String: String] = [
        "anthropic": "claude-haiku-4-5",
        "openai":    "gpt-4o-mini",
        "deepseek":  "deepseek-chat",
        "gemini":    "gemini-2.5-flash",
        "groq":      "llama-3.3-70b-versatile",
    ]

    /// 选择记忆提取 / 上下文总结等 backend agent 用的便宜模型。
    /// **只在 enabledProviders（有 key）里找**，避免落到没 key 没拨款的 provider。
    /// 顺序：用户旧设置 `memoryExtractModelId`（限 enabled）→ 主 provider 的 cheap map → fallback。
    private func cheapModel(providerManager: ProviderManager, fallback: ProviderModel) -> ProviderModel {
        let enabledModels = providerManager.enabledProviders.flatMap(\.models)

        // 老 UserDefaults key 兼容（Picker 现已被 MemoryModelConfig 替代，但之前选过的仍尊重）
        let userChoice = UserDefaults.standard.string(forKey: "memoryExtractModelId") ?? ""
        if !userChoice.isEmpty, let model = enabledModels.first(where: { $0.id == userChoice }) {
            return model
        }

        if let cheapId = Self.cheapModelIdByProvider[fallback.providerId],
           let provider = providerManager.enabledProviders.first(where: { $0.id == fallback.providerId }),
           let model = provider.models.first(where: { $0.modelId == cheapId }) {
            return model
        }

        return fallback
    }

    /// Build API message history from currentPath, excluding a specific node, limited to recent messages
    private func buildAPIMessages(excluding excludeId: String? = nil, maxMessages: Int = 40) -> [(role: String, content: String)] {
        let relevant = currentPath.compactMap { node -> (role: String, content: String)? in
            guard node.role == "user" || node.role == "assistant" else { return nil }
            if node.id == excludeId { return nil }
            guard !node.content.isEmpty else { return nil }
            // Strip thinking blocks from assistant messages before sending
            let content: String
            if node.role == "assistant" {
                let result = ContentCleaner.extractThinking(from: node.content)
                content = result.content
            } else {
                content = node.content
            }
            guard !content.isEmpty else { return nil }
            return (role: node.role, content: content)
        }
        // Only keep the most recent messages
        if relevant.count > maxMessages {
            return Array(relevant.suffix(maxMessages))
        }
        return relevant
    }

    /// Send a user message and get a streaming response
    func sendMessage(_ text: String, imageData: Data? = nil, fileData: Data? = nil, fileName: String? = nil, model: ProviderModel, profile: Profile, preset: Preset, providerManager: ProviderManager, context: ModelContext) {
        guard let conversation = selectedConversation else { return }
        guard preCheckBudget(text: text, model: model, profile: profile, preset: preset, providerManager: providerManager) else { return }

        // 1. Determine parent node (last node in path, or nil for first message)
        let parentId = currentPath.last?.id

        // 2. Build content and contentType
        let (userContent, userContentType): (String, String) = {
            if let data = imageData {
                let b64 = data.base64EncodedString()
                let blocks: [[String: Any]] = [
                    ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": b64]],
                    ["type": "text", "text": text]
                ]
                let json = (try? JSONSerialization.data(withJSONObject: blocks)).flatMap { String(data: $0, encoding: .utf8) } ?? text
                return (json, "multimodal_text")
            } else if let data = fileData {
                let ext = (fileName ?? "").lowercased().components(separatedBy: ".").last ?? ""
                let imageExts = ["jpg", "jpeg", "png", "gif", "webp", "heic"]
                let textExts = ["json", "txt", "md", "csv", "html", "xml", "swift", "py", "js", "ts", "yaml", "yml", "toml", "log", "sh", "css"]
                if imageExts.contains(ext) {
                    let b64 = data.base64EncodedString()
                    let mimeType = ext == "png" ? "image/png" : ext == "gif" ? "image/gif" : ext == "webp" ? "image/webp" : "image/jpeg"
                    let blocks: [[String: Any]] = [
                        ["type": "image", "source": ["type": "base64", "media_type": mimeType, "data": b64]],
                        ["type": "text", "text": text]
                    ]
                    let json = (try? JSONSerialization.data(withJSONObject: blocks)).flatMap { String(data: $0, encoding: .utf8) } ?? text
                    return (json, "multimodal_text")
                } else if textExts.contains(ext) {
                    let fileContent = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) ?? "[无法解码文件内容]"
                    let maxChars = 100_000
                    let truncated = fileContent.count > maxChars ? String(fileContent.prefix(maxChars)) + "\n\n[文件过长，已截断至前 100K 字符]" : fileContent
                    let combined = "📎 \(fileName ?? "file")\n```\n" + truncated + "\n```" + (text.isEmpty ? "" : "\n\n" + text)
                    return (combined, "text")
                } else if ext == "pdf" {
                    let b64 = data.base64EncodedString()
                    var docBlock: [String: Any] = [
                        "type": "document",
                        "source": ["type": "base64", "media_type": "application/pdf", "data": b64]
                    ]
                    if let name = fileName { docBlock["title"] = name }
                    let blocks: [[String: Any]] = [docBlock, ["type": "text", "text": text]]
                    let json = (try? JSONSerialization.data(withJSONObject: blocks)).flatMap { String(data: $0, encoding: .utf8) } ?? text
                    return (json, "multimodal_text")
                } else {
                    if let fileContent = String(data: data, encoding: .utf8), !fileContent.isEmpty {
                        let maxChars = 100_000
                        let truncated = fileContent.count > maxChars ? String(fileContent.prefix(maxChars)) + "\n\n[文件过长，已截断]" : fileContent
                        let combined = "📎 \(fileName ?? "file")\n```\n" + truncated + "\n```" + (text.isEmpty ? "" : "\n\n" + text)
                        return (combined, "text")
                    } else {
                        return ("[无法读取 \(fileName ?? "file")：不支持的格式]" + (text.isEmpty ? "" : "\n\n" + text), "text")
                    }
                }
            } else {
                return (text, "text")
            }
        }()

        // 3. Create user MessageNode
        let userNodeId = UUID().uuidString
        let userNode = MessageNode(
            id: userNodeId,
            role: "user",
            content: userContent,
            contentType: userContentType,
            createTime: Date(),
            parentId: parentId,
            childrenIds: [],
            conversationId: conversation.id,
            profileId: conversation.profileId
        )
        context.insert(userNode)

        // Update parent's childrenIds
        if let parentId, let parent = nodeMap[parentId] {
            if !parent.childrenIds.contains(userNodeId) {
                parent.childrenIds.append(userNodeId)
            }
        }

        // Add to nodeMap and path
        nodeMap[userNodeId] = userNode
        effectiveChildrenMap[userNodeId] = []
        if let parentId {
            effectiveChildrenMap[parentId, default: []].append(userNodeId)
        }
        currentPath.append(userNode)

        // 3. Create placeholder assistant node
        let assistantNodeId = UUID().uuidString
        let assistantNode = MessageNode(
            id: assistantNodeId,
            role: "assistant",
            content: "",
            contentType: "text",
            createTime: Date(),
            parentId: userNodeId,
            childrenIds: [],
            conversationId: conversation.id,
            profileId: conversation.profileId
        )
        context.insert(assistantNode)

        userNode.childrenIds.append(assistantNodeId)
        nodeMap[assistantNodeId] = assistantNode
        effectiveChildrenMap[assistantNodeId] = []
        effectiveChildrenMap[userNodeId, default: []].append(assistantNodeId)
        currentPath.append(assistantNode)

        // Update conversation
        conversation.currentNodeId = assistantNodeId
        conversation.updateTime = Date()
        markConversationDirty()

        streamingText = ""
        streamingThinkingText = ""
        isThinking = false
        thinkingSummary = ""

        // 4. Assemble prompt using PromptAssembler
        let assembled = assemblePrompt(profile: profile, preset: preset, excludingNodeId: assistantNodeId, context: context, globalEntries: globalWorldBookEntries)
        let payload = prepareRouterPayload(assembled: assembled, model: model, conversation: conversation, profile: profile, providerManager: providerManager, messageNodeId: assistantNodeId)

        // 5. Stream
        providerRouter.sendStreaming(
            model: model,
            messages: payload.messages,
            systemPrompt: payload.systemPrompt,
            providerManager: providerManager,
            samplingParams: payload.sampling,
            additionalHeaders: payload.additionalHeaders,
            onSegments: { [weak assistantNode] segments in
                // 仅在存在 tool_use/tool_result 段时调用。
                // 比 onComplete 先执行，context.save() 在 onComplete 中处理。
                assistantNode?.setSegments(segments)
            },
            onThinkingToken: { [weak self] token in
                guard let self else { return }
                streamingThinkingText += token
                if !isThinking { isThinking = true }
            },
            onToken: { [weak self] token in
                guard let self else { return }
                HapticService.shared.streamingTick()
                if isThinking {
                    isThinking = false
                    let capturedThinking = streamingThinkingText
                    let capturedModel = model
                    let capturedProvider = providerManager
                    Task { [weak self] in
                        guard let self else { return }
                        let summary = await self.providerRouter.summarizeThinking(
                            thinkingText: capturedThinking,
                            model: capturedModel,
                            providerManager: capturedProvider
                        )
                        if let s = summary { self.thinkingSummary = s }
                    }
                }
                streamingText += token
                assistantNode.content = streamingText
            },
            onComplete: { [weak self] fullText, usage in
                guard let self else { return }
                HapticService.shared.streamingComplete()
                assistantNode.content = fullText
                streamingText = ""
                streamingThinkingText = ""
                isThinking = false
                conversation.nodeCount = currentPath.filter {
                    ($0.role == "user" || $0.role == "assistant") && !$0.content.isEmpty
                }.count
                // Auto-title from first user message
                if conversation.title == "新对话" {
                    let firstUserMsg = currentPath.first(where: { $0.role == "user" && !$0.content.isEmpty })?.content ?? ""
                    if !firstUserMsg.isEmpty {
                        let title = String(firstUserMsg.prefix(40)).replacingOccurrences(of: "\n", with: " ")
                        conversation.title = title
                        // 走 debounce，和发消息触发的重排合并在一次 refresh 里（避免首次发消息
                        // 标题立刻变 + 位置立刻跳的双抖动）
                        markConversationDirty()
                    }
                }
                try? context.save()
                scrollToNodeId = assistantNodeId

                // 预算扣费（Phase C 完整接入前先只用 usage）
                self.commitBudgetSpend(providerManager: providerManager, model: model, usage: usage)

                // AUDN 记忆提取（memoryEnabled=false 的对话不提取）
                if conversation.memoryEnabled {
                    self.extractMemoriesIfNeeded(profileId: profile.id, conversationId: conversation.id, model: model, providerManager: providerManager, context: context)
                }

                // 上下文总结（异步，不阻塞）
                self.triggerContextSummaryIfNeeded(
                    conversationId: conversation.id,
                    contextDepth: preset.sampling.contextDepth,
                    model: model, providerManager: providerManager
                )
            },
            onError: { [weak self] error in
                guard let self else { return }
                if streamingText.isEmpty {
                    assistantNode.content = "⚠️ \(error)"
                }
                streamingText = ""
                streamingThinkingText = ""
                isThinking = false
            }
        )

        scrollToNodeId = userNodeId
    }

    /// AUDN 记忆提取：每轮对话后异步调用便宜模型提取/更新/删除记忆
    private func extractMemoriesIfNeeded(profileId: String, conversationId: String, model: ProviderModel, providerManager: ProviderManager, context: ModelContext) {
        guard !profileId.isEmpty else { return }

        let recentMessages = Array(buildAPIMessages().suffix(memoryExtractWindow))
        guard !recentMessages.isEmpty else { return }

        let existingMemories = memoryStore.listHotAndWarm(profileId: profileId, context: context)
        let extractModel = cheapModel(providerManager: providerManager, fallback: model)
        #if DEBUG
        print("🧠 记忆提取: 使用模型 \(extractModel.name) (\(extractModel.id)), 最近 \(recentMessages.count) 条消息, 已有 \(existingMemories.count) 条记忆")
        #endif

        let request = MemoryExtractor.buildRequest(
            recentMessages: recentMessages,
            existingMemories: existingMemories
        )

        // 预算保险闸：共用主对话 provider 一个预算（粟粟批注：分词器也是粗算，保险即可）
        if backendAgentBlockedByBudget(model: model, messages: request.messages, systemPrompt: request.systemPrompt, providerManager: providerManager) {
            #if DEBUG
            print("🧠 记忆提取: 跳过（主 provider \(model.providerId) 预算已用完 / 未拨款）")
            #endif
            return
        }

        // Fire-and-forget: 异步调用，不阻塞对话
        let router = ProviderRouter()
        Task.detached { [weak self] in
            do {
                let (response, usage) = try await router.sendNonStreaming(
                    model: extractModel,
                    messages: request.messages,
                    systemPrompt: request.systemPrompt,
                    providerManager: providerManager
                )
                #if DEBUG
                print("🧠 记忆提取: 模型返回 \(response.prefix(200))...")
                #endif

                // Spent 累加到全局预算池（GlobalBudgetStore 不分 providerId，共用一个预算）。
                // 但 actualCost 必须用 extractModel（实际跑的廉价模型）查 PricingCatalog，
                // 否则 Haiku token 数 × Opus 单价会超收 ~18×（ultrareview B17 / bug_004）。
                if let usage {
                    await MainActor.run {
                        self?.commitBudgetSpend(providerManager: providerManager, model: extractModel, usage: usage)
                    }
                }

                let actions = MemoryExtractor.parseActions(response)
                #if DEBUG
                if actions.isEmpty {
                    print("🧠 记忆提取: 解析结果为空（模型返回了无法解析的格式或 NOOP）")
                } else {
                    print("🧠 记忆提取: 解析到 \(actions.count) 个操作")
                }
                #endif
                guard !actions.isEmpty else { return }

                await MainActor.run {
                    for action in actions {
                        #if DEBUG
                        switch action {
                        case .add(let content, let category, _):
                            print("🧠 记忆: ✅ ADD [\(category)] \(content.prefix(60))...")
                        case .update(let id, let content, _):
                            print("🧠 记忆: ✏️ UPDATE \(id.uuidString.prefix(8)) → \(content.prefix(60))...")
                        case .delete(let id):
                            print("🧠 记忆: 🗑️ DELETE \(id.uuidString.prefix(8))")
                        }
                        #endif
                    }
                    try? MemoryExtractor.executeActions(
                        actions,
                        store: self?.memoryStore ?? SwiftDataMemoryStore(),
                        profileId: profileId,
                        extractedBy: extractModel.name,
                        sourceConversationId: conversationId,
                        context: context
                    )
                }
            } catch {
                #if DEBUG
                print("🧠 记忆提取: ⚠️ 失败 — \(error)")
                #endif
            }
        }
    }

    /// 上下文总结触发（fire-and-forget）
    private func triggerContextSummaryIfNeeded(conversationId: String, contextDepth: Int, model: ProviderModel, providerManager: ProviderManager) {
        let allMessages = buildAPIMessages(maxMessages: Int.max)
        let sumModel = cheapModel(providerManager: providerManager, fallback: model)
        Task.detached {
            try? await ContextSummarizer.summarize(
                allMessages: allMessages,
                contextDepth: contextDepth,
                conversationId: conversationId,
                model: sumModel,
                providerManager: providerManager
            )
        }
    }

    /// 会话巩固：切换对话时刷新衰减权重
    func consolidateSessionMemories(profileId: String, context: ModelContext) {
        guard !profileId.isEmpty else { return }
        try? memoryStore.applyDecay(profileId: profileId, context: context)
    }

    /// Regenerate: create a new assistant response as a sibling branch of the existing one
    func regenerate(assistantNodeId: String, model: ProviderModel, profile: Profile, preset: Preset, providerManager: ProviderManager, context: ModelContext) {
        guard preCheckBudget(text: "", model: model, profile: profile, preset: preset, providerManager: providerManager) else { return }
        guard let conversation = selectedConversation,
              let oldNode = nodeMap[assistantNodeId],
              oldNode.role == "assistant",
              let userParentId = oldNode.parentId,
              let userParent = nodeMap[userParentId]
        else { return }

        // Create new assistant node as sibling
        let newAssistantId = UUID().uuidString
        let newNode = MessageNode(
            id: newAssistantId,
            role: "assistant",
            content: "",
            contentType: "text",
            createTime: Date(),
            parentId: userParentId,
            childrenIds: [],
            conversationId: conversation.id,
            profileId: conversation.profileId
        )
        context.insert(newNode)

        userParent.childrenIds.append(newAssistantId)
        nodeMap[newAssistantId] = newNode
        effectiveChildrenMap[newAssistantId] = []
        effectiveChildrenMap[userParentId, default: []].append(newAssistantId)

        // Replace old node in path with new one
        if let idx = currentPath.firstIndex(where: { $0.id == assistantNodeId }) {
            // Remove everything after the old assistant node
            currentPath.removeSubrange(idx...)
            currentPath.append(newNode)
        }

        conversation.currentNodeId = newAssistantId
        conversation.updateTime = Date()
        markConversationDirty()
        streamingText = ""
        streamingThinkingText = ""
        isThinking = false
        thinkingSummary = ""

        // Assemble prompt
        let assembled = assemblePrompt(profile: profile, preset: preset, excludingNodeId: newAssistantId, context: context, globalEntries: globalWorldBookEntries)
        let payload = prepareRouterPayload(assembled: assembled, model: model, conversation: conversation, profile: profile, providerManager: providerManager, messageNodeId: newAssistantId)

        providerRouter.sendStreaming(
            model: model,
            messages: payload.messages,
            systemPrompt: payload.systemPrompt,
            providerManager: providerManager,
            samplingParams: payload.sampling,
            additionalHeaders: payload.additionalHeaders,
            onSegments: { [weak newNode] segments in
                newNode?.setSegments(segments)
            },
            onThinkingToken: { [weak self] token in
                guard let self else { return }
                streamingThinkingText += token
                if !isThinking { isThinking = true }
            },
            onToken: { [weak self] token in
                guard let self else { return }
                HapticService.shared.streamingTick()
                if isThinking {
                    isThinking = false
                    let capturedThinking = streamingThinkingText
                    let capturedModel = model
                    let capturedProvider = providerManager
                    Task { [weak self] in
                        guard let self else { return }
                        let summary = await self.providerRouter.summarizeThinking(
                            thinkingText: capturedThinking,
                            model: capturedModel,
                            providerManager: capturedProvider
                        )
                        if let s = summary { self.thinkingSummary = s }
                    }
                }
                streamingText += token
                newNode.content = streamingText
            },
            onComplete: { [weak self] fullText, usage in
                guard let self else { return }
                HapticService.shared.streamingComplete()
                newNode.content = fullText
                streamingText = ""
                streamingThinkingText = ""
                isThinking = false
                try? context.save()
                scrollToNodeId = newAssistantId
                self.commitBudgetSpend(providerManager: providerManager, model: model, usage: usage)

                // 上下文总结
                self.triggerContextSummaryIfNeeded(
                    conversationId: conversation.id,
                    contextDepth: preset.sampling.contextDepth,
                    model: model, providerManager: providerManager
                )
            },
            onError: { [weak self] error in
                guard let self else { return }
                if streamingText.isEmpty {
                    newNode.content = "⚠️ \(error)"
                }
                streamingText = ""
                streamingThinkingText = ""
                isThinking = false
            }
        )

        scrollToNodeId = newAssistantId
    }

    /// Edit a user message: create a new branch from the original message's parent with new text, then get a response
    func editAndResend(_ originalNodeId: String, newText: String, model: ProviderModel, profile: Profile, preset: Preset, providerManager: ProviderManager, context: ModelContext) {
        guard preCheckBudget(text: newText, model: model, profile: profile, preset: preset, providerManager: providerManager) else { return }
        guard let conversation = selectedConversation,
              let originalNode = nodeMap[originalNodeId],
              originalNode.role == "user",
              let grandparentId = originalNode.parentId
        else { return }

        // Trim path up to (but not including) the original user node
        if let idx = currentPath.firstIndex(where: { $0.id == originalNodeId }) {
            currentPath.removeSubrange(idx...)
        }

        // Create new user node as sibling branch
        let newUserId = UUID().uuidString
        let newUserNode = MessageNode(
            id: newUserId,
            role: "user",
            content: newText,
            contentType: "text",
            createTime: Date(),
            parentId: grandparentId,
            childrenIds: [],
            conversationId: conversation.id,
            profileId: conversation.profileId
        )
        context.insert(newUserNode)

        if let grandparent = nodeMap[grandparentId] {
            if !grandparent.childrenIds.contains(newUserId) {
                grandparent.childrenIds.append(newUserId)
            }
            effectiveChildrenMap[grandparentId, default: []].append(newUserId)
        }
        nodeMap[newUserId] = newUserNode
        effectiveChildrenMap[newUserId] = []
        currentPath.append(newUserNode)

        // Create placeholder assistant node
        let newAssistantId = UUID().uuidString
        let newAssistantNode = MessageNode(
            id: newAssistantId,
            role: "assistant",
            content: "",
            contentType: "text",
            createTime: Date(),
            parentId: newUserId,
            childrenIds: [],
            conversationId: conversation.id,
            profileId: conversation.profileId
        )
        context.insert(newAssistantNode)

        newUserNode.childrenIds.append(newAssistantId)
        nodeMap[newAssistantId] = newAssistantNode
        effectiveChildrenMap[newAssistantId] = []
        effectiveChildrenMap[newUserId, default: []].append(newAssistantId)
        currentPath.append(newAssistantNode)

        conversation.currentNodeId = newAssistantId
        conversation.updateTime = Date()
        markConversationDirty()
        streamingText = ""
        streamingThinkingText = ""
        isThinking = false
        thinkingSummary = ""

        let assembled = assemblePrompt(profile: profile, preset: preset, excludingNodeId: newAssistantId, context: context, globalEntries: globalWorldBookEntries)
        let payload = prepareRouterPayload(assembled: assembled, model: model, conversation: conversation, profile: profile, providerManager: providerManager, messageNodeId: newAssistantId)

        providerRouter.sendStreaming(
            model: model,
            messages: payload.messages,
            systemPrompt: payload.systemPrompt,
            providerManager: providerManager,
            samplingParams: payload.sampling,
            additionalHeaders: payload.additionalHeaders,
            onSegments: { [weak newAssistantNode] segments in
                newAssistantNode?.setSegments(segments)
            },
            onThinkingToken: { [weak self] token in
                guard let self else { return }
                streamingThinkingText += token
                if !isThinking { isThinking = true }
            },
            onToken: { [weak self] token in
                guard let self else { return }
                HapticService.shared.streamingTick()
                if isThinking {
                    isThinking = false
                    let capturedThinking = streamingThinkingText
                    let capturedModel = model
                    let capturedProvider = providerManager
                    Task { [weak self] in
                        guard let self else { return }
                        let summary = await self.providerRouter.summarizeThinking(
                            thinkingText: capturedThinking,
                            model: capturedModel,
                            providerManager: capturedProvider
                        )
                        if let s = summary { self.thinkingSummary = s }
                    }
                }
                streamingText += token
                newAssistantNode.content = streamingText
            },
            onComplete: { [weak self] fullText, usage in
                guard let self else { return }
                HapticService.shared.streamingComplete()
                newAssistantNode.content = fullText
                streamingText = ""
                streamingThinkingText = ""
                isThinking = false
                try? context.save()
                scrollToNodeId = newAssistantId
                self.commitBudgetSpend(providerManager: providerManager, model: model, usage: usage)

                // 上下文总结
                self.triggerContextSummaryIfNeeded(
                    conversationId: conversation.id,
                    contextDepth: preset.sampling.contextDepth,
                    model: model, providerManager: providerManager
                )
            },
            onError: { [weak self] error in
                guard let self else { return }
                if streamingText.isEmpty {
                    newAssistantNode.content = "⚠️ \(error)"
                }
                streamingText = ""
                streamingThinkingText = ""
                isThinking = false
            }
        )

        scrollToNodeId = newUserId
    }

    /// Create a new empty conversation for chatting
    func createNewConversation(title: String, profileId: String, context: ModelContext, projectId: String? = nil) -> Conversation {
        let rootId = UUID().uuidString
        let conversation = Conversation(
            id: UUID().uuidString,
            title: title,
            createTime: Date(),
            updateTime: Date(),
            currentNodeId: rootId,
            provider: "api",
            profileId: profileId
        )
        conversation.projectId = projectId
        context.insert(conversation)

        // Create invisible root node
        let rootNode = MessageNode(
            id: rootId,
            role: "system",
            content: "",
            contentType: "text",
            createTime: Date(),
            parentId: nil,
            childrenIds: [],
            conversationId: conversation.id,
            profileId: profileId
        )
        context.insert(rootNode)
        try? context.save()

        return conversation
    }
}

// MARK: - Budget

extension ConversationViewModel {

    /// 发送后扣费：优先用响应里的真实 usage；没 usage 就用最近一次 pre-check 估的值保守扣。
    func commitBudgetSpend(providerManager: ProviderManager, model: ProviderModel, usage: TokenUsage?) {
        guard let provider = providerManager.provider(for: model) else { return }
        let cost: Double
        if let usage {
            cost = BudgetCalculator.actualCost(provider: provider, modelId: model.modelId, usage: usage)
        } else if pendingEstimatedCost > 0 {
            // 没 usage（流中断 / 某些 API 不回 usage）→ 按 pre-send 估算扣
            cost = pendingEstimatedCost
        } else {
            return
        }
        providerManager.commitSpend(providerId: provider.id, amount: cost)
        pendingEstimatedCost = 0
    }

    /// pre-send 门控：超额返回 false（调用方 return）。失败会写 budgetBlockedMessage 让 UI 显示 alert。
    /// 成功（ok / warning）会把 estimate 存到 pendingEstimatedCost，发送完回填扣费兜底。
    func preCheckBudget(
        text: String,
        model: ProviderModel,
        profile: Profile,
        preset: Preset,
        providerManager: ProviderManager
    ) -> Bool {
        guard let provider = providerManager.provider(for: model) else { return true }
        let maxOut = preset.sampling.maxTokens
        // 粗估 input：system + 当前 path（已有上下文）+ 新消息
        var accumulated = ""
        if !profile.systemPrompt.isEmpty { accumulated += profile.systemPrompt + "\n" }
        for node in currentPath where !node.content.isEmpty {
            accumulated += node.content + "\n"
        }
        accumulated += text
        let inputTok = HeuristicEstimator().estimate(accumulated)
        let estimated = BudgetCalculator.actualCost(
            provider: provider,
            modelId: model.modelId,
            usage: TokenUsage(inputTokens: inputTok, outputTokens: maxOut)
        )
        pendingEstimatedCost = estimated
        let gate = providerManager.budgetGate(providerId: provider.id, estimatedCost: estimated)
        switch gate {
        case .ok, .disabled, .warning:
            return true
        case .blocked(let spent, let budget):
            budgetBlockedMessage = Self.blockedMessage(providerName: provider.name, spent: spent, budget: budget)
            pendingEstimatedCost = 0
            return false
        }
    }

    /// Backend agent（memory extract / context summary 等）统一预算 gate。
    /// 返回 true = 被预算拦了，应该跳过这次 API 调用。
    func backendAgentBlockedByBudget(
        model: ProviderModel,
        messages: [(role: String, content: String)],
        systemPrompt: String?,
        providerManager: ProviderManager,
        assumedMaxOutput: Int = 1024
    ) -> Bool {
        guard let provider = providerManager.provider(for: model) else { return true }
        var accumulated = systemPrompt ?? ""
        for m in messages {
            accumulated += "\n" + m.content
        }
        let inputTok = HeuristicEstimator().estimate(accumulated)
        let estimated = BudgetCalculator.actualCost(
            provider: provider,
            modelId: model.modelId,
            usage: TokenUsage(inputTokens: inputTok, outputTokens: assumedMaxOutput)
        )
        let gate = providerManager.budgetGate(providerId: provider.id, estimatedCost: estimated)
        if case .blocked = gate { return true }
        return false
    }

    /// 友好文案：区分"没拨款（首次使用）"和"已用完"。
    private static func blockedMessage(providerName: String, spent: Double, budget: Double) -> String {
        if budget <= 0 {
            return """
            「\(providerName)」还没设预算。

            防止 app bug 把你的 key 烧干，所以默认开了保险闸。

            去「API 设置 → 预算（保险闸）」给它拨款（比如 $5），或关掉「启用预算限额」开关。
            """
        }
        return String(
            format: "「%@」预算已用完：$%.2f / $%.2f。\n\n去「API 设置 → 预算（保险闸）」点「重置已用」，或加预算上限。",
            providerName, spent, budget
        )
    }
}
