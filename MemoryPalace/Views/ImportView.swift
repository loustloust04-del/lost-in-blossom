import SwiftUI
import SwiftData
import UIKit

struct ImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager: ThemeManager?
    @Environment(ProfileManager.self) private var profileManager: ProfileManager?
    @State private var importer: ConversationImporter?
    @State private var claudeImporter: ClaudeImporter?
    @State private var selectedProvider: String = "chatgpt"
    @State private var mergeMode: Bool = false
    @State private var downloadError: String?

    private var isImporting: Bool {
        importer?.isImporting == true || claudeImporter?.isImporting == true
    }

    private var currentStatus: String {
        switch selectedProvider {
        case "claude":
            return claudeImporter?.statusMessage ?? ""
        default:
            return importer?.statusMessage ?? ""
        }
    }

    private var currentProgress: Double {
        switch selectedProvider {
        case "claude":
            return claudeImporter?.progress ?? 0
        default:
            return importer?.progress ?? 0
        }
    }

    private var currentError: String? {
        switch selectedProvider {
        case "claude":
            return claudeImporter?.errorMessage
        default:
            return importer?.errorMessage
        }
    }

    private var currentImportedCount: Int {
        switch selectedProvider {
        case "claude":
            return claudeImporter?.importedCount ?? 0
        default:
            return importer?.importedCount ?? 0
        }
    }

    private var currentProcessedCount: Int {
        switch selectedProvider {
        case "claude":
            return claudeImporter?.processedCount ?? 0
        default:
            return importer?.processedCount ?? 0
        }
    }

    private var currentAddedCount: Int {
        switch selectedProvider {
        case "claude":
            return claudeImporter?.addedConversationCount ?? 0
        default:
            return importer?.addedConversationCount ?? 0
        }
    }

    private var currentUpdatedCount: Int {
        switch selectedProvider {
        case "claude":
            return claudeImporter?.updatedConversationCount ?? 0
        default:
            return importer?.updatedConversationCount ?? 0
        }
    }

    private var currentSkippedCount: Int {
        switch selectedProvider {
        case "claude":
            return claudeImporter?.skippedConversationCount ?? 0
        default:
            return importer?.skippedConversationCount ?? 0
        }
    }

    private var currentIgnoredCount: Int {
        switch selectedProvider {
        case "claude":
            return claudeImporter?.ignoredConversationCount ?? 0
        default:
            return importer?.ignoredConversationCount ?? 0
        }
    }

    private var currentDidCompleteImport: Bool {
        switch selectedProvider {
        case "claude":
            return claudeImporter?.didCompleteImport ?? false
        default:
            return importer?.didCompleteImport ?? false
        }
    }

    private var importDone: Bool {
        !isImporting && currentDidCompleteImport && currentError == nil
    }

    private var providerName: String {
        selectedProvider == "claude" ? "Claude" : "ChatGPT"
    }

    private var providerIntro: String {
        selectedProvider == "claude"
            ? "选 Claude 的 conversations.json，按时间线整理。"
            : "选 ChatGPT 的 conversations.json，保留分支结构。"
    }

    private var providerFootnote: String {
        selectedProvider == "claude"
            ? "Claude 导出是扁平结构。"
            : "ChatGPT 导出是树状结构。"
    }

    private var mergeModeDescription: String {
        "只追加本地没有的对话，已有对话保留本地版本。"
    }

    private var completionSummaryText: String {
        if currentAddedCount == 0 && currentUpdatedCount == 0 {
            if currentIgnoredCount > 0 {
                return "没有新变化，跳过 \(currentSkippedCount) 条，\(currentIgnoredCount) 条未导入。"
            }
            return "没有新变化，跳过 \(currentSkippedCount) 条\(providerName)对话。"
        }

        if currentUpdatedCount > 0 || currentSkippedCount > 0 {
            var parts = [
                "新增 \(currentAddedCount) 条",
                "更新 \(currentUpdatedCount) 条",
                "跳过 \(currentSkippedCount) 条"
            ]
            if currentIgnoredCount > 0 {
                parts.append("未导入 \(currentIgnoredCount) 条")
            }
            return parts.joined(separator: "，") + "。"
        }

        return "新增 \(currentImportedCount) 条 \(providerName) 对话。"
    }

    private var resultBreakdownItems: [(title: String, count: Int, detail: String)] {
        var items: [(title: String, count: Int, detail: String)] = [
            ("新增", currentAddedCount, "本地没有，这次新导入。")
        ]

        if mergeMode || currentUpdatedCount > 0 {
            items.append((
                "更新",
                currentUpdatedCount,
                "本地已有，但导入文件里这条更完整，已替换。"
            ))
        }

        items.append((
            "跳过",
            currentSkippedCount,
            mergeMode
                ? "本地已有完整版，不动。"
                : "本地已有同一条对话，不重复导入。"
        ))

        if currentIgnoredCount > 0 {
            items.append((
                "未导入",
                currentIgnoredCount,
                "空白草稿或无有效内容。"
            ))
        }

        return items
    }

    var body: some View {
        let _ = themeManager?.themeChangeID
        Group {
            iOSBody
        }
    }

    private var iOSBody: some View {
        NavigationStack {
            List {
                iOSHeroSection
                iOSProviderSection
                iOSStateSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.sidebarBg)
            .navigationTitle("导入对话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(isImporting ? Theme.textMuted : Theme.branchIndicator)
                        .disabled(isImporting)
                }
            }
        }
        .interactiveDismissDisabled(isImporting)
    }

    @ViewBuilder
    private var iOSHeroSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("读取本地 \(providerName) 导出包，不联网。")
                    .font(.system(size: Theme.F.body))
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    iOSMetaPill("本地 JSON")
                    iOSMetaPill("不联网")
                    iOSMetaPill(selectedProvider == "claude" ? "单线对话" : "保留分支")
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Theme.mainBg)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var iOSProviderSection: some View {
        Section("数据来源") {
            HStack(spacing: 10) {
                providerOption(tag: "chatgpt", title: "ChatGPT", subtitle: "树状分支", systemImage: "bubble.left.and.bubble.right")
                providerOption(tag: "claude", title: "Claude", subtitle: "单线对话", systemImage: "text.quote")
            }
            .padding(.vertical, 4)

            Text(providerFootnote)
                .font(.system(size: Theme.F.caption))
                .foregroundColor(Theme.textMuted)
        }
        .listRowBackground(Theme.mainBg)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var iOSStateSection: some View {
        if isImporting {
            Section("正在导入") {
                iOSImportingRows
            }
            .listRowBackground(Theme.mainBg)
            .listRowSeparator(.hidden)
        } else if importDone {
            Section("导入完成") {
                iOSCompletedRows
            }
            .listRowBackground(Theme.mainBg)
            .listRowSeparator(.hidden)

            Section {
                Button { dismiss() } label: {
                    HStack { Spacer(); Text("完成"); Spacer() }
                        .font(.system(size: Theme.F.body, weight: .semibold))
                        .foregroundColor(.white)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Theme.branchIndicator)
            }
            .listRowSeparator(.hidden)
        } else if let error = currentError {
            Section("导入失败") {
                iOSFailedRows(error: error)
            }
            .listRowBackground(Theme.mainBg)
            .listRowSeparator(.hidden)

            Section {
                Button {
                    switch selectedProvider {
                    case "claude": claudeImporter = nil
                    default: importer = nil
                    }
                    downloadError = nil
                } label: {
                    HStack { Spacer(); Text("返回"); Spacer() }
                        .font(.system(size: Theme.F.body, weight: .semibold))
                        .foregroundColor(.white)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Theme.branchIndicator)
            }
            .listRowSeparator(.hidden)
        } else {
            iOSIdleSections
        }
    }

    @ViewBuilder
    private var iOSIdleSections: some View {
        Section {
            Text(providerIntro)
                .font(.system(size: Theme.F.secondary))
                .foregroundColor(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("叠加导入")
                        .font(.system(size: Theme.F.body, weight: .medium))
                        .foregroundColor(Theme.textPrimary)
                    Text(mergeModeDescription)
                        .font(.system(size: Theme.F.caption))
                        .foregroundColor(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: $mergeMode)
                    .labelsHidden()
                    .tint(Theme.branchIndicator)
            }
        } header: {
            Text("选择文件")
        } footer: {
            Text("文件名一般是 conversations.json。只读本地，不联网。")
                .font(.system(size: Theme.F.caption))
        }
        .listRowBackground(Theme.mainBg)
        .listRowSeparator(.hidden)

        Section {

            Button("从 Files 粘贴导入") {
                pasteAndImport()
            }
            .font(.system(size: 14))
            .buttonStyle(.bordered)
            .disabled(isImporting)

            Text("Files App → 长按文件 → 拷贝 → 回到这里点此按钮")
                .font(.caption2)
                .foregroundColor(Theme.textMuted)
        }
        .listRowBackground(Theme.mainBg)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var iOSImportingRows: some View {
        HStack(alignment: .firstTextBaseline) {
            Label("正在导入 \(providerName)", systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: Theme.F.body, weight: .medium))
                .foregroundColor(Theme.textPrimary)
            Spacer()
            Text(currentProgress > 0 ? "\(Int(currentProgress * 100))%" : "处理中")
                .font(.system(size: Theme.F.secondary, weight: .semibold))
                .foregroundColor(Theme.branchIndicator)
        }

        ProgressView(value: max(currentProgress, 0.02))
            .tint(Theme.branchIndicator)

        Text(currentStatus.isEmpty ? "准备中…" : currentStatus)
            .font(.system(size: Theme.F.secondary))
            .foregroundColor(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

        if currentProcessedCount > 0 {
            Text("已处理 \(currentProcessedCount) 条")
                .font(.system(size: Theme.F.caption))
                .foregroundColor(Theme.textMuted)
        }

        Text("大文件会分批处理，别关这个页面。")
            .font(.system(size: Theme.F.caption))
            .foregroundColor(Theme.textMuted)
    }

    @ViewBuilder
    private var iOSCompletedRows: some View {
        Label("导入完成", systemImage: "checkmark.seal")
            .font(.system(size: Theme.F.body, weight: .medium))
            .foregroundColor(Theme.textPrimary)

        Text(completionSummaryText)
            .font(.system(size: Theme.F.secondary))
            .foregroundColor(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

        if !currentStatus.isEmpty {
            Text(currentStatus)
                .font(.system(size: Theme.F.caption))
                .foregroundColor(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }

        ForEach(Array(resultBreakdownItems.enumerated()), id: \.offset) { _, item in
            VStack(alignment: .leading, spacing: 2) {
                Text("\(item.title) \(item.count) 条")
                    .font(.system(size: Theme.F.body, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                Text(item.detail)
                    .font(.system(size: Theme.F.caption))
                    .foregroundColor(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func iOSFailedRows(error: String) -> some View {
        Label("导入失败", systemImage: "exclamationmark.triangle")
            .font(.system(size: Theme.F.body, weight: .medium))
            .foregroundColor(Theme.textPrimary)

        Text("读取 \(providerName) 文件失败，重新选一次文件试试。")
            .font(.system(size: Theme.F.secondary))
            .foregroundColor(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

        VStack(alignment: .leading, spacing: 4) {
            Text("错误信息")
                .font(.system(size: Theme.F.label, weight: .semibold))
                .foregroundColor(Theme.danger)
            Text(error)
                .font(.system(size: Theme.F.secondary))
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8).fill(Theme.danger.opacity(0.08))
        )
    }

    private func providerOption(
        tag: String,
        title: String,
        subtitle: String,
        systemImage: String
    ) -> some View {
        let isSelected = selectedProvider == tag

        return Button {
            guard !isImporting else { return }
            selectedProvider = tag
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: systemImage)
                    .font(.system(size: Theme.F.body, weight: .semibold))
                    .foregroundColor(isSelected ? Theme.textPrimary : Theme.textSecondary)

                Text(subtitle)
                    .font(.system(size: Theme.F.caption))
                    .foregroundColor(isSelected ? Theme.textSecondary : Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Theme.accent.opacity(0.55) : Theme.sidebarBg.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected ? Theme.branchIndicator.opacity(0.45) : Theme.accent.opacity(0.4),
                        lineWidth: isSelected ? 1.2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func iOSMetaPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: Theme.F.badge, weight: .medium))
            .foregroundColor(Theme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Theme.accent.opacity(0.45))
            )
    }

    private var resultBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("结果说明")
                .font(.system(size: Theme.F.sectionHeader, weight: .semibold))
                .foregroundColor(Theme.textSecondary)

            ForEach(Array(resultBreakdownItems.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(item.title) \(item.count) 条")
                        .font(.system(size: Theme.F.sectionHeader, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)

                    Text(item.detail)
                        .font(.system(size: Theme.F.caption))
                        .foregroundColor(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.accent.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.accent.opacity(0.28), lineWidth: 1)
        )
    }


    private func pasteAndImport() {
        guard !isImporting else { return }
        let pb = UIPasteboard.general
        let jsonTypes = ["public.json", "public.plain-text", "public.utf8-plain-text", "public.text"]
        var data: Data?
        for type in jsonTypes {
            if let d = pb.data(forPasteboardType: type) { data = d; break }
        }
        if data == nil, let str = pb.string { data = str.data(using: .utf8) }

        guard let jsonData = data else {
            downloadError = "剪贴板里没有 JSON 数据。在 Files 中长按文件 → 拷贝。"
            return
        }
        guard (try? JSONSerialization.jsonObject(with: jsonData)) != nil else {
            downloadError = "剪贴板内容不是有效 JSON。"
            return
        }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("clipboard_import.json")
        try? FileManager.default.removeItem(at: tempURL)
        do {
            try jsonData.write(to: tempURL)
            startImport(url: tempURL)
        } catch {
            downloadError = "写入临时文件失败：\(error.localizedDescription)"
        }
    }

    private func startImport(url: URL) {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("import_conversations.json")
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.copyItem(at: url, to: tempURL)
        if isSecurityScoped { url.stopAccessingSecurityScopedResource() }

        let container = modelContext.container

        let isMerge = mergeMode
        let profileId = profileManager?.currentProfile.id ?? ""
        switch selectedProvider {
        case "claude":
            let imp = ClaudeImporter(modelContainer: container, profileId: profileId)
            claudeImporter = imp
            Task.detached(priority: .userInitiated) {
                if isMerge {
                    await imp.mergeImportFile(url: tempURL)
                } else {
                    await imp.importFile(url: tempURL)
                }
                try? FileManager.default.removeItem(at: tempURL)
            }
        default:
            let imp = ConversationImporter(modelContainer: container, profileId: profileId)
            importer = imp
            Task.detached(priority: .userInitiated) {
                if isMerge {
                    await imp.mergeImportFile(url: tempURL)
                } else {
                    await imp.importFile(url: tempURL)
                }
                try? FileManager.default.removeItem(at: tempURL)
            }
        }
    }
}
