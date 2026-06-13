import Foundation

/// 群聊 V2 参与者。存在 Conversation.participantsData（JSON 编码），避免新增 @Model，
/// 从而不必改 ProfileManager.fullSchema。
struct GroupParticipant: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var characterCardID: String
    var model: String        // provider model id，如 "anthropic/claude-opus-4.8"
    var presetId: String
    var colorHex: String     // 气泡颜色，如 "#7C9CBF"

    init(id: String = UUID().uuidString,
         name: String,
         characterCardID: String,
         model: String,
         presetId: String,
         colorHex: String) {
        self.id = id
        self.name = name
        self.characterCardID = characterCardID
        self.model = model
        self.presetId = presetId
        self.colorHex = colorHex
    }
}
