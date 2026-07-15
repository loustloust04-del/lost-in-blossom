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

        // 写临时 .md，然后弹系统分享面板（存文件/隔空投送/发给自己…）
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(MarkdownExporter.sanitizedFileName(conversation.title)).md")
        do {
            try markdown.write(to: tmpURL, atomically: true, encoding: .utf8)
        } catch {
            ToastCenter.shared.show("导出失败：\(error.localizedDescription)")
            dismiss()
            return
        }
        // 先收起本 sheet，再弹 UIActivityViewController（StickerViewModel 先例：SwiftUI
        // sheet 关闭回调里弹 UIKit VC 不可靠，改直接从当前 keyWindow 的顶层 VC present）。
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            presentShareSheet(for: tmpURL)
        }
    }

    /// 从当前活跃 window 的最顶层 VC 弹系统分享面板。
    private func presentShareSheet(for url: URL) {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first,
              var top = window.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }

        let ac = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        // iPad：给 popover 一个锚点，避免崩溃
        if let pop = ac.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        top.present(ac, animated: true)
    }
}
