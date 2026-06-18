import Foundation
import SwiftData

// MARK: - 群聊 V4 串行编排（门控 + 串行 + 镜像）

extension ConversationViewModel {

    /// 群聊一轮：存用户消息 → 串行遍历 participants（门控 → YES 才说话）。
    @MainActor
    func runGroupRound(
        conversation: Conversation,
        userText: String,
        participants: [GroupParticipant],
        providerManager: ProviderManager,
        context: ModelContext
    ) async {
        let userName = UserDefaults.standard.string(forKey: "userName") ?? "我"
        print("[GroupChat] ═══ 新一轮 ═══ 用户: \(userText.prefix(50))... 参与者: \(participants.map(\.name))")

        // 1. 用户消息入树
        insertGroupNode(role: "user", content: userText,
                        senderId: nil, senderName: userName,
                        conversation: conversation, context: context)

        // 角色卡 & preset 管理器（用于绑定了角色卡的参与者）
        let cardManager = CharacterCardManager()
        let presetManager = PresetManager()

        // 2. 串行遍历每个角色
        for participant in participants {
            let history = groupHistoryItems()
            guard let latest = history.last else {
                print("[GroupChat] ⚠️ \(participant.name): 历史为空，跳过")
                continue
            }

            // 解析模型
            guard let model = providerManager.model(byId: participant.model) else {
                print("[GroupChat] ❌ \(participant.name): 模型 '\(participant.model)' 找不到！可用模型: \(providerManager.availableModels.map(\.id).prefix(5))")
                // 在聊天里显示错误而不是静默跳过
                insertGroupNode(role: "assistant", content: "⚠️ 模型 \(participant.model) 未找到",
                                senderId: participant.id, senderName: participant.name,
                                conversation: conversation, context: context)
                continue
            }

            // 门控
            let speak = await GroupChatScheduler.gateCheck(
                participant: participant,
                recentHistory: history,
                newMessage: latest,
                providerManager: providerManager
            )
            guard speak else {
                print("[GroupChat] \(participant.name): 门控 NO，跳过")
                continue
            }

            // 说话
            print("[GroupChat] \(participant.name): 开始发言 (model: \(model.name))")
            await groupSpeak(
                participant: participant,
                card: cardManager.cards.first { $0.id == participant.characterCardID },
                preset: presetManager.preset(byId: participant.presetId),
                conversation: conversation,
                model: model,
                providerManager: providerManager,
                context: context
            )
            print("[GroupChat] \(participant.name): 发言完成")
        }
        print("[GroupChat] ═══ 轮次结束 ═══")
    }

    /// 单个角色发言。
    @MainActor
    private func groupSpeak(
        participant: GroupParticipant,
        card: CharacterCard?,
        preset: Preset?,
        conversation: Conversation,
        model: ProviderModel,
        providerManager: ProviderManager,
        context: ModelContext
    ) async {
        let systemPrompt = GroupChatScheduler.buildSystemPrompt(
            for: participant, card: card, preset: preset
        )
        let messages = GroupChatScheduler.buildMirrorMessages(
            for: participant, history: groupHistoryItems()
        )

        guard !messages.isEmpty else {
            print("[GroupChat] ⚠️ \(participant.name): 镜像 messages 为空，跳过")
            return
        }

        let node = insertGroupNode(
            role: "assistant", content: "",
            senderId: participant.id, senderName: participant.name,
            conversation: conversation, context: context
        )

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            var finished = false
            let resume = {
                if !finished { finished = true; cont.resume() }
            }

            providerRouter.sendStreaming(
                model: model,
                messages: messages,
                systemPrompt: systemPrompt.isEmpty ? nil : systemPrompt,
                providerManager: providerManager,
                onToken: { token in
                    node.content += token
                },
                onComplete: { full, usage in
                    if !full.isEmpty { node.content = full }
                    let tokens = usage.map { "in=\($0.inputTokens) out=\($0.outputTokens)" } ?? "无"
                    print("[GroupChat] ✅ \(participant.name) 完成: \(full.prefix(80))... tokens: \(tokens)")
                    try? context.save()
                    resume()
                },
                onError: { err in
                    print("[GroupChat] ❌ \(participant.name) 错误: \(err)")
                    if node.content.isEmpty {
                        node.content = "⚠️ \(err)"
                    }
                    try? context.save()
                    resume()
                }
            )
        }
    }

    /// 当前 path 投影成 HistoryItem。
    private func groupHistoryItems() -> [GroupChatScheduler.HistoryItem] {
        currentPath.compactMap { node in
            guard node.role == "user" || node.role == "assistant", !node.content.isEmpty else { return nil }
            return GroupChatScheduler.HistoryItem(
                role: node.role, senderId: node.senderId,
                senderName: node.senderName, content: node.content
            )
        }
    }

    /// 建节点并接入树/path。
    @discardableResult
    @MainActor
    private func insertGroupNode(
        role: String, content: String,
        senderId: String?, senderName: String?,
        conversation: Conversation, context: ModelContext
    ) -> MessageNode {
        let parentId = currentPath.last?.id
        let nodeId = UUID().uuidString
        let node = MessageNode(
            id: nodeId, role: role, content: content, contentType: "text",
            createTime: Date(), parentId: parentId, childrenIds: [],
            conversationId: conversation.id, profileId: conversation.profileId
        )
        node.senderId = senderId
        node.senderName = senderName
        context.insert(node)

        if let parentId, let parent = nodeMap[parentId], !parent.childrenIds.contains(nodeId) {
            parent.childrenIds.append(nodeId)
        }
        nodeMap[nodeId] = node
        effectiveChildrenMap[nodeId] = []
        if let parentId {
            effectiveChildrenMap[parentId, default: []].append(nodeId)
        }
        currentPath.append(node)

        conversation.currentNodeId = nodeId
        conversation.updateTime = Date()
        conversation.nodeCount = currentPath.filter {
            ($0.role == "user" || $0.role == "assistant") && !$0.content.isEmpty
        }.count
        markConversationDirty()
        try? context.save()
        scrollToNodeId = nodeId
        return node
    }

    /// 新建群聊会话。
    func createGroupConversation(
        participants: [GroupParticipant],
        profileId: String,
        context: ModelContext
    ) -> Conversation {
        let rootId = UUID().uuidString
        let names = participants.map(\.name).joined(separator: "、")
        let conversation = Conversation(
            id: UUID().uuidString,
            title: names.isEmpty ? "群聊" : "群聊：\(names)",
            createTime: Date(),
            updateTime: Date(),
            currentNodeId: rootId,
            provider: "api",
            profileId: profileId
        )
        conversation.kind = "group"
        conversation.participants = participants
        context.insert(conversation)

        let rootNode = MessageNode(
            id: rootId, role: "system", content: "", contentType: "text",
            createTime: Date(), parentId: nil, childrenIds: [],
            conversationId: conversation.id, profileId: profileId
        )
        context.insert(rootNode)
        try? context.save()
        print("[GroupChat] 创建群聊: \(names) participants=\(participants.count)")
        return conversation
    }
}
