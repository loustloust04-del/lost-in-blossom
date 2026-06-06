import SwiftUI

struct CreateChatroomView: View {
    /// 创建成功后回调，传回新 session（已含后端返回的 id）。
    let onCreated: (ChatroomSession) -> Void

    private var service = ChatroomService.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(PresetManager.self) private var presetManager: PresetManager?

    @State private var topic = ""
    @State private var aiAName = "Caelum"
    @State private var aiAModel = ""
    @State private var aiASystem = ""
    @State private var aiAPresetId: String? = nil
    @State private var aiBName = "DeepSeek"
    @State private var aiBModel = ""
    @State private var aiBSystem = ""
    @State private var aiBPresetId: String? = nil
    @State private var isCreating = false
    @State private var errorMessage: String?

    init(onCreated: @escaping (ChatroomSession) -> Void) {
        self.onCreated = onCreated
    }

    private var canStart: Bool {
        !topic.trimmingCharacters(in: .whitespaces).isEmpty
            && !aiAName.trimmingCharacters(in: .whitespaces).isEmpty
            && !aiBName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider().opacity(0.2)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    fieldSection("话题") {
                        TextField("给 AI 们一个话题...", text: $topic, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: Theme.F.body))
                            .lineLimit(1...3)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.mainBg.opacity(0.8)))
                    }

                    aiSection(
                        title: "AI A",
                        accent: .blue,
                        name: $aiAName,
                        model: $aiAModel,
                        system: $aiASystem,
                        presetId: $aiAPresetId
                    )

                    aiSection(
                        title: "AI B",
                        accent: .green,
                        name: $aiBName,
                        model: $aiBModel,
                        system: $aiBSystem,
                        presetId: $aiBPresetId
                    )

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: Theme.F.secondary))
                            .foregroundColor(Theme.danger)
                    }
                }
                .padding(16)
            }
        }
        .background(Theme.sidebarBg)
        .task {
            await service.fetchModels()
            if aiAModel.isEmpty, let first = service.availableModels.first {
                aiAModel = first.id
            }
            if aiBModel.isEmpty, let first = service.availableModels.first {
                aiBModel = first.id
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button("取消") { dismiss() }
                .buttonStyle(.plain)
                .foregroundColor(Theme.branchIndicator)
            Spacer()
            Text("新建群聊")
                .font(.system(size: Theme.F.sectionHeader, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
            Spacer()
            Button {
                start()
            } label: {
                Text("开始")
                    .foregroundColor(canStart ? .white : Theme.textMuted)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(canStart ? Theme.branchIndicator : Theme.textMuted.opacity(0.3)))
            }
            .buttonStyle(.plain)
            .disabled(!canStart || isCreating)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - AI Section

    private func aiSection(
        title: String,
        accent: Color,
        name: Binding<String>,
        model: Binding<String>,
        system: Binding<String>,
        presetId: Binding<String?>
    ) -> some View {
        // 选中的 Preset（nil = 无预设，走自由文本）
        let selectedPreset = presetId.wrappedValue.flatMap { id in presetManager?.preset(byId: id) }
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(accent).frame(width: 8, height: 8)
                Text(title)
                    .font(.system(size: Theme.F.label, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
            }

            fieldSection("名字") {
                TextField("名字", text: name)
                    .textFieldStyle(.plain)
                    .font(.system(size: Theme.F.body))
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.mainBg.opacity(0.8)))
            }

            fieldSection("模型") {
                Picker("模型", selection: model) {
                    ForEach(service.availableModels) { model in
                        Text(model.label).tag(model.id)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.branchIndicator)
            }

            fieldSection("预设") {
                Picker("预设", selection: presetId) {
                    Text("无预设").tag(String?.none)
                    ForEach(presetManager?.allPresets ?? []) { preset in
                        Text(preset.name).tag(String?.some(preset.id))
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.branchIndicator)
            }

            // 选了 Preset → System Prompt 只读预览 main slot；没选 → 自由文本输入
            if let preset = selectedPreset {
                fieldSection("System Prompt（来自预设，只读）") {
                    Text(presetMainPreview(preset))
                        .font(.system(size: Theme.F.body))
                        .foregroundColor(Theme.textMuted)
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.mainBg.opacity(0.5)))
                        .textSelection(.enabled)
                }
            } else {
                fieldSection("System Prompt（可选）") {
                    TextEditor(text: system)
                        .font(.system(size: Theme.F.body))
                        .frame(minHeight: 60)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.mainBg.opacity(0.8)))
                        .scrollContentBackground(.hidden)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.mainBg.opacity(0.4)))
    }

    /// 取 Preset 的 main slot 内容作为只读预览；没有就退回第一个有内容的 system 插槽。
    private func presetMainPreview(_ preset: Preset) -> String {
        if let main = preset.prompts.first(where: { $0.id == PromptSlot.mainId }),
           !main.content.isEmpty {
            return main.content
        }
        if let firstFilled = preset.prompts.first(where: { $0.role == "system" && !$0.content.isEmpty }) {
            return firstFilled.content
        }
        return "（此预设的 main 指令为空，将注入其它启用的插槽）"
    }

    private func fieldSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: Theme.F.secondary))
                .foregroundColor(Theme.textMuted)
            content()
        }
    }

    // MARK: - Actions

    /// 把选中的 Preset 序列化成后端要的 slot 数组（只取启用的插槽）。没选 → nil。
    private func presetSlots(for presetId: String?) -> [[String: Any]]? {
        guard let id = presetId, let preset = presetManager?.preset(byId: id) else { return nil }
        return preset.prompts.filter { $0.isEnabled }.map { slot in
            [
                "role": slot.role,
                "content": slot.content,
                "injection_depth": slot.injectionDepth,
                "injection_order": slot.injectionOrder,
                "is_marker": slot.isMarker,
                "name": slot.name,
            ]
        }
    }

    private func presetName(for presetId: String?) -> String? {
        guard let id = presetId else { return nil }
        return presetManager?.preset(byId: id)?.name
    }

    private func start() {
        guard canStart else { return }
        isCreating = true
        errorMessage = nil
        let aiASlots = presetSlots(for: aiAPresetId)
        let aiBSlots = presetSlots(for: aiBPresetId)
        let aiAPName = presetName(for: aiAPresetId)
        let aiBPName = presetName(for: aiBPresetId)
        Task {
            do {
                let id = try await service.startSession(
                    topic: topic.trimmingCharacters(in: .whitespaces),
                    aiAModel: aiAModel,
                    aiAName: aiAName.trimmingCharacters(in: .whitespaces),
                    aiASystem: aiASystem,
                    aiBModel: aiBModel,
                    aiBName: aiBName.trimmingCharacters(in: .whitespaces),
                    aiBSystem: aiBSystem,
                    aiAPresetSlots: aiASlots,
                    aiBPresetSlots: aiBSlots,
                    aiAPresetName: aiAPName,
                    aiBPresetName: aiBPName
                )
                let newSession = ChatroomSession(
                    id: id,
                    topic: topic.trimmingCharacters(in: .whitespaces),
                    ai_a_model: aiAModel,
                    ai_a_name: aiAName.trimmingCharacters(in: .whitespaces),
                    ai_b_model: aiBModel,
                    ai_b_name: aiBName.trimmingCharacters(in: .whitespaces),
                    status: "active",
                    rounds: 0,
                    created_at: "",
                    ended_at: nil,
                    ai_a_preset_name: aiAPName,
                    ai_b_preset_name: aiBPName
                )
                await MainActor.run {
                    isCreating = false
                    onCreated(newSession)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                    errorMessage = "创建失败：\(error.localizedDescription)"
                }
            }
        }
    }
}

