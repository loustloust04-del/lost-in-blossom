import Foundation
import SwiftData

// MARK: - 群聊 V5（选人 + 串行 + 镜像 + 互感）

extension ConversationViewModel {

    /// 群聊一轮：用户发消息 → LLM 选人 → 选中者发言 → 再选 → 直到没人想说或达到上限。
    @MainActor
    func runGroupRound(
        conversation: Conversation,
        userText: String,
        participants: [GroupParticipant],
        providerManager: ProviderManager,
        context: ModelContext
    ) async {
        let userName = UserDefaults.standard.string(forKey: "userName") ?? "我"
        let maxReplies = 3  // 每轮最多几个角色回复
        print("[GroupV5] ═══ 新一轮 ═══ 用户: \(userText.prefix(50))... 参与者: \(participants.map(\.name))")

        BreadcrumbLog.shared.add("👥", "群聊: \(userText.prefix(30))...")

        // 1. 用户消息入树
        insertGroupNode(role: "user", content: userText,
                        senderId: nil, senderName: userName,
                        conversation: conversation, context: context)

        let cardManager = CharacterCardManager()
        let presetManager = PresetManager()

        // 2. 选人→说话 循环
        var lastSpeakerId: String? = nil
        var repliesThisRound = 0

        while repliesThisRound < maxReplies {
            let history = groupHistoryItems()

            // 选人
            let speaker = await GroupChatScheduler.selectNextSpeaker(
                participants: participants,
                history: history,
                lastSpeakerId: lastSpeakerId,
                providerManager: providerManager
            )

            guard let speaker else {
                print("[GroupV5] 选人返回 nil，本轮结束")
                break
            }

            // 解析模型
            guard let model = providerManager.model(byId: speaker.model) else {
                print("[GroupV5] ❌ \(speaker.name): 模型 '\(speaker.model)' 找不到")
                insertGroupNode(role: "assistant",
                                content: "⚠️ 模型 \(speaker.model) 未找到",
                                senderId: speaker.id, senderName: speaker.name,
                                conversation: conversation, context: context)
                repliesThisRound += 1
                continue
            }

            // 说话
            print("[GroupV5] \(speaker.name): 开始发言 (#\(repliesThisRound + 1))")
            await groupSpeak(
                participant: speaker,
                allParticipants: participants,
                userName: userName,
                card: cardManager.cards.first { $0.id == speaker.characterCardID },
                preset: presetManager.preset(byId: speaker.presetId),
                conversation: conversation,
                model: model,
                providerManager: providerManager,
                context: context
            )
            print("[GroupV5] \(speaker.name): 发言完成")

            lastSpeakerId = speaker.id
            repliesThisRound += 1

            // 检查 AI 回复里有没有 @ 提及（自动追加一轮给被提及的人）
            let latestHistory = groupHistoryItems()
            if let lastMsg = latestHistory.last,
               lastMsg.senderId == speaker.id {
                let mentions = GroupChatScheduler.extractMentions(
                    from: lastMsg.content, participants: participants)
                if !mentions.isEmpty && repliesThisRound < maxReplies {
                    print("[GroupV5] \(speaker.name) @提及了 \(mentions.map(\.name))，追加一轮")
                    // 下一轮选人会自动命中被 @ 的角色
                }
            }
        }

        print("[GroupV5] ═══ 轮次结束 ═══ 共 \(repliesThisRound) 条回复")
    }

