import SwiftUI

struct CreateChatroomView: View {
    /// 创建成功后回调，传回新 session（已含后端返回的 id）。
    let onCreated: (ChatroomSession) -> Void

    private var service = ChatroomService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var topic = ""
    @State private var aiAName = "Caelum"
    @State private var aiAModel = ChatroomModelOption.options[1].id
    @State private var aiASystem = ""
    @State private var aiBName = "DeepSeek"
    @State private var aiBModel = ChatroomModelOption.options[0].id
    @State private var aiBSystem = ""
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
                        system: $aiASystem
                    )

                    aiSection(
                        title: "AI B",
                        accent: .green,
                        name: $aiBName,
                        model: $aiBModel,
                        system: $aiBSystem
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
        system: Binding<String>
    ) -> some View {
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
                    ForEach(ChatroomModelOption.options) { option in
                        Text(option.label).tag(option.id)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.branchIndicator)
            }

            fieldSection("System Prompt（可选）") {
                TextEditor(text: system)
                    .font(.system(size: Theme.F.body))
                    .frame(minHeight: 60)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.mainBg.opacity(0.8)))
                    .scrollContentBackground(.hidden)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.mainBg.opacity(0.4)))
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

    private func start() {
        guard canStart else { return }
        isCreating = true
        errorMessage = nil
        Task {
            do {
                let id = try await service.startSession(
                    topic: topic.trimmingCharacters(in: .whitespaces),
                    aiAModel: aiAModel,
                    aiAName: aiAName.trimmingCharacters(in: .whitespaces),
                    aiASystem: aiASystem,
                    aiBModel: aiBModel,
                    aiBName: aiBName.trimmingCharacters(in: .whitespaces),
                    aiBSystem: aiBSystem
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
                    ended_at: nil
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

// MARK: - Model Options

struct ChatroomModelOption: Identifiable {
    let id: String
    let label: String

    static let options: [ChatroomModelOption] = [
        ChatroomModelOption(id: "deepseek/deepseek-chat", label: "DeepSeek Chat"),
        ChatroomModelOption(id: "anthropic/claude-sonnet-4", label: "Claude Sonnet 4"),
        ChatroomModelOption(id: "anthropic/claude-opus-4", label: "Claude Opus 4"),
    ]
}
