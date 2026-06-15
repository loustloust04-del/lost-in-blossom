import Foundation
import SwiftData

// MARK: - 群聊 V3 串行编排（门控 + 串行 + 镜像）

extension ConversationViewModel {

    /// 群聊一轮：存用户消息 → 串行遍历 participants（门控判断 → YES 才说话）。
    /// 串行的关键：后面的角色能看到前面角色刚说的话（已存入 currentPath）。
    @MainActor
    func runGroupRound(
        conversation: Conversation,
        userText: String,
        participants: [GroupParticipant],
        providerManager: ProviderManager,
        context: ModelContext
    ) async {
        let userName = UserDefaults.standard.string(forKey: "userName") ?? "我"

        // 1. 用户消息入树（带 senderName 供镜像 prompt 标注）
        insertGroupNode(role: "user", content: userText,
                        senderId: nil, senderName: userName,
                        conversation: conversation, context: context)

        // 全局资产（UserDefaults 备份），即时实例化读取即可
        let cardManager = CharacterCardManager()
        let presetManager = PresetManager()

        // 2. 串行遍历每个角色
        for participant in participants {
            let history = groupHistoryItems()
            guard let latest = history.last else { continue }
            let card = cardManager.cards.first { $0.id == participant.characterCardID }

            // 门控：要不要说话
            let speak = await GroupChatScheduler.gateCheck(
                participant: participant,
                cardDescription: card?.description ?? "",
                recentHistory: history,
                newMessage: latest,
                providerManager: providerManager
            )
            guard speak else { continue }

            // 说话（组装 prompt → 流式 → 存）
            await groupSpeak(
                participant: participant,
                card: card,
                preset: presetManager.preset(byId: participant.presetId),
                conversation: conversation,
                providerManager: providerManager,
                context: context
            )
        }
    }

    /// 单个角色发言：建占位节点 → 镜像 messages → providerRouter 流式 → 等完成。
    @MainActor
    private func groupSpeak(
        participant: GroupParticipant,
        card: CharacterCard?,
        preset: Preset?,
        conversation: Conversation,
        providerManager: ProviderManager,
        context: ModelContext
    ) async {
        guard let model = providerManager.model(byId: participant.model) else { return }
        let systemPrompt = GroupChatScheduler.buildSystemPrompt(for: participant, card: card, preset: preset)
        let messages = GroupChatScheduler.buildMirrorMessages(for: participant, history: groupHistoryItems())

        let node = insertGroupNode(role: "assistant", content: "",
                                   senderId: participant.id, senderName: participant.name,
                                   conversation: conversation, context: context)

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
                onComplete: { full, _ in
                    if !full.isEmpty { node.content = full }
                    try? context.save()
                    resume()
                },
                onError: { err in
                    if node.content.isEmpty { node.content = "⚠️ \(err)" }
                    try? context.save()
                    resume()
                }
            )
        }
    }

    /// 当前 path 投影成 HistoryItem（跳过空 system root / 空占位）。
    private func groupHistoryItems() -> [GroupChatScheduler.HistoryItem] {
        currentPath.compactMap { node in
            guard node.role == "user" || node.role == "assistant", !node.content.isEmpty else { return nil }
            return GroupChatScheduler.HistoryItem(
                role: node.role, senderId: node.senderId,
                senderName: node.senderName, content: node.content
            )
        }
    }

    /// 建节点并接入树/path（复用单聊的 nodeMap / effectiveChildrenMap 机制）。
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

    /// 新建群聊会话（kind=group + participants），插入隐形 root 节点。
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
        return conversation
    }
}
