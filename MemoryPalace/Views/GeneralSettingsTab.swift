import SwiftUI
import SwiftData

// MARK: - General Tab (macOS)

struct GeneralSettingsTab: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ProfileManager.self) private var profileManager: ProfileManager?

    @AppStorage("userName") private var userName = "你"
    @AppStorage("assistantName") private var assistantName = "助手"
    @State private var editingUserName = ""
    @State private var editingAssistantName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Profile
            VStack(alignment: .leading, spacing: 8) {
                Text("楼层")
                    .font(.system(size: Theme.SettingsFont.sectionHeader, weight: .semibold))
                    .foregroundColor(Theme.textSecondary)

                if let pm = profileManager {
                    ProfileSwitcher(profileManager: pm)
                }
            }

            Divider().opacity(0.15)

            // Names
            VStack(alignment: .leading, spacing: 14) {
                Text("气泡标签")
                    .font(.system(size: Theme.SettingsFont.sectionHeader, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)

                VStack(alignment: .leading, spacing: 10) {
                    SettingsTextField(label: "我的名字", placeholder: "你", text: $editingUserName)
                    SettingsTextField(label: "AI 的名字", placeholder: "助手", text: $editingAssistantName)
                }

                HStack {
                    Text("显示在每条消息气泡上方的名称标签")
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                    Spacer()
                    Button(action: {
                        let newUser = editingUserName.trimmingCharacters(in: .whitespacesAndNewlines)
                        let newAssistant = editingAssistantName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !newUser.isEmpty { userName = newUser }
                        if !newAssistant.isEmpty { assistantName = newAssistant }
                        dismiss()
                    }) {
                        Text("确认")
                            .font(.system(size: Theme.SettingsFont.secondary, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Theme.branchIndicator))
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().opacity(0.15)

            // 世界书绑定管理
            worldBookBindingSection

        }
        .onAppear {
            editingUserName = userName
            editingAssistantName = assistantName
        }
    }

    // MARK: - 世界书绑定管理

    private var worldBookBindingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("世界书绑定")
                .font(.system(size: Theme.SettingsFont.sectionHeader, weight: .semibold))
                .foregroundColor(Theme.textPrimary)

            let profileId = profileManager?.currentProfile.id ?? ""
            let linkedIds = profileManager?.currentProfile.linkedWorldBookIDs ?? []
            let wbDescriptor = FetchDescriptor<WorldBook>(predicate: #Predicate { $0.profileId == profileId })
            let floorBooks = (try? modelContext.fetch(wbDescriptor)) ?? []

            if floorBooks.isEmpty {
                Text("当前楼层没有绑定的世界书")
                    .font(.system(size: Theme.SettingsFont.body))
                    .foregroundColor(Theme.textMuted)
            } else {
                VStack(spacing: 4) {
                    ForEach(floorBooks, id: \.id) { book in
                        HStack(spacing: 8) {
                            Image(systemName: book.scopeConversationId != nil ? "bubble.left" : "book.closed.fill")
                                .font(.system(size: Theme.SettingsFont.secondary))
                                .foregroundColor(Theme.branchIndicator)
                            Text(book.name)
                                .font(.system(size: Theme.SettingsFont.body))
                                .foregroundColor(Theme.textPrimary)

                            Text(book.scopeConversationId != nil ? "对话" : "楼层")
                                .font(.system(size: Theme.SettingsFont.badge, weight: .medium))
                                .foregroundColor(Theme.branchIndicator)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Theme.branchIndicator.opacity(0.1)))

                            Text("\(book.entries.count) 条")
                                .font(.system(size: Theme.SettingsFont.secondary))
                                .foregroundColor(Theme.textMuted)

                            Spacer()

                            Button {
                                unbindWorldBook(book)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: Theme.SettingsFont.secondary, weight: .medium))
                                    .foregroundColor(Theme.textMuted)
                                    .frame(width: 20, height: 20)
                                    .background(Circle().fill(Theme.accent.opacity(0.2)))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.mainBg.opacity(0.6)))
                    }
                }
            }

            Text("在右栏「世界书」tab 里可以新建、导入、编辑世界书")
                .font(.system(size: Theme.SettingsFont.caption))
                .foregroundColor(Theme.textMuted.opacity(0.6))
        }
    }

    private func unbindWorldBook(_ book: WorldBook) {
        modelContext.delete(book)
        if var profile = profileManager?.currentProfile {
            profile.linkedWorldBookIDs.removeAll { $0 == book.id.uuidString }
            profileManager?.updateProfile(profile)
        }
        try? modelContext.save()
    }
}