    /// 单个角色发言。
    @MainActor
    private func groupSpeak(
        participant: GroupParticipant,
        allParticipants: [GroupParticipant],
        userName: String,
        card: CharacterCard?,
        preset: Preset?,
        conversation: Conversation,
        model: ProviderModel,
        providerManager: ProviderManager,
        context: ModelContext
    ) async {
        // 组装增强版 system prompt（含成员列表）
        let systemPrompt = GroupChatScheduler.buildSystemPrompt(
            for: participant, allParticipants: allParticipants,
            userName: userName, card: card, preset: preset
        )

        // 车道判定：CC 天生只读消息正文、丢弃 systemPrompt，且需要路由头才发得回。
        let isCC = providerManager.provider(for: model)?.type == .ccBridge

        let messages: [(role: String, content: String)]
        var headers: [String: String] = [:]
        if isCC {
            // CC 读不到 system → 把群规则+成员+角色设定拼进正文；最近对话走 X-MP-Context。
            let ctx = ccGroupContext(userName: userName)
            let ccContent = systemPrompt +
                "\n\n（接着群里最近的对话，以「\(participant.name)」的身份自然说 1-3 句，" +
                "不要加名字前缀；想叫谁接话可以 @名字。如果确实没话可说就只回复「（沉默）」。）"
            messages = [(role: "user", content: ccContent)]
            // 复用正在跑的那个 CC 会话（不设自定义 session_name——群里给每个角色单开 tmux
            // 需要每个都有 claude 进程在跑，兔兔没配；靠正文注入的人设区分角色即可）。
            // chatId 带 participant 后缀让回复路由回本角色、多个 CC 角色互不串台。
            headers = [
                "X-MP-ChatId": "\(conversation.id)__\(participant.id)",
                "X-MP-User": userName,
            ]
            if !ctx.isEmpty { headers["X-MP-Context"] = ctx }
        } else {
            // 镜像 prompt（含角色关系）
            messages = GroupChatScheduler.buildMirrorMessages(
                for: participant, history: groupHistoryItems(),
                participants: allParticipants
            )
        }

        guard !messages.isEmpty else {
            print("[GroupV5] ⚠️ \(participant.name): messages 为空，跳过")
            return
        }

        // 创建 assistant node
        let node = insertGroupNode(
            role: "assistant", content: "",
            senderId: participant.id, senderName: participant.name,
            conversation: conversation, context: context
        )
        if isCC { headers["X-MP-MessageId"] = node.id }
        // 让气泡在流式期间显示实时文本：判定是 streamingNodeId == node.id，
        // 群聊之前没设它 → 整段流式都是空气泡，直到 onComplete 才一次性冒出来。
        streamingNodeId = node.id

        // 流式调用
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            var finished = false
            var accumulated = ""
            let resume = {
                if !finished { finished = true; cont.resume() }
            }

            providerRouter.sendStreaming(
                model: model,
                messages: messages,
                systemPrompt: isCC ? nil : systemPrompt,
                providerManager: providerManager,
                samplingParams: SamplingParams(temperature: 0.8, maxTokens: 2000),
                additionalHeaders: headers,
                onToken: { [weak self] token in
                    guard let self else { return }
                    accumulated += token
                    streamingText = accumulated
                    // 不做 per-token SwiftData 写（V5 流式优化）
                },
                onComplete: { [weak self] fullText, usage in
                    guard let self else { resume(); return }
                    // 空回 / 显式沉默 → 删节点，不留空气泡（Bug1：system 允许沉默，
                    // 模型真返回空/「（沉默）」时旧代码照样插空气泡）。
                    let clean = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if clean.isEmpty || clean == "（沉默）" || clean == "(沉默)" {
                        self.removeGroupNode(node, conversation: conversation, context: context)
                        resume()
                        return
                    }
                    node.content = fullText
                    try? context.save()
                    // Token 统计
                    if let usage {
                        let cost = providerManager.provider(for: model).map {
                            BudgetCalculator.actualCost(provider: $0, modelId: model.modelId, usage: usage)
                        } ?? 0
                        TokenStatsStore.append(TokenRecord(
                            date: Date(), model: model.name,
                            conversationId: conversation.id,
                            conversationTitle: conversation.title,
                            inputTokens: usage.inputTokens,
                            outputTokens: usage.outputTokens,
                            cacheReadTokens: usage.cacheReadInputTokens,
                            cacheWriteTokens: usage.cacheCreationInputTokens,
                            cost: cost, responseTime: 0
                        ))
                    }
                    resume()
                },
                onError: { [weak self] error in
                    guard let self else { resume(); return }
                    if accumulated.isEmpty {
                        // 无内容的失败也删节点，避免一排 "⚠️" 占屏（CC 60s 超时最常见）
                        self.removeGroupNode(node, conversation: conversation, context: context)
                        print("[GroupV5] ⚠️ \(participant.name) 失败/超时，丢弃空节点: \(error)")
                    } else {
                        node.content = accumulated
                        try? context.save()
                    }
                    resume()
                }
            )
        }

