import SwiftUI

/// 群聊 V2 创建页：从角色卡库多选 2~4 张卡，每个参与者可改名/选模型/选 Preset。
/// 纯 UI；创建逻辑（写 Conversation(kind:"group") + 各卡 firstMes 首条消息）由
/// onCreate 回调里的 ConversationViewModel.createGroupConversation 完成。
struct CreateGroupChatView: View {
    /// 回调：返回组装好的参与者列表。父视图负责建会话并打开。
    let onCreate: ([GroupParticipant]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(CharacterCardManager.self) private var cardManager: CharacterCardManager?
    @Environment(PresetManager.self) private var presetManager: PresetManager?

    @State private var selectedIds: [String] = []          // 选中顺序 = 发言轮询顺序
    @State private var nameOverride: [String: String] = [:]
    @State private var modelChoice: [String: String] = [:]
    @State private var presetChoice: [String: String] = [:]

    private let palette = ["#7C9CBF", "#C28E6B", "#8FA876", "#B07CA8"]

    private var cards: [CharacterCard] { cardManager?.cards ?? [] }
    private var presets: [Preset] { presetManager?.presets ?? [] }
    private var models: [ChatroomService.GatewayModel] { ChatroomService.shared.availableModels }

    private var canCreate: Bool { selectedIds.count >= 2 && selectedIds.count <= 4 }

    var body: some View {
        NavigationStack {
            Form {
                Section("选择角色（2~4）") {
                    ForEach(cards) { card in
                        let on = selectedIds.contains(card.id)
                        Button {
                            toggle(card.id)
                        } label: {
                            HStack {
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(on ? .accentColor : .secondary)
                                Text(card.name).foregroundStyle(.primary)
                                Spacer()
                                if on, let idx = selectedIds.firstIndex(of: card.id) {
                                    Text("\(idx + 1)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if cards.isEmpty {
                        Text("还没有角色卡，先去卡库创建").foregroundStyle(.secondary)
                    }
                }

                ForEach(selectedIds, id: \.self) { cid in
                    if let card = cards.first(where: { $0.id == cid }) {
                        Section("参与者：\(card.name)") {
                            TextField("显示名", text: bindingName(cid, card.name))
                            Picker("模型", selection: bindingModel(cid)) {
                                ForEach(models) { m in Text(m.id).tag(m.id) }
                            }
                            Picker("Preset", selection: bindingPreset(cid)) {
                                Text("默认").tag("")
                                ForEach(presets) { p in Text(p.name).tag(p.id) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("新建群聊")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") { create() }.disabled(!canCreate)
                }
            }
        }
    }

    private func toggle(_ id: String) {
        if let i = selectedIds.firstIndex(of: id) { selectedIds.remove(at: i) }
        else if selectedIds.count < 4 { selectedIds.append(id) }
    }
    private func bindingName(_ cid: String, _ def: String) -> Binding<String> {
        Binding(get: { nameOverride[cid] ?? def }, set: { nameOverride[cid] = $0 })
    }
    private func bindingModel(_ cid: String) -> Binding<String> {
        Binding(get: { modelChoice[cid] ?? models.first?.id ?? "" }, set: { modelChoice[cid] = $0 })
    }
    private func bindingPreset(_ cid: String) -> Binding<String> {
        Binding(get: { presetChoice[cid] ?? "" }, set: { presetChoice[cid] = $0 })
    }

    private func create() {
        var participants: [GroupParticipant] = []
        for (idx, cid) in selectedIds.enumerated() {
            guard let card = cards.first(where: { $0.id == cid }) else { continue }
            participants.append(GroupParticipant(
                name: nameOverride[cid] ?? card.name,
                characterCardID: cid,
                model: modelChoice[cid] ?? models.first?.id ?? "",
                presetId: presetChoice[cid] ?? "",
                colorHex: palette[idx % palette.count]
            ))
        }
        guard participants.count >= 2 else { return }
        onCreate(participants)
        dismiss()
    }
}