// MARK: - iOS General Page

struct IOSGeneralPage: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ProfileManager.self) private var profileManager: ProfileManager?

    @AppStorage("userName") private var userName = "你"
    @AppStorage("assistantName") private var assistantName = "助手"
    @State private var editingUserName = ""
    @State private var editingAssistantName = ""

    var body: some View {
        List {
            Section("楼层") {
                if let pm = profileManager {
                    ProfileSwitcher(profileManager: pm)
                }
            }
            .listRowBackground(Theme.mainBg)
            .listRowSeparator(.hidden)

            Section {
                VStack(spacing: 8) {
                    SettingsTextField(label: "我的名字", placeholder: "你", text: $editingUserName)
                    SettingsTextField(label: "AI 的名字", placeholder: "助手", text: $editingAssistantName)
                }

                HStack {
                    Text("显示在每条消息气泡上方的名称标签")
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                    Spacer()
                    Button(action: {
                        let newUser = editingUserName.trimmingCharacters(in: .whitespacesAndNewlines)
                        let newAssistant = editingAssistantName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !newUser.isEmpty { userName = newUser }
                        if !newAssistant.isEmpty { assistantName = newAssistant }
                        dismiss()
                    }) {
                        Text("确认")
                            .font(.system(size: Theme.F.secondary, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Theme.branchIndicator))
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("气泡标签")
            }
            .listRowBackground(Theme.mainBg)
            .listRowSeparator(.hidden)

            Section("世界书") {
                IOSGeneralWorldBookBindingSection()
            }
            .listRowBackground(Theme.mainBg)
            .listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.sidebarBg)
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("通用")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            editingUserName = userName
            editingAssistantName = assistantName
        }
    }
}

private struct IOSGeneralWorldBookBindingSection: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ProfileManager.self) private var profileManager: ProfileManager?

    var body: some View {
        let profileId = profileManager?.currentProfile.id ?? ""
        let linkedIds = profileManager?.currentProfile.linkedWorldBookIDs ?? []
        let wbDescriptor = FetchDescriptor<WorldBook>(predicate: #Predicate { $0.profileId == profileId })
        let floorBooks = (try? modelContext.fetch(wbDescriptor)) ?? []

        if floorBooks.isEmpty {
            Text("当前楼层没有绑定的世界书")
                .font(.system(size: Theme.F.body))
                .foregroundColor(Theme.textMuted)
        } else {
            ForEach(floorBooks, id: \.id) { book in
                HStack(spacing: 8) {
                    Image(systemName: book.scopeConversationId != nil ? "bubble.left" : "book.closed.fill")
                        .font(.system(size: Theme.F.secondary))
                        .foregroundColor(Theme.branchIndicator)
                    Text(book.name)
                        .font(.system(size: Theme.F.body))
                        .foregroundColor(Theme.textPrimary)

                    Text(book.scopeConversationId != nil ? "对话" : "楼层")
                        .font(.system(size: Theme.F.badge, weight: .medium))
                        .foregroundColor(Theme.branchIndicator)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Theme.branchIndicator.opacity(0.1)))

                    Text("\(book.entries.count) 条")
                        .font(.system(size: Theme.F.secondary))
                        .foregroundColor(Theme.textMuted)

                    Spacer()

                    Button {
                        unbindWorldBook(book)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: Theme.F.secondary, weight: .medium))
                            .foregroundColor(Theme.textMuted)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Theme.accent.opacity(0.2)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        Text("在右栏「世界书」tab 里可以新建、导入、编辑世界书")
            .font(.system(size: Theme.F.caption))
            .foregroundColor(Theme.textMuted.opacity(0.6))
    }

    private func unbindWorldBook(_ book: WorldBook) {
        modelContext.delete(book)
        if var profile = profileManager?.currentProfile {
            profile.linkedWorldBookIDs.removeAll { $0 == book.id.uuidString }
            profileManager?.updateProfile(profile)
        }
        try? modelContext.save()
    }
}
