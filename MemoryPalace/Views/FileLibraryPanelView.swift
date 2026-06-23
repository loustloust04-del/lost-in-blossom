import SwiftUI
import MarkdownUI

// MARK: - File Library Panel (右栏文件库 tab)

struct FileLibraryPanelView: View {
    @Environment(ProfileManager.self) private var profileManager: ProfileManager?

    @State private var files: [FileLibraryStore.FileMeta] = []
    @State private var showNewFileAlert = false
    @State private var newFileName = ""
    @State private var deletingPath: String? = nil
    @State private var editingFile: EditingFile? = nil
    @State private var previews: [String: String] = [:]

    private var profileId: String { profileManager?.currentProfile.id ?? "" }

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    struct EditingFile: Identifiable { let id = UUID(); let path: String; let content: String }

    var body: some View {
        VStack(spacing: 0) {
            header
            if files.isEmpty { emptyState } else { fileList }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.sidebarBg)
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .profileWillSwitch)) { _ in files = [] }
        .onReceive(NotificationCenter.default.publisher(for: .fileLibraryDidChange)) { _ in reload() }
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
                    try? FileLibraryStore.write(f.path, content: newContent, profileId: profileId)
                    editingFile = nil
                    reload()
                },
                onCancel: { editingFile = nil }
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("\(files.count) 个文件")
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
                ForEach(files, id: \.path) { meta in
                    fileCard(meta)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private func fileCard(_ meta: FileLibraryStore.FileMeta) -> some View {
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

            Text(relativeDate(meta.modifiedAt))
                .font(.system(size: Theme.F.secondary))
                .foregroundColor(Theme.textMuted)
                .padding(.horizontal, 2)
        }
        .padding(6)
        .contentShape(Rectangle())
        .onTapGesture { openFile(meta) }
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
            Text("文件库是空的")
                .font(.system(size: Theme.F.body))
                .foregroundColor(Theme.textMuted)
            Text("新建一个 .md，或让小克自己写")
                .font(.system(size: Theme.F.caption))
                .foregroundColor(Theme.textMuted.opacity(0.6))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Ops

    private func reload() {
        files = FileLibraryStore.list(profileId: profileId)
        var p: [String: String] = [:]
        for meta in files {
            if let content = try? FileLibraryStore.read(meta.path, profileId: profileId) {
                p[meta.path] = String(content.prefix(280))
            }
        }
        previews = p
    }

    private func openFile(_ meta: FileLibraryStore.FileMeta) {
        let content = (try? FileLibraryStore.read(meta.path, profileId: profileId)) ?? ""
        editingFile = EditingFile(path: meta.path, content: content)
    }

    private func createFile() {
        var name = newFileName.trimmingCharacters(in: .whitespaces)
        newFileName = ""
        guard !name.isEmpty else { return }
        if !name.hasSuffix(".md") { name += ".md" }
        try? FileLibraryStore.write(name, content: "", profileId: profileId)
        reload()
    }

    private func confirmDelete() {
        guard let p = deletingPath else { return }
        try? FileLibraryStore.delete(p, profileId: profileId)
        deletingPath = nil
        reload()
    }

    private func relativeDate(_ date: Date) -> String {
        let days = Int(-date.timeIntervalSinceNow / 86400)
        if days <= 0 { return "今天" }
        if days == 1 { return "昨天" }
        if days < 30 { return "\(days)天前" }
        return "\(days / 30)月前"
    }
}

// MARK: - File Editor Sheet

struct FileEditorSheet: View {
    let path: String
    let initialContent: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var content: String
    @State private var isPreview: Bool = true

    init(path: String, initialContent: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.path = path
        self.initialContent = initialContent
        self.onSave = onSave
        self.onCancel = onCancel
        _content = State(initialValue: initialContent)
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
