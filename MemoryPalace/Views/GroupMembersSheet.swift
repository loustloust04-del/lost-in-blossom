import SwiftUI
import SwiftData

/// 群成员页：从聊天页右上角 ⋯ 菜单进入。查看成员（颜色/名字/模型），
/// 可直接编辑群名片（intro）和话痨度——建群之后终于能调人了。
struct GroupMembersSheet: View {
    let conversation: Conversation

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ProviderManager.self) private var providerManager: ProviderManager?

    @State private var members: [GroupParticipant] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach($members) { $member in
                    Section {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color(hex: member.colorHex) ?? .gray)
                                .frame(width: 14, height: 14)
                            Text(member.name)
                                .font(.headline)
                            Spacer()
                            Text(modelName(member.model))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        TextField("一句话简介（群名片，给其他成员看的）", text: $member.intro)
                            .font(.callout)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("话痨度")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(member.talkativeness * 100))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $member.talkativeness, in: 0...1, step: 0.05)
                        }
                    }
                }
            }
            .navigationTitle("群成员（\(members.count)）")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
            .onAppear { members = conversation.participants }
        }
    }

    private func modelName(_ id: String) -> String {
        providerManager?.model(byId: id)?.name ?? id
    }

    private func save() {
        conversation.participants = members
        try? modelContext.save()
        dismiss()
    }
}
