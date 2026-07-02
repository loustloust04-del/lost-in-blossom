import SwiftUI

/// 群聊创建页 V5：群名 + 角色卡（可选）+ 模型 + 话痨度 + 气泡颜色 + 补充 prompt。
/// 选卡只存 characterCardID，卡内容由 GroupChatScheduler 运行时组装（改卡自动生效）。
struct CreateGroupChatView: View {
    let onCreate: ([GroupParticipant], String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ProviderManager.self) private var providerManager: ProviderManager?
    @Environment(CharacterCardManager.self) private var cardManager: CharacterCardManager?

    @State private var groupTitle: String = ""
    @State private var slots: [SlotState] = [
        SlotState(name: "Caelum", colorHex: "#7C9CBF"),
        SlotState(name: "", colorHex: "#C28E6B")
    ]

    private var models: [ProviderModel] { providerManager?.allModels ?? [] }
    private var cards: [CharacterCard] { cardManager?.cards ?? [] }

    private var canCreate: Bool {
        let filled = slots.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        return filled.count >= 2 && !models.isEmpty
    }

    private static let palette = ["#7C9CBF", "#C28E6B", "#8FA876", "#B07CA8", "#D9A05B", "#6BA8A0", "#A87C7C", "#8E8EC2"]

    var body: some View {
        NavigationStack {
            Form {
                titleSection
                participantSections
                addButton
            }
            .navigationTitle("新建群聊")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("开始") { create() }
                        .disabled(!canCreate)
                }
            }
        }
    }

    // MARK: - Sections

    private var titleSection: some View {
        Section {
            TextField("默认用成员名拼接", text: $groupTitle)
        } header: {
            Text("群聊名称（可选）")
        }
    }

    private var participantSections: some View {
        ForEach(slots.indices, id: \.self) { idx in
            Section {
                cardPicker(for: idx)
                TextField("名字", text: $slots[idx].name)
                modelPicker(for: idx)
                talkativenessSlider(for: idx)
                colorRow(for: idx)
                systemPromptField(for: idx)
            } header: {
                HStack {
                    Circle()
                        .fill(Color(hex: slots[idx].colorHex) ?? .gray)
                        .frame(width: 8, height: 8)
                    Text("AI \(Character(UnicodeScalar(65 + idx)!))")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if slots.count > 2 {
                        Button { slots.remove(at: idx) } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cardPicker(for idx: Int) -> some View {
        if !cards.isEmpty {
            Picker("角色卡", selection: $slots[idx].characterCardID) {
                Text("不用卡（自定义）").tag("")
                ForEach(cards) { card in
                    Text(card.name).tag(card.id)
                }
            }
            .onChange(of: slots[idx].characterCardID) { _, newId in
                guard idx < slots.count,
                      let card = cards.first(where: { $0.id == newId }) else { return }
                slots[idx].name = card.name
            }
        }
    }

    private func modelPicker(for idx: Int) -> some View {
        Picker("模型", selection: $slots[idx].modelId) {
            if models.isEmpty {
                Text("无可用模型").tag("")
            }
            ForEach(models) { m in
                Text(m.name).tag(m.id)
            }
        }
        .onAppear {
            if slots[idx].modelId.isEmpty, let first = models.first {
                slots[idx].modelId = first.id
            }
        }
    }

    private func talkativenessSlider(for idx: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("话痨度")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(slots[idx].talkativeness * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text("沉默")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Slider(value: $slots[idx].talkativeness, in: 0...1, step: 0.05)
                Text("话痨")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func colorRow(for idx: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("气泡颜色")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(Self.palette, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex) ?? .gray)
                        .frame(width: 24, height: 24)
                        .overlay {
                            if slots[idx].colorHex == hex {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .onTapGesture { slots[idx].colorHex = hex }
                }
                Spacer()
            }
        }
    }

    private func systemPromptField(for idx: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("补充 Prompt（可选，叠加在角色卡之上）")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $slots[idx].systemPrompt)
                .frame(minHeight: 60, maxHeight: 120)
                .font(.callout)
        }
    }

    @ViewBuilder
    private var addButton: some View {
        if slots.count < 4 {
            Section {
                Button {
                    let color = Self.palette[slots.count % Self.palette.count]
                    slots.append(SlotState(name: "", colorHex: color))
                } label: {
                    Label("添加参与者", systemImage: "plus.circle")
                }
            }
        }
    }

    // MARK: - Create

    private func create() {
        let participants: [GroupParticipant] = slots.compactMap { slot in
            let name = slot.name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            let modelId = slot.modelId.isEmpty ? (models.first?.id ?? "") : slot.modelId
            return GroupParticipant(
                name: name,
                characterCardID: slot.characterCardID,
                model: modelId,
                colorHex: slot.colorHex,
                systemPrompt: slot.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
                talkativeness: slot.talkativeness
            )
        }
        guard participants.count >= 2 else { return }
        onCreate(participants, groupTitle.trimmingCharacters(in: .whitespaces))
        dismiss()
    }
}

// MARK: - Slot State

private struct SlotState {
    var name: String
    var modelId: String = ""
    var systemPrompt: String = ""
    var colorHex: String
    var characterCardID: String = ""
    var talkativeness: Double = 0.5
}

// MARK: - Color(hex:)

private extension Color {
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
        self.init(
            red: Double((val >> 16) & 0xFF) / 255,
            green: Double((val >> 8) & 0xFF) / 255,
            blue: Double(val & 0xFF) / 255
        )
    }
}
