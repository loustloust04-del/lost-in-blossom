import Foundation

/// 群聊 V4 调度：门控 + 镜像 prompt + system prompt 组装。
///
/// 三个关键词：门控（每个角色先判断要不要说话）、串行（一个说完下一个才想）、
/// 镜像（每个角色看到自己之前说的是 assistant、别人说的是 user）。
enum GroupChatScheduler {

    /// 历史消息最小视图。
    struct HistoryItem {
        let role: String          // "user" / "assistant"
        let senderId: String?
        let senderName: String?
        let content: String
    }

    // MARK: - 镜像 prompt

    /// 站在 speaker 视角重建 messages：
    /// - speaker 自己之前说的 → role=assistant
    /// - 其他所有人 → role=user，正文加 [名字]: 前缀
    static func buildMirrorMessages(
        for speaker: GroupParticipant,
        history: [HistoryItem]
    ) -> [(role: String, content: String)] {
        var out: [(role: String, content: String)] = []
        for m in history where !m.content.isEmpty {
            if m.senderId == speaker.id {
                // 自己说的 → assistant
                out.append((role: "assistant", content: m.content))
            } else {
                // 别人说的（包括用户和其他角色）→ user + 标注
                let name = m.senderName ?? (m.role == "user" ? "用户" : "AI")
                out.append((role: "user", content: "[\(name)]: \(m.content)"))
            }
        }
        print("[GroupChat] 镜像 messages for \(speaker.name): \(out.count) 条")
        return out
    }

    // MARK: - System Prompt

    /// 组装 system prompt。优先级：
    /// 1. 群聊角色指令（固定）
    /// 2. participant.systemPrompt（用户在创建页输入的）
    /// 3. 角色卡内容（如果绑定了角色卡）
    /// 4. preset 内容（如果选了 preset）
    static func buildSystemPrompt(
        for participant: GroupParticipant,
        card: CharacterCard? = nil,
        preset: Preset? = nil
    ) -> String {
        var parts: [String] = []

        // 固定群聊指令
        parts.append(
            "你正在一个多人群聊里，只扮演「\(participant.name)」这一个角色。"
            + "其他参与者的消息会用 [名字]: 前缀标注。"
            + "规则：只以「\(participant.name)」的身份回复；不替别人发言；"
            + "回复正文不加 [名字]: 前缀；像真人群聊一样自然简洁。"
        )

        // 用户自定义 system prompt（创建页填写的）
        if !participant.systemPrompt.isEmpty {
            parts.append(participant.systemPrompt)
        }

        // 角色卡（如果有绑定）
        if let card {
            if !card.systemPrompt.isEmpty { parts.append(card.systemPrompt) }
            if !card.description.isEmpty { parts.append("【角色设定】\n\(card.description)") }
            if !card.personality.isEmpty { parts.append("【性格】\n\(card.personality)") }
            if !card.scenario.isEmpty { parts.append("【场景】\n\(card.scenario)") }
        }

        // preset
        if let preset {
            let presetSys = preset.prompts
                .filter { $0.isSystemPrompt && !$0.isMarker && !$0.content.isEmpty }
                .map(\.content)
                .joined(separator: "\n")
            if !presetSys.isEmpty { parts.append(presetSys) }
        }

        let result = parts.joined(separator: "\n\n")
        print("[GroupChat] system prompt for \(participant.name): \(result.count) chars")
        return result
    }

    // MARK: - 门控

    static func buildGatePrompt(
        participant: GroupParticipant,
        recentHistory: [HistoryItem],
        newMessage: HistoryItem
    ) -> String {
        let desc = String(participant.systemPrompt.prefix(200))
        let recent = recentHistory.suffix(5).map { h -> String in
            let name = h.senderName ?? (h.role == "user" ? "用户" : "AI")
            return "[\(name)]: \(String(h.content.prefix(100)))"
        }.joined(separator: "\n")
        let newName = newMessage.senderName ?? "用户"
        return """
        你是群聊中的「\(participant.name)」。
        简述：\(desc.isEmpty ? "无" : desc)

        最近消息：
        \(recent.isEmpty ? "（无）" : recent)

        最新：[\(newName)]: \(String(newMessage.content.prefix(200)))

        你需要回复吗？
        - @你的名字 → YES
        - 话题相关 → YES
        - 已有充分回应 → NO
        - 连续说了2条以上 → NO

        只输出 YES 或 NO。
        """
    }

    static func parseGate(_ response: String) -> Bool {
        let up = response.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if up.hasPrefix("YES") || up == "Y" { return true }
        if up.hasPrefix("NO") || up == "N" { return false }
        print("[GroupChat] ⚠️ 门控返回无法解析: \(response)")
        return true  // 模糊时让它说话
    }

    /// 廉价门控模型：优先 deepseek-chat，其次任意 deepseek，最后角色自己的模型。
    static func cheapGateModel(providerManager: ProviderManager, fallbackModelId: String) -> ProviderModel? {
        let available = providerManager.availableModels
        if let ds = available.first(where: { $0.providerId == "deepseek" && $0.modelId.contains("chat") }) {
            return ds
        }
        if let ds = available.first(where: { $0.providerId == "deepseek" }) { return ds }
        return providerManager.model(byId: fallbackModelId)
    }

    /// 门控判断：用廉价模型跑 YES/NO。
    static func gateCheck(
        participant: GroupParticipant,
        recentHistory: [HistoryItem],
        newMessage: HistoryItem,
        providerManager: ProviderManager
    ) async -> Bool {
        // @点名 → 直接 YES
        if newMessage.content.contains("@\(participant.name)") {
            print("[GroupChat] 门控: \(participant.name) → YES (@点名)")
            return true
        }
        // CC → 跳过门控
        if participant.model.hasPrefix("cc-bridge") {
            print("[GroupChat] 门控: \(participant.name) → YES (CC)")
            return true
        }

        guard let gateModel = cheapGateModel(providerManager: providerManager,
                                             fallbackModelId: participant.model) else {
            print("[GroupChat] ⚠️ 门控: \(participant.name) 找不到模型，默认 YES")
            return true
        }

        let prompt = buildGatePrompt(participant: participant,
                                     recentHistory: recentHistory,
                                     newMessage: newMessage)
        do {
            let router = ProviderRouter()
            let (resp, _) = try await router.sendNonStreaming(
                model: gateModel,
                messages: [(role: "user", content: prompt)],
                systemPrompt: nil,
                providerManager: providerManager
            )
            let result = parseGate(resp)
            print("[GroupChat] 门控: \(participant.name) → \(result ? "YES" : "NO") (model: \(gateModel.name), raw: \(resp.prefix(20)))")
            return result
        } catch {
            print("[GroupChat] ⚠️ 门控调用失败: \(participant.name) error=\(error.localizedDescription)，默认 YES")
            return true
        }
    }

    /// @点名解析。
    static func mentioned(in input: String, participants: [GroupParticipant]) -> GroupParticipant? {
        for p in participants.sorted(by: { $0.name.count > $1.name.count })
        where input.contains("@\(p.name)") {
            return p
        }
        return nil
    }
}
