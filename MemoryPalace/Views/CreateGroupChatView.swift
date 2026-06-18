import SwiftUI

/// 群聊创建页 V4：直接输入名字 + 选模型 + 可选 system prompt。
/// 不依赖角色卡，每个参与者独立配置。
struct CreateGroupChatView: View {
    let onCreate: ([GroupParticipant]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ProviderManager.self) private var providerManager: ProviderManager?

    @State private var slots: [SlotState] = [
        SlotState(name: "Caelum", colorHex: "#7C9CBF"),
        SlotState(name: "", colorHex: "#C28E6B")
    ]

    private var models: [ProviderModel] {
        providerManager?.availableModels ?? []
    }

    private var canCreate: Bool {
        let filled = slots.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        return filled.count >= 2 && !models.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
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

    private var participantSections: some View {
        ForEach(slots.indices, id: \.self) { idx in
            Section {
                TextField("名字", text: $slots[idx].name)
                modelPicker(for: idx)
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

    private func systemPromptField(for idx: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("System Prompt（可选）")
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
                    let colors = ["#7C9CBF", "#C28E6B", "#8FA876", "#B07CA8"]
                    let color = colors[slots.count % colors.count]
                    slots.append(SlotState(name: "", colorHex: color))
                } label: {
                    Label("添加参与者", systemImage: "plus.circle")
                }
            }
        }
    }

    // MARK: - Create

    private func create() {
        let participants: [GroupParticipant] = slots.enumerated().compactMap { idx, slot in
            let name = slot.name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            let modelId = slot.modelId.isEmpty ? (models.first?.id ?? "") : slot.modelId
            return GroupParticipant(
                name: name,
                model: modelId,
                colorHex: slot.colorHex,
                systemPrompt: slot.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        guard participants.count >= 2 else { return }
        onCreate(participants)
        dismiss()
    }
}

// MARK: - Slot State

private struct SlotState {
    var name: String
    var modelId: String = ""
    var systemPrompt: String = ""
    var colorHex: String
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
