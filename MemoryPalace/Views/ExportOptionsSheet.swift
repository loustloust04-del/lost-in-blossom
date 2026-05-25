import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ExportOptionsSheet: View {
    let conversation: Conversation
    var viewModel: ConversationViewModel
    let userName: String
    let assistantName: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMode: ExportPathMode = .longest

    /// Whether the conversation is currently loaded in the ViewModel
    private var isConversationLoaded: Bool {
        viewModel.selectedConversation?.id == conversation.id && !viewModel.currentPath.isEmpty
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("导出选项")
                .font(.system(size: Theme.F.sectionHeader, weight: .semibold))
                .foregroundColor(Theme.textPrimary)

            Text(conversation.title)
                .font(.system(size: Theme.F.secondary))
                .foregroundColor(Theme.textMuted)
                .lineLimit(1)

            VStack(spacing: 4) {
                exportOption(
                    title: "最长分支",
                    description: "自动选择最长的对话路径",
                    mode: .longest
                )

                if isConversationLoaded {
                    exportOption(
                        title: "当前显示路径",
                        description: "导出当前正在查看的路径",
                        mode: .current
                    )
                }

                exportOption(
                    title: "主路径",
                    description: "导出 ChatGPT 默认的主路径",
                    mode: .mainPath
                )

                exportOption(
                    title: "完整树",
                    description: "所有分支，非主线用折叠显示",
                    mode: .fullTree
                )
            }

            HStack {
                Button("取消") { dismiss() }
                    .foregroundColor(Theme.textMuted)
                    .buttonStyle(.plain)

                Spacer()

                Button(action: { performExport() }) {
                    Text("导出")
                        .font(.system(size: Theme.F.secondary, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Theme.branchIndicator)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private func exportOption(title: String, description: String, mode: ExportPathMode) -> some View {
        Button(action: { selectedMode = mode }) {
            HStack(spacing: 8) {
                Image(systemName: selectedMode == mode ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundColor(selectedMode == mode ? Theme.branchIndicator : Theme.textMuted.opacity(0.5))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: Theme.F.body))
                        .foregroundColor(Theme.textPrimary)
                    Text(description)
                        .font(.system(size: Theme.F.caption))
                        .foregroundColor(Theme.textMuted)
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selectedMode == mode ? Theme.accent.opacity(0.4) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func performExport() {
        let markdown: String

        if selectedMode == .current && isConversationLoaded {
            // Use ViewModel's loaded data for current path
            markdown = viewModel.exportMarkdown(
                mode: .current,
                userName: userName,
                assistantName: assistantName
            )
        } else if (selectedMode == .mainPath || selectedMode == .longest || selectedMode == .fullTree) && isConversationLoaded {
            // Can use ViewModel data for these too
            markdown = viewModel.exportMarkdown(
                mode: selectedMode,
                userName: userName,
                assistantName: assistantName
            )
        } else {
            // Load from context (conversation not displayed)
            markdown = MarkdownExporter.loadAndExport(
                conversation: conversation,
                context: modelContext,
                mode: selectedMode,
                userName: userName,
                assistantName: assistantName
            )
        }

        // Save file
        #if os(macOS)
        let panel = NSSavePanel()
        panel.title = "导出 Markdown"
        panel.nameFieldStringValue = "\(MarkdownExporter.sanitizedFileName(conversation.title)).md"
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? markdown.write(to: url, atomically: true, encoding: .utf8)
        #else
        // iOS: 暂时保存到临时目录（后续接 ShareSheet）
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(MarkdownExporter.sanitizedFileName(conversation.title)).md")
        try? markdown.write(to: tmpURL, atomically: true, encoding: .utf8)
        #endif

        dismiss()
    }
}
