import Foundation

/// 群聊参与者。存在 Conversation.participantsData（JSON 编码），避免新增 @Model，
/// 从而不必改 ProfileManager.fullSchema。
struct GroupParticipant: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var characterCardID: String
    var model: String           // provider model combined id
    var presetId: String
    var colorHex: String        // 气泡颜色
    var systemPrompt: String    // 每个参与者独立的 system prompt

    init(id: String = UUID().uuidString,
         name: String,
         characterCardID: String = "",
         model: String,
         presetId: String = "",
         colorHex: String,
         systemPrompt: String = "") {
        self.id = id
        self.name = name
        self.characterCardID = characterCardID
        self.model = model
        self.presetId = presetId
        self.colorHex = colorHex
        self.systemPrompt = systemPrompt
    }

    // 向后兼容：旧数据没有 systemPrompt 字段也能正常解码
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        characterCardID = try c.decodeIfPresent(String.self, forKey: .characterCardID) ?? ""
        model = try c.decode(String.self, forKey: .model)
        presetId = try c.decodeIfPresent(String.self, forKey: .presetId) ?? ""
        colorHex = try c.decode(String.self, forKey: .colorHex)
        systemPrompt = try c.decodeIfPresent(String.self, forKey: .systemPrompt) ?? ""
    }
}
