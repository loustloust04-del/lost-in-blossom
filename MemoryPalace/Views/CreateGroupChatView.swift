import SwiftUI

/// 群聊 V3 创建页（简化版）：多选 2~4 张角色卡，每张可选模型 + preset。
struct CreateGroupChatView: View {
    let onCreate: ([GroupParticipant]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(CharacterCardManager.self) private var cardManager: CharacterCardManager?
    @Environment(PresetManager.self) private var presetManager: PresetManager?
    @Environment(ProviderManager.self) private var providerManager: ProviderManager?

    @State private var selectedIds: [String] = []
    @State private var nameOverride: [String: String] = [:]
    @State private var modelChoice: [String: String] = [:]
    @State private var presetChoice: [String: String] = [:]

    private let palette = ["#7C9CBF", "#C28E6B", "#8FA876", "#B07CA8"]

    private var cards: [CharacterCard] { cardManager?.cards ?? [] }
    private var presets: [Preset] { presetManager?.presets ?? [] }
    private var models: [ProviderModel] { providerManager?.availableModels ?? [] }
    private var canCreate: Bool { selectedIds.count >= 2 && selectedIds.count <= 4 }

    var body: some View {
        NavigationStack {
            Form {
                cardSelectionSection
                participantSections
            }
            .navigationTitle("新建群聊")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") { create() }.disabled(!canCreate)
                }
            }
        }
    }

    // MARK: - Sections

    private var cardSelectionSection: some View {
        Section("选择角色（2~4 个）") {
            if cards.isEmpty {
                Text("还没有角色卡，先去卡库创建").foregroundStyle(.secondary)
            } else {
                ForEach(cards) { card in cardRow(card) }
            }
        }
    }

    private func cardRow(_ card: CharacterCard) -> some View {
        let on = selectedIds.contains(card.id)
        return Button { toggle(card.id) } label: {
            HStack {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? Color.accentColor : Color.secondary)
                Text(card.name).foregroundStyle(.primary)
                Spacer()
                if on, let idx = selectedIds.firstIndex(of: card.id) {
                    Text("\(idx + 1)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var participantSections: some View {
        ForEach(selectedIds, id: \.self) { cid in
            if let card = cards.first(where: { $0.id == cid }) {
                participantSection(cid: cid, card: card)
            }
        }
    }

    private func participantSection(cid: String, card: CharacterCard) -> some View {
        Section("参与者：\(card.name)") {
            TextField("显示名", text: bindingName(cid, card.name))
            Picker("模型", selection: bindingModel(cid)) {
                ForEach(models) { m in Text(m.name).tag(m.id) }
            }
            Picker("Preset", selection: bindingPreset(cid)) {
                Text("默认").tag("")
                ForEach(presets) { p in Text(p.name).tag(p.id) }
            }
        }
    }

    // MARK: - Logic

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
        let parts: [GroupParticipant] = selectedIds.enumerated().compactMap { (idx, cid) -> GroupParticipant? in
            guard let card = cards.first(where: { $0.id == cid }) else { return nil }
            let nameRaw = (nameOverride[cid] ?? card.name).trimmingCharacters(in: .whitespacesAndNewlines)
            let model = modelChoice[cid] ?? models.first?.id ?? ""
            let preset = presetChoice[cid] ?? ""
            let color = palette[idx % palette.count]
            return GroupParticipant(
                name: nameRaw.isEmpty ? card.name : nameRaw,
                characterCardID: cid,
                model: model,
                presetId: preset,
                colorHex: color
            )
        }
        guard parts.count >= 2 else { return }
        onCreate(parts)
        dismiss()
    }
}
