import Foundation

/// 群聊 V2 调度器：决定下一个发言者 + 为该发言者构造镜像 prompt。
/// 纯逻辑，无副作用，方便单测；实际建节点/流式由 ConversationViewModel 驱动。
enum GroupChatScheduler {

    /// 历史消息的最小视图（来自 MessageNode）。
    struct HistoryItem {
        let role: String           // "user" / "assistant"
        let senderId: String?
        let senderName: String?
        let content: String
    }

    /// 下一个发言者：
    /// - userInput 含 `@名字` → 只调被点名的角色（点名覆盖轮询）
    /// - 否则轮询：lastSpeaker 的下一个；无 lastSpeaker → 第一个
    static func nextSpeaker(
        participants: [GroupParticipant],
        lastSpeakerId: String?,
        userInput: String?
    ) -> GroupParticipant? {
        guard !participants.isEmpty else { return nil }
        if let input = userInput, !input.isEmpty {
            // 长名字优先匹配，避免 "@小白" 命中 "@小"
            for p in participants.sorted(by: { $0.name.count > $1.name.count })
            where input.contains("@\(p.name)") {
                return p
            }
        }
        guard let last = lastSpeakerId,
              let idx = participants.firstIndex(where: { $0.id == last }) else {
            return participants.first
        }
        return participants[(idx + 1) % participants.count]
    }

    /// 镜像 prompt：站在 speaker 的视角重建 messages。
    /// - 用户消息 → role=user（原样）
    /// - speaker 自己的发言 → role=assistant
    /// - 其他 AI 的发言 → role=user，正文加 `[名字]: ` 前缀
    /// 连续同 role 由各 provider 自行合并；这里不强行交替。
    static func buildMessages(
        for speaker: GroupParticipant,
        history: [HistoryItem]
    ) -> [(role: String, content: String)] {
        var out: [(role: String, content: String)] = []
        for m in history {
            if m.content.isEmpty { continue }
            if m.role == "user" {
                out.append((role: "user", content: m.content))
            } else if m.role == "assistant" {
                if m.senderId == speaker.id {
                    out.append((role: "assistant", content: m.content))
                } else {
                    let name = m.senderName ?? "AI"
                    out.append((role: "user", content: "[\(name)]: \(m.content)"))
                }
            }
        }
        return out
    }

    /// 从 @名字 解析出被点名的参与者 id（无则 nil），供 UI 高亮"轮到谁"用。
    static func mentioned(in input: String, participants: [GroupParticipant]) -> GroupParticipant? {
        for p in participants.sorted(by: { $0.name.count > $1.name.count })
        where input.contains("@\(p.name)") {
            return p
        }
        return nil
    }
}
