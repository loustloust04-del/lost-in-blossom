import SwiftUI
import SwiftData

// MARK: - Add Memory Sheet（page2 添加记忆，学 SlotEditPage 样板）

struct AddMemorySheet: View {
    let profileId: String
    let onAdded: () -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var content: String = ""
    @State private var category: String = "fact"

    private static let categories: [(key: String, label: String)] = [
        ("fact", "事实"), ("preference", "偏好"), ("relationship", "关系"),
        ("goal", "目标"), ("context", "情境")
    ]

    private var trimmed: String { content.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            List {
                Section("内容") {
                    TextEditor(text: $content)
                        .font(.system(size: Theme.F.body))
                        .frame(minHeight: 120)
                        .scrollContentBackground(.hidden)
                }
                .listRowBackground(Theme.mainBg)

                Section("分类") {
                    Picker("分类", selection: $category) {
                        ForEach(Self.categories, id: \.key) { c in
                            Text(c.label).tag(c.key)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.branchIndicator)
                }
                .listRowBackground(Theme.mainBg)
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.plain)
            #endif
            .scrollContentBackground(.hidden)
            .background(Theme.sidebarBg)
            .navigationTitle("添加记忆")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundColor(Theme.textMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { commit() }
                        .foregroundColor(trimmed.isEmpty ? Theme.textMuted : Theme.branchIndicator)
                        .disabled(trimmed.isEmpty)
                }
            }
            #if os(macOS)
            .frame(width: 480, height: 380)
            #endif
        }
    }

    private func commit() {
        guard !trimmed.isEmpty else { return }
        let store = SwiftDataMemoryStore()
        try? store.add(
            content: trimmed, category: category, keywords: [],
            profileId: profileId, isUserExplicit: true, extractedBy: "manual",
            sourceConversationId: nil, context: modelContext
        )
        onAdded()
        dismiss()
    }
}
