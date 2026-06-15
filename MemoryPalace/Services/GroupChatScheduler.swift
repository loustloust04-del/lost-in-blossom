import Foundation

/// 群聊 V3 调度：门控 + 镜像 prompt + 系统 prompt 组装。
///
/// 设计三关键词：门控（每个角色先判断要不要说话）、串行（一个说完下一个才想，
/// 能接前面的话）、标注（每条消息带 senderName）。
///
/// 这里放纯逻辑 + 廉价门控；串行编排 runGroupRound 在 ConversationViewModel+Group，
/// 因为它要驱动 SwiftData 节点树 + 流式（属于 ViewModel 的职责）。
enum GroupChatScheduler {

    /// 历史消息最小视图（从 MessageNode 投影）。
    struct HistoryItem {
        let role: String          // "user" / "assistant"
        let senderId: String?
        let senderName: String?
        let content: String
    }

    // MARK: - 镜像 prompt

    /// 站在 speaker 视角重建 messages：
    /// - speaker 自己之前说的 → role=assistant（让模型觉得是自己说的）
    /// - 其他所有人（用户 + 别的角色）→ role=user，正文加 `[名字]: ` 前缀
    static func buildMirrorMessages(
        for speaker: GroupParticipant,
        history: [HistoryItem]
    ) -> [(role: String, content: String)] {
        var out: [(role: String, content: String)] = []
        for m in history where !m.content.isEmpty {
            if m.role == "assistant", m.senderId == speaker.id {
                out.append((role: "assistant", content: m.content))
            } else {
                let name = m.senderName ?? (m.role == "user" ? "用户" : "AI")
                out.append((role: "user", content: "[\(name)]: \(m.content)"))
            }
        }
        return out
    }

    // MARK: - 系统 prompt（每个角色用自己的角色卡 + preset）

    static func buildSystemPrompt(
        for participant: GroupParticipant,
        card: CharacterCard?,
        preset: Preset?
    ) -> String {
        var parts: [String] = []
        parts.append(
            "你正在一个多人群聊里，只扮演「\(participant.name)」这一个角色。"
            + "其他参与者（用户和别的角色）的消息会用 [名字]: 前缀标注是谁说的。"
            + "规则：只以「\(participant.name)」的身份和口吻回复；绝不替别人发言、不复述别人的话、"
            + "回复正文里不要加 [名字]: 前缀；像真人在群里聊天，简洁自然，可以只说一两句，也可以接别人的话。"
        )
        if let card {
            if !card.systemPrompt.isEmpty { parts.append(card.systemPrompt) }
            if !card.description.isEmpty { parts.append("【角色设定】\n\(card.description)") }
            if !card.personality.isEmpty { parts.append("【性格】\n\(card.personality)") }
            if !card.scenario.isEmpty { parts.append("【场景】\n\(card.scenario)") }
        }
        if let preset {
            let presetSys = preset.prompts
                .filter { $0.isSystemPrompt && !$0.isMarker && !$0.content.isEmpty }
                .map(\.content)
                .joined(separator: "\n")
            if !presetSys.isEmpty { parts.append(presetSys) }
        }
        return parts.joined(separator: "\n\n")
    }

    // MARK: - 门控

    static func buildGatePrompt(
        participant: GroupParticipant,
        cardDescription: String,
        recentHistory: [HistoryItem],
        newMessage: HistoryItem
    ) -> String {
        let desc = String(cardDescription.prefix(200))
        let recent = recentHistory.suffix(5).map { h -> String in
            let name = h.senderName ?? (h.role == "user" ? "用户" : "AI")
            return "[\(name)]: \(h.content)"
        }.joined(separator: "\n")
        let newName = newMessage.senderName ?? "用户"
        return """
        你是一个群聊中的角色"\(participant.name)"。
        你的性格简述：\(desc)

        最近的群聊记录：
        \(recent.isEmpty ? "（无）" : recent)

        最新消息：
        [\(newName)]: \(newMessage.content)

        判断：你需要回复这条消息吗？
        - 有人 @你的名字 → YES
        - 话题跟你的性格/兴趣直接相关 → YES
        - 已经有其他人充分回应了 → NO
        - 你最近连续说了2条以上 → NO（克制一下）

        只输出 YES 或 NO，不要其他内容。
        """
    }

    static func parseGate(_ response: String) -> Bool {
        let up = response.uppercased()
        if up.contains("YES") { return true }
        if up.contains("NO") { return false }
        return true  // 模糊时倾向于让它说话，避免群里冷场
    }

    /// 廉价门控模型：优先 enabled 的 deepseek-chat，其次任意 deepseek，最后角色自己的模型。
    static func cheapGateModel(providerManager: ProviderManager, fallbackModelId: String) -> ProviderModel? {
        let available = providerManager.availableModels
        if let ds = available.first(where: { $0.providerId == "deepseek" && $0.modelId.contains("chat") }) {
            return ds
        }
        if let ds = available.first(where: { $0.providerId == "deepseek" }) { return ds }
        return providerManager.model(byId: fallbackModelId)
    }

    /// 门控判断：用廉价模型跑 YES/NO。
    /// - @点名命中 → 直接 YES（不烧 token）
    /// - CC 角色（cc-bridge）→ 跳过门控，交给 CC 自己判断（plan §7）
    static func gateCheck(
        participant: GroupParticipant,
        cardDescription: String,
        recentHistory: [HistoryItem],
        newMessage: HistoryItem,
        providerManager: ProviderManager
    ) async -> Bool {
        if newMessage.content.contains("@\(participant.name)") { return true }
        if participant.model.hasPrefix("cc-bridge") { return true }

        guard let gateModel = cheapGateModel(providerManager: providerManager,
                                             fallbackModelId: participant.model) else {
            return true
        }
        let prompt = buildGatePrompt(participant: participant, cardDescription: cardDescription,
                                     recentHistory: recentHistory, newMessage: newMessage)
        do {
            let router = ProviderRouter()
            let (resp, _) = try await router.sendNonStreaming(
                model: gateModel,
                messages: [(role: "user", content: prompt)],
                systemPrompt: nil,
                providerManager: providerManager
            )
            return parseGate(resp)
        } catch {
            return true  // 门控失败默认让它说话
        }
    }

    // MARK: - @点名解析（供 UI / 单角色触发）

    static func mentioned(in input: String, participants: [GroupParticipant]) -> GroupParticipant? {
        for p in participants.sorted(by: { $0.name.count > $1.name.count })
        where input.contains("@\(p.name)") {
            return p
        }
        return nil
    }
}