        streamingText = ""
        streamingNodeId = nil
    }

    /// CC 群聊上下文：最近若干条群消息格式化成 `[名字]: 内容`（CC 读不到 messages 历史，靠这个）。
    private func ccGroupContext(userName: String) -> String {
        groupHistoryItems().suffix(12).compactMap { m -> String? in
            guard !m.content.isEmpty else { return nil }
            let name = m.senderName ?? (m.role == "user" ? userName : "某角色")
            let clean = ContentCleaner.extractThinking(from: m.content).content
            return "[\(name)]: \(clean)"
        }.joined(separator: "\n")
    }

    /// 删掉一个刚插入但内容为空的群节点（Bug1）。从 path/map/父子关系里摘除并回退 currentNodeId。
    func removeGroupNode(_ node: MessageNode, conversation: Conversation, context: ModelContext) {
        let nodeId = node.id
        let parentId = node.parentId
        currentPath.removeAll { $0.id == nodeId }
        nodeMap[nodeId] = nil
        effectiveChildrenMap[nodeId] = nil
        if let parentId {
            nodeMap[parentId]?.childrenIds.removeAll { $0 == nodeId }
            effectiveChildrenMap[parentId]?.removeAll { $0 == nodeId }
            conversation.currentNodeId = parentId
        }
        context.delete(node)
        try? context.save()
    }

    // MARK: - 工具函数

    /// 提取群聊历史为 HistoryItem 数组。
    func groupHistoryItems() -> [GroupChatScheduler.HistoryItem] {
        currentPath.map { node in
            // 剥离思考链再喂历史——跟单聊一致（ConversationViewModel+Chat 里 assistant
            // 历史走 extractThinking）。否则每个角色都会看到别人拖着的整段思考链，被污染
            // 后顺着编上下文 / 产生幻觉，不像在群里对话。
            let content = node.role == "assistant"
                ? ContentCleaner.extractThinking(from: node.content).content
                : node.content
            return GroupChatScheduler.HistoryItem(
                role: node.role,
                senderId: node.senderId,
                senderName: node.senderName,
                content: content
            )
        }
    }

    /// 群聊消息入树（复用 MessageNode 基建）。
    @MainActor
    @discardableResult
    func insertGroupNode(
        role: String,
        content: String,
        senderId: String?,
        senderName: String?,
        conversation: Conversation,
        context: ModelContext
    ) -> MessageNode {
        let nodeId = UUID().uuidString
        let parentId = currentPath.last?.id

        let node = MessageNode(
            id: nodeId,
            role: role,
            content: content,
            contentType: "text",
            createTime: Date(),
            parentId: parentId,
            childrenIds: [],
            conversationId: conversation.id,
            profileId: conversation.profileId
        )
        node.senderId = senderId
        node.senderName = senderName
        context.insert(node)

        if let parentId, let parent = nodeMap[parentId] {
            parent.childrenIds.append(nodeId)
            effectiveChildrenMap[parentId, default: []].append(nodeId)
        }
        nodeMap[nodeId] = node
        effectiveChildrenMap[nodeId] = []
        currentPath.append(node)

        conversation.currentNodeId = nodeId
        conversation.updateTime = Date()
        markConversationDirty()
        try? context.save()

        return node
    }
}
