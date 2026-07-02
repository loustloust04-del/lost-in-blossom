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

        // 镜像 prompt（含角色关系）
        let messages = GroupChatScheduler.buildMirrorMessages(
            for: participant, history: groupHistoryItems(),
            participants: allParticipants
        )

        guard !messages.isEmpty else {
            print("[GroupV5] ⚠️ \(participant.name): 镜像 messages 为空，跳过")
            return
        }

        // 创建 assistant node
        let node = insertGroupNode(
            role: "assistant", content: "",
            senderId: participant.id, senderName: participant.name,
            conversation: conversation, context: context
        )

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
                systemPrompt: systemPrompt,
                providerManager: providerManager,
                samplingParams: SamplingParams(temperature: 0.8, maxTokens: 300),
                onToken: { [weak self] token in
                    guard let self else { return }
                    accumulated += token
                    streamingText = accumulated
                    // 不做 per-token SwiftData 写（V5 流式优化）
                },
                onComplete: { fullText, usage in
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
                onError: { error in
                    if accumulated.isEmpty {
                        node.content = "⚠️ \(error)"
                    } else {
                        node.content = accumulated
                    }
                    try? context.save()
                    resume()
                }
            )
        }

        streamingText = ""
    }

    // MARK: - 工具函数

    /// 提取群聊历史为 HistoryItem 数组。
    func groupHistoryItems() -> [GroupChatScheduler.HistoryItem] {
        currentPath.map { node in
            GroupChatScheduler.HistoryItem(
                role: node.role,
                senderId: node.senderId,
                senderName: node.senderName,
                content: node.content
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
