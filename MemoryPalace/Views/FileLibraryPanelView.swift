import SwiftUI
import MarkdownUI

// MARK: - File Library Panel (右栏文件库 tab)

struct FileLibraryPanelView: View {
    @Environment(ProfileManager.self) private var profileManager: ProfileManager?

    // 统一到服务器笔记本（架构审计：文件库唯一真相源 = Gateway /api/notebook）。
    // 你在 app 编辑的、API Caelum 写的、CC Caelum 写的，全是同一本。
    // 本地 FileLibraryStore 保留给附件存储（AttachmentStore），不再作为笔记本。
    @State private var remoteFiles: [NotebookRemoteStore.FileMeta] = []
    @State private var remoteError: String? = nil
    @State private var isLoadingRemote = false
    @State private var showNewFileAlert = false
    @State private var newFileName = ""
    @State private var deletingPath: String? = nil
    @State private var editingFile: EditingFile? = nil
    @State private var previews: [String: String] = [:]

    private var profileId: String { profileManager?.currentProfile.id ?? "" }
    private var isEmpty: Bool { remoteFiles.isEmpty }

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    struct EditingFile: Identifiable { let id = UUID(); let path: String; let content: String }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let remoteError {
                errorState(remoteError)
            } else if isEmpty {
                emptyState
            } else {
                fileList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.sidebarBg)
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .fileLibraryDidChange)) { _ in reload() }
        // CC 在服务器上写完笔记，hub 会广播一帧过来。收到就重拉，省掉手动下拉。
        .onReceive(NotificationCenter.default.publisher(for: .ccNotebookChanged)) { _ in reload() }
        .alert("新建文件", isPresented: $showNewFileAlert) {
            TextField("文件名（可含 / 子目录）", text: $newFileName)
            Button("创建") { createFile() }
            Button("取消", role: .cancel) { newFileName = "" }
        } message: {
            Text("会自动补 .md 后缀")
        }
        .confirmationDialog(
            "删除文件",
            isPresented: Binding(get: { deletingPath != nil }, set: { if !$0 { deletingPath = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) { confirmDelete() }
            Button("取消", role: .cancel) { deletingPath = nil }
        } message: {
            Text(deletingPath.map { "确定删除「\($0)」吗？不可恢复。" } ?? "")
        }
        .sheet(item: $editingFile) { f in
            FileEditorSheet(path: f.path, initialContent: f.content,
                onSave: { newContent in
                    Task {
                        try? await NotebookRemoteStore.write(f.path, content: newContent)
                        await MainActor.run { editingFile = nil; reload() }
                    }
                },
                onCancel: { editingFile = nil }
            )
        }
    }

    // MARK: - Source picker

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(isLoadingRemote ? "读取中…" : "\(remoteFiles.count) 个文件")
                .font(.system(size: Theme.F.secondary))
                .foregroundColor(Theme.textMuted)
            Spacer()
            Button { newFileName = ""; showNewFileAlert = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 12))
                    Text("新建")
                        .font(.system(size: Theme.F.secondary))
                }
                .foregroundColor(Theme.branchIndicator)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - List

    private var fileList: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(remoteFiles) { meta in
                    fileCard(CardMeta(path: meta.path, subtitle: byteText(meta.bytes)))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private struct CardMeta { let path: String; let subtitle: String }

    private func fileCard(_ meta: CardMeta) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.accent.opacity(0.4))
                Text((previews[meta.path]?.isEmpty == false) ? previews[meta.path]! : "（空文件）")
                    .font(.system(size: 8.5))
                    .foregroundColor(Theme.textSecondary.opacity(0.7))
                    .lineLimit(9)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(9)
                    .frame(height: 118, alignment: .top)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white)
                    )
                    .padding(.horizontal, 12)
                    .offset(y: 16)
            }
            .frame(height: 122)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.accent.opacity(0.72), lineWidth: 1)
            )

            Text(meta.path)
                .font(.system(size: Theme.F.body, weight: .medium))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 2)

            Text(meta.subtitle)
                .font(.system(size: Theme.F.secondary))
                .foregroundColor(Theme.textMuted)
                .padding(.horizontal, 2)
        }
        .padding(6)
        .contentShape(Rectangle())
        .onTapGesture { openFile(meta.path) }
        .contextMenu {
            Button("删除", role: .destructive) { deletingPath = meta.path }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "folder")
                .font(.system(size: 24))
                .foregroundColor(Theme.textMuted.opacity(0.4))
            Text("笔记本还是空的")
                .font(.system(size: Theme.F.body))
                .foregroundColor(Theme.textMuted)
            Text("新建一个 .md，或让 Caelum 用 fs_write 写进来")
                .font(.system(size: Theme.F.caption))
                .foregroundColor(Theme.textMuted.opacity(0.6))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Ops

    private func reload() {
        reloadRemote()
    }

    /// 服务器那本要走网络，逐个拉正文做预览。笔记本一般只有几个文件，
    /// 串行拉够用；真多起来再考虑并发或者让网关直接返回摘要。
    private func reloadRemote() {
        guard NotebookRemoteStore.isConfigured else {
            remoteFiles = []
            remoteError = "还没配网关 token，连不上服务器笔记本"
            return
        }
        isLoadingRemote = true
        Task {
            do {
                let list = try await NotebookRemoteStore.list()
                var p: [String: String] = [:]
                for meta in list {
                    if let content = try? await NotebookRemoteStore.read(meta.path) {
                        p[meta.path] = String(content.prefix(280))
                    }
                }
                await MainActor.run {
                    remoteFiles = list
                    previews = p
                    remoteError = nil
                    isLoadingRemote = false
                }
            } catch {
                await MainActor.run {
                    remoteError = error.localizedDescription
                    isLoadingRemote = false
                }
            }
        }
    }

    private func openFile(_ path: String) {
        Task {
            let content = (try? await NotebookRemoteStore.read(path)) ?? ""
            await MainActor.run {
                editingFile = EditingFile(path: path, content: content)
            }
        }
    }

    private func createFile() {
        var name = newFileName.trimmingCharacters(in: .whitespaces)
        newFileName = ""
        guard !name.isEmpty else { return }
        if !name.hasSuffix(".md") { name += ".md" }
        Task {
            try? await NotebookRemoteStore.write(name, content: "")
            await MainActor.run { reload() }
        }
    }

    private func confirmDelete() {
        guard let p = deletingPath else { return }
        deletingPath = nil
        Task {
            try? await NotebookRemoteStore.delete(p)
            await MainActor.run { reload() }
        }
    }

    private func byteText(_ bytes: Int) -> String {
        bytes < 1024 ? "\(bytes) B" : String(format: "%.1f KB", Double(bytes) / 1024)
    }

    private func errorState(_ msg: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "exclamationmark.icloud")
                .font(.system(size: 24))
                .foregroundColor(Theme.textMuted.opacity(0.4))
            Text(msg)
                .font(.system(size: Theme.F.body))
                .foregroundColor(Theme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("重试") { reload() }
                .font(.system(size: Theme.F.secondary))
                .foregroundColor(Theme.branchIndicator)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $isPreview) {
                    Text("预览").tag(true)
                    Text("编辑").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .tint(Theme.branchIndicator)

                Divider()

                if isPreview {
                    ScrollView {
                        Markdown(content)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    TextEditor(text: $content)
                        .font(.system(size: Theme.F.body))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                }
            }
            .background(Theme.mainBg)
            .navigationTitle(path)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { onCancel() }
                        .foregroundColor(Theme.textMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { onSave(content) }
                        .foregroundColor(Theme.branchIndicator)
                        .disabled(content == initialContent)
                }
            }
        }
    }
}
