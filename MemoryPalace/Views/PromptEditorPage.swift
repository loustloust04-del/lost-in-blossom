import SwiftUI

// MARK: - Prompt Editor Page（学 SlotEditPage 样板，单值编辑）

/// 通用提示词编辑页：title + 大 TextEditor + 默认/清空快捷 + 原生 toolbar 取消/保存。
/// 用 NavigationLink push 调起（不是 sheet），跟 SlotEditPage 一致。
struct PromptEditorPage: View {
    let title: String
    let storageKey: String
    let defaultTemplate: String
    let hint: String

    @State private var edited: String = ""
    @State private var initial: String = ""
    @Environment(\.dismiss) private var dismiss

    private var isDirty: Bool { edited != initial }

    var body: some View {
        List {
            Section("内容") {
                TextEditor(text: $edited)
                    .font(.system(size: Theme.F.caption, design: .monospaced))
                    .frame(minHeight: 240)
                    .scrollContentBackground(.hidden)
            }
            .listRowBackground(Theme.mainBg)

            Section {
                Button("用默认模板") { edited = defaultTemplate }
                    .foregroundColor(Theme.branchIndicator)
                if !edited.isEmpty {
                    Button(role: .destructive) { edited = "" } label: {
                        Text("清空（用默认）")
                    }
                }
                Text(hint)
                    .font(.system(size: Theme.F.caption))
                    .foregroundColor(Theme.textMuted)
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
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
                    .foregroundColor(Theme.textMuted)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    UserDefaults.standard.set(edited, forKey: storageKey)
                    initial = edited
                    dismiss()
                }
                .foregroundColor(isDirty ? Theme.branchIndicator : Theme.textMuted)
                .disabled(!isDirty)
            }
        }
        .onAppear {
            let stored = UserDefaults.standard.string(forKey: storageKey) ?? ""
            edited = stored
            initial = stored
        }
    }
}
