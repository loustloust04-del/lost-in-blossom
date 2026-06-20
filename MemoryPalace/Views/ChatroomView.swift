import SwiftUI

struct ChatroomView: View {
    let session: ChatroomSession

    private var service = ChatroomService.shared
    @State private var inputText = ""
    @State private var sendTarget = "round"  // round / ai_a / ai_b / silent
    @Environment(\.dismiss) private var dismiss

    init(session: ChatroomSession) {
        self.session = session
    }

    private var targetLabel: String {
        switch sendTarget {
        case "ai_a": return "@" + (session.ai_a_name)
        case "ai_b": return "@" + (session.ai_b_name)
        case "silent": return "只发送"
        default: return "Round"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider().opacity(0.2)

            messagesScroll

            Divider().opacity(0.2)

            inputBar
        }
        .background(Theme.mainBg)
        .task {
            try? await service.fetchHistory(sessionId: session.id)
            service.subscribeStream(sessionId: session.id)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.topic)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    nameTag(session.ai_a_name, preset: session.ai_a_preset_name, color: .blue)
                    Text("·")
                        .foregroundColor(Theme.textMuted)
                    nameTag(session.ai_b_name, preset: session.ai_b_preset_name, color: .green)
                }
            }

            Spacer()

            Button {
                dismiss()
                Task { try? await service.endSession(sessionId: session.id) }
            } label: {
                Text("结束")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.danger)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func nameTag(_ name: String, preset: String? = nil, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(name)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(color)
            if let preset, !preset.isEmpty {
                Text("· \(preset)")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textMuted)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Messages

    private var messagesScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    Color.clear.frame(height: 4)
                    ForEach(service.currentMessages) { message in
                        messageRow(message)
                            .id(message.id)
                    }

                    // 正在说话的 AI：流式文字
                    if service.isStreaming, let role = service.streamingRole, !service.streamingContent.isEmpty {
                        streamingRow(role: role, content: service.streamingContent)
                            .id("streaming")
                    } else if service.isStreaming {
                        typingIndicator
                            .id("streaming")
                    }

                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(.horizontal, 14)
            }
            .onChange(of: service.currentMessages.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: service.streamingContent) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ message: ChatroomMessage) -> some View {
        if message.role == "user" {
            HStack {
                Spacer(minLength: 50)
                Text(message.content)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.userBubble))
            }
        } else {
            let isA = message.role == "ai_a"
            let bubbleColor = isA ? Color.blue.opacity(0.12) : Color.green.opacity(0.12)
            let labelColor = isA ? Color.blue : Color.green
            let name = isA ? session.ai_a_name : session.ai_b_name
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(labelColor)
                    .padding(.leading, 4)
                HStack {
                    Text(message.content)
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 14).fill(bubbleColor))
                    Spacer(minLength: 50)
                }
            }
        }
    }

    private func streamingRow(role: String, content: String) -> some View {
        let isA = role == "ai_a"
        let bubbleColor = isA ? Color.blue.opacity(0.12) : Color.green.opacity(0.12)
        let labelColor = isA ? Color.blue : Color.green
        let name = isA ? session.ai_a_name : session.ai_b_name
        return VStack(alignment: .leading, spacing: 3) {
            Text(name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(labelColor)
                .padding(.leading, 4)
            HStack {
                Text(content)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 14).fill(bubbleColor))
                Spacer(minLength: 50)
            }
        }
    }

    private var typingIndicator: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(Theme.textMuted.opacity(0.5))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.assistantBubble))
            Spacer()
        }
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(spacing: 10) {
            // 发送目标选择
            Menu {
                Button { sendTarget = "round" } label: {
                    Label("Round（都说）", systemImage: sendTarget == "round" ? "checkmark" : "")
                }
                Button { sendTarget = "ai_a" } label: {
                        Label("@\(session.ai_a_name)", systemImage: sendTarget == "ai_a" ? "checkmark" : "")
                    }
                    Button { sendTarget = "ai_b" } label: {
                        Label("@\(session.ai_b_name)", systemImage: sendTarget == "ai_b" ? "checkmark" : "")
                    }
                Button { sendTarget = "silent" } label: {
                    Label("只发送", systemImage: sendTarget == "silent" ? "checkmark" : "")
                }
            } label: {
                Text(targetLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.accent.opacity(0.1))
                    .clipShape(Capsule())
            }

            TextField("说点什么，或留空继续…", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 18).fill(Theme.mainBg.opacity(0.8)))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Theme.textMuted.opacity(0.15), lineWidth: 1)
                )

            let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            Button {
                if trimmed.isEmpty {
                    Task { try? await service.continueRound(sessionId: session.id, target: sendTarget) }
                } else {
                    let text = trimmed
                    inputText = ""
                    Task { try? await service.sendMessage(sessionId: session.id, content: text, target: sendTarget) }
                }
            } label: {
                Text(trimmed.isEmpty ? "继续" : "发送")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Theme.branchIndicator))
            }
            .buttonStyle(.plain)
            .disabled(service.isStreaming)
            .opacity(service.isStreaming ? 0.5 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
