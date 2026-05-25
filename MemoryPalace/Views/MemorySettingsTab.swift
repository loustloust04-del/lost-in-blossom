import SwiftUI
import SwiftData

// MARK: - macOS Memory Settings Tab

struct MemorySettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ProfileManager.self) private var profileManager: ProfileManager?
    @Environment(ProviderManager.self) private var providerManager: ProviderManager?

    @State private var memories: [Memory] = []
    @State private var newNoteText = ""
    @State private var editingNoteId: UUID? = nil
    @State private var editingNoteText = ""
    @AppStorage("memoryExplanationExpanded") private var memoryExplanationExpanded = true
    @AppStorage("memoryExtractModelId") private var memoryExtractModelId = ""
    @AppStorage("customMemoryExtractionPrompt") private var customMemoryPrompt = ""
    @State private var isEditingPrompt = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            let profileId = profileManager?.currentProfile.id ?? ""

            // 说明卡片
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        memoryExplanationExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: memoryExplanationExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: Theme.SettingsFont.caption))
                        Text("记忆系统说明")
                            .font(.system(size: Theme.SettingsFont.sectionHeader, weight: .medium))
                        Spacer()
                    }
                    .foregroundColor(Theme.textSecondary)
                }
                .buttonStyle(.plain)

                if memoryExplanationExpanded {
                    VStack(alignment: .leading, spacing: 6) {
                        memoryExplanationLine("每轮对话后，后台自动用小模型分析对话，提取值得记住的事实")
                        memoryExplanationLine("小模型自己判断：新建、更新、删除、或不操作")
                        memoryExplanationLine("🟢 活跃记忆会注入每次对话，让 AI 像朋友一样知道你的事")
                        memoryExplanationLine("🟠 7 天没提起的记忆进入休眠，再提起时会唤醒")
                        memoryExplanationLine("📌 手动钉住的记忆永远不会忘")
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accent.opacity(0.15)))
                }
            }

            Divider().opacity(0.15)

            // 提取模型（粟粟 2026-04：入口在 API 设置的 model 列表里点 🌛）
            memoryModelHintRow

            // 提取提示词
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("提取提示词")
                        .font(.system(size: Theme.SettingsFont.label))
                        .foregroundColor(Theme.textSecondary)
                    Spacer()
                    if customMemoryPrompt.isEmpty {
                        Text("使用默认")
                            .font(.system(size: Theme.SettingsFont.caption))
                            .foregroundColor(Theme.textMuted)
                    } else {
                        Button("恢复默认") {
                            customMemoryPrompt = ""
                        }
                        .font(.system(size: Theme.SettingsFont.caption))
                        .foregroundColor(.red.opacity(0.7))
                        .buttonStyle(.plain)
                    }
                    Button(isEditingPrompt ? "收起" : "编辑") {
                        isEditingPrompt.toggle()
                    }
                    .font(.system(size: Theme.SettingsFont.caption))
                    .foregroundColor(Theme.branchIndicator)
                    .buttonStyle(.plain)
                }

                if isEditingPrompt {
                    TextEditor(text: $customMemoryPrompt)
                        .font(.system(size: Theme.SettingsFont.caption, design: .monospaced))
                        .frame(height: 180)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.mainBg.opacity(0.8)))
                        .overlay(
                            Group {
                                if customMemoryPrompt.isEmpty {
                                    Text(MemoryExtractor.extractionPrompt.prefix(200) + "...")
                                        .font(.system(size: Theme.SettingsFont.caption, design: .monospaced))
                                        .foregroundColor(Theme.textMuted.opacity(0.4))
                                        .padding(10)
                                        .allowsHitTesting(false)
                                }
                            },
                            alignment: .topLeading
                        )
                    Text("留空使用默认提示词。可用占位符：{{MEMORIES}}（当前记忆列表）")
                        .font(.system(size: Theme.SettingsFont.caption))
                        .foregroundColor(Theme.textMuted.opacity(0.6))
                }
            }

            Divider().opacity(0.15)

            // 统计
            let hotCount = memories.filter { DecayEngine.tier($0) == .hot }.count
            let warmCount = memories.filter { DecayEngine.tier($0) == .warm }.count
            let coldCount = memories.filter { DecayEngine.tier($0) == .cold }.count
            let totalTokens = memories.filter { DecayEngine.tier($0) == .hot }.reduce(0) { $0 + $1.tokenCount }

            HStack(spacing: 16) {
                memoryStatBadge("总计", count: memories.count, color: Theme.textSecondary)
                memoryStatBadge("活跃", count: hotCount, color: Theme.branchIndicator)
                memoryStatBadge("休眠", count: warmCount, color: .orange)
                memoryStatBadge("冷藏", count: coldCount, color: Theme.textMuted)
                Spacer()
                Text("注入 \(totalTokens) / \(MemoryInjector.tokenBudget) token")
                    .font(.system(size: Theme.SettingsFont.secondary))
                    .foregroundColor(Theme.textMuted)
            }

            Divider().opacity(0.15)

            // 按温区分组显示
            if memories.isEmpty {
                Text("还没有记忆")
                    .font(.system(size: Theme.SettingsFont.body))
                    .foregroundColor(Theme.textMuted)
                    .padding(.vertical, 8)
            } else {
                let grouped = Dictionary(grouping: memories) { DecayEngine.tier($0) }
                let tiers: [(MemoryTier, String, Color)] = [
                    (.hot, "活跃", Theme.branchIndicator),
                    (.warm, "休眠", .orange),
                    (.cold, "冷藏", Theme.textMuted),
                ]
                ForEach(tiers, id: \.0) { tier, label, color in
                    if let items = grouped[tier], !items.isEmpty {
                        Text(label)
                            .font(.system(size: Theme.SettingsFont.sectionHeader, weight: .medium))
                            .foregroundColor(color)
                            .padding(.top, 4)

                        ForEach(items, id: \.id) { memory in
                            memoryRow(memory, tierColor: color, profileId: profileId)
                        }
                    }
                }
            }

            Divider().opacity(0.15)

            // 手动添加
            VStack(alignment: .leading, spacing: 8) {
                Text("手动添加记忆")
                    .font(.system(size: Theme.SettingsFont.sectionHeader, weight: .medium))
                    .foregroundColor(Theme.textSecondary)

                TextEditor(text: $newNoteText)
                    .font(.system(size: Theme.SettingsFont.body))
                    .frame(height: 50)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.mainBg))
                    .scrollContentBackground(.hidden)

                Button {
                    let text = newNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    let store = SwiftDataMemoryStore()
                    try? store.add(
                        content: text, category: "fact", keywords: [],
                        profileId: profileId, isUserExplicit: true, extractedBy: "manual",
                        sourceConversationId: nil, context: modelContext
                    )
                    newNoteText = ""
                    refreshMemories()
                } label: {
                    Text("添加")
                        .font(.system(size: Theme.SettingsFont.secondary, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Theme.branchIndicator))
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear { refreshMemories() }
        // 切楼层 race defense，见 docs/plan-profile-switch-atomic.md
        .onReceive(NotificationCenter.default.publisher(for: .profileWillSwitch)) { _ in
            memories = []
        }
    }

    // MARK: - Memory Model Hint (只读 — 切换入口在 API 设置 model list)

    @ViewBuilder
    private var memoryModelHintRow: some View {
        HStack(spacing: 8) {
            Text("提取模型")
                .font(.system(size: Theme.SettingsFont.label))
                .foregroundColor(Theme.textSecondary)

            Text(memoryModelDisplayName)
                .font(.system(size: Theme.SettingsFont.body, weight: .medium))
                .foregroundColor(Theme.textPrimary)

            Spacer()

            Text("在「API 设置」→ 点击模型旁 🌛 切换")
                .font(.system(size: Theme.SettingsFont.caption))
                .foregroundColor(Theme.textMuted)
        }
    }

    private var memoryModelDisplayName: String {
        guard let pm = providerManager else { return "—" }
        if !memoryExtractModelId.isEmpty, let m = pm.enabledProviders.flatMap(\.models).first(where: { $0.id == memoryExtractModelId }) {
            return m.name
        }
        return "自动（主 provider 的便宜款）"
    }

    // MARK: - Helpers

    private func memoryExplanationLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: Theme.SettingsFont.caption))
            .foregroundColor(Theme.textSecondary)
    }

    private func memoryStatBadge(_ label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(label) \(count)")
                .font(.system(size: Theme.SettingsFont.secondary))
                .foregroundColor(Theme.textSecondary)
        }
    }

    private func memoryRow(_ memory: Memory, tierColor: Color, profileId: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(spacing: 6) {
                Circle().fill(tierColor).frame(width: 5, height: 5)

                let categoryLabels: [String: String] = [
                    "preference": "偏好", "fact": "事实", "relationship": "关系",
                    "goal": "目标", "context": "情境",
                ]
                Text(categoryLabels[memory.category] ?? memory.category)
                    .font(.system(size: Theme.SettingsFont.badge, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(tierColor.opacity(0.7)))

                if memory.isUserExplicit {
                    Image(systemName: "pin.fill")
                        .font(.system(size: Theme.SettingsFont.badge))
                        .foregroundColor(Theme.branchIndicator)
                }

                Spacer()

                Text(memory.updatedAt.formatted(.dateTime.month().day().hour().minute()))
                    .font(.system(size: Theme.SettingsFont.caption))
                    .foregroundColor(Theme.textMuted.opacity(0.6))
            }

            // Content
            if editingNoteId == memory.id {
                TextEditor(text: $editingNoteText)
                    .font(.system(size: Theme.SettingsFont.body))
                    .frame(height: 50)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.mainBg))
                    .scrollContentBackground(.hidden)

                HStack(spacing: 8) {
                    Button("取消") { editingNoteId = nil }
                        .font(.caption).foregroundColor(Theme.textMuted).buttonStyle(.plain)
                    Button("保存") {
                        let store = SwiftDataMemoryStore()
                        try? store.update(id: memory.id, content: editingNoteText, keywords: memory.keywords, context: modelContext)
                        editingNoteId = nil
                        refreshMemories()
                    }
                    .font(.caption).foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.branchIndicator))
                    .buttonStyle(.plain)
                }
            } else {
                Text(memory.content)
                    .font(.system(size: Theme.SettingsFont.body))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(3)
            }

            // Actions
            if editingNoteId != memory.id {
                HStack(spacing: 12) {
                    Button(memory.isUserExplicit ? "取消钉住" : "钉住") {
                        memory.isUserExplicit.toggle()
                        if memory.isUserExplicit { memory.decayWeight = 1.0 }
                        try? modelContext.save()
                        refreshMemories()
                    }
                    .font(.system(size: Theme.SettingsFont.secondary)).foregroundColor(Theme.textMuted).buttonStyle(.plain)

                    Button("编辑") {
                        editingNoteText = memory.content
                        editingNoteId = memory.id
                    }
                    .font(.system(size: Theme.SettingsFont.secondary)).foregroundColor(Theme.textMuted).buttonStyle(.plain)

                    Button("删除") {
                        modelContext.delete(memory)
                        try? modelContext.save()
                        refreshMemories()
                    }
                    .font(.system(size: Theme.SettingsFont.secondary)).foregroundColor(Theme.danger).buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.assistantBubble))
    }

    private func refreshMemories() {
        let profileId = profileManager?.currentProfile.id ?? ""
        let store = SwiftDataMemoryStore()
        memories = store.listAll(profileId: profileId, context: modelContext)
    }
}

// MARK: - iOS Memory Page

#if os(iOS)
struct IOSMemoryPage: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ProfileManager.self) private var profileManager: ProfileManager?
    @Environment(ProviderManager.self) private var providerManager: ProviderManager?

    @State private var memories: [Memory] = []
    @State private var newNoteText = ""
    @State private var editingNoteId: UUID? = nil
    @State private var editingNoteText = ""
    @AppStorage("memoryExplanationExpanded") private var memoryExplanationExpanded = true
    @AppStorage("memoryExtractModelId") private var memoryExtractModelId = ""
    @AppStorage("customMemoryExtractionPrompt") private var customMemoryPrompt = ""
    @State private var isEditingPrompt = false

    var body: some View {
        let profileId = profileManager?.currentProfile.id ?? ""
        let hotMems = memories.filter { DecayEngine.tier($0) == .hot }
        let warmMems = memories.filter { DecayEngine.tier($0) == .warm }
        let coldMems = memories.filter { DecayEngine.tier($0) == .cold }
        let totalTokens = hotMems.reduce(0) { $0 + $1.tokenCount }

        List {
            // 说明
            Section {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { memoryExplanationExpanded.toggle() }
                } label: {
                    HStack {
                        Text("记忆系统说明")
                            .font(.system(size: Theme.F.body))
                            .foregroundColor(Theme.textSecondary)
                        Spacer()
                        Image(systemName: memoryExplanationExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: Theme.F.caption))
                            .foregroundColor(Theme.textMuted)
                    }
                }
                .buttonStyle(.plain)

                if memoryExplanationExpanded {
                    VStack(alignment: .leading, spacing: 6) {
                        memoryExplanationLine("每轮对话后，后台自动用小模型分析对话，提取值得记住的事实")
                        memoryExplanationLine("🟢 活跃记忆会注入每次对话")
                        memoryExplanationLine("🟠 7 天没提起进入休眠")
                        memoryExplanationLine("📌 手动钉住永远不会忘")
                    }
                }
            }
            .listRowBackground(Theme.mainBg)
            .listRowSeparator(.hidden)

            // 提取模型（只读提示；切换入口在 API 设置 model list 的 🌛）
            Section("配置") {
                HStack {
                    Text("提取模型")
                        .font(.system(size: Theme.F.label))
                        .foregroundColor(Theme.textSecondary)
                    Spacer()
                    Text(iosMemoryModelDisplayName)
                        .font(.system(size: Theme.F.body, weight: .medium))
                        .foregroundColor(Theme.textPrimary)
                }
                Text("在 API 设置里点击模型旁 🌛 可切换副模型。不选就自动用主 provider 的便宜款。")
                    .font(.system(size: Theme.F.caption))
                    .foregroundColor(Theme.textMuted)

                HStack(spacing: 12) {
                    memoryStatBadge("总计", count: memories.count, color: Theme.textSecondary)
                    memoryStatBadge("活跃", count: hotMems.count, color: Theme.branchIndicator)
                    memoryStatBadge("休眠", count: warmMems.count, color: .orange)
                    memoryStatBadge("冷藏", count: coldMems.count, color: Theme.textMuted)
                }
                Text("注入 \(totalTokens) / \(MemoryInjector.tokenBudget) token")
                    .font(.system(size: Theme.F.caption))
                    .foregroundColor(Theme.textMuted)

                // 提取提示词
                Button {
                    isEditingPrompt.toggle()
                } label: {
                    HStack {
                        Text("提取提示词")
                            .font(.system(size: Theme.F.body))
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        Text(customMemoryPrompt.isEmpty ? "默认" : "自定义")
                            .font(.system(size: Theme.F.caption))
                            .foregroundColor(Theme.textMuted)
                        Image(systemName: "chevron.right")
                            .font(.system(size: Theme.F.caption))
                            .foregroundColor(Theme.textMuted.opacity(0.4))
                    }
                }
                .buttonStyle(.plain)
            }
            .listRowBackground(Theme.mainBg)
            .listRowSeparator(.hidden)

            if isEditingPrompt {
                Section("提取提示词") {
                    TextEditor(text: $customMemoryPrompt)
                        .font(.system(size: Theme.F.caption, design: .monospaced))
                        .frame(minHeight: 200)

                    if !customMemoryPrompt.isEmpty {
                        Button("恢复默认") {
                            customMemoryPrompt = ""
                        }
                        .foregroundColor(.red.opacity(0.7))
                        .font(.system(size: Theme.F.secondary))
                    }

                    Text("留空使用默认提示词。可用占位符：{{MEMORIES}}")
                        .font(.system(size: Theme.F.caption))
                        .foregroundColor(Theme.textMuted.opacity(0.6))
                }
                .listRowBackground(Theme.mainBg)
            }

            // 三温区
            if !memories.isEmpty {
                if !hotMems.isEmpty {
                    Section("活跃") {
                        ForEach(hotMems, id: \.id) { memory in
                            memoryRow(memory, tierColor: Theme.branchIndicator, profileId: profileId)
                        }
                    }
                    .listRowBackground(Theme.mainBg)
                    .listRowSeparator(.hidden)
                }
                if !warmMems.isEmpty {
                    Section("休眠") {
                        ForEach(warmMems, id: \.id) { memory in
                            memoryRow(memory, tierColor: .orange, profileId: profileId)
                        }
                    }
                    .listRowBackground(Theme.mainBg)
                    .listRowSeparator(.hidden)
                }
                if !coldMems.isEmpty {
                    Section("冷藏") {
                        ForEach(coldMems, id: \.id) { memory in
                            memoryRow(memory, tierColor: Theme.textMuted, profileId: profileId)
                        }
                    }
                    .listRowBackground(Theme.mainBg)
                    .listRowSeparator(.hidden)
                }
            } else {
                Section {
                    Text("还没有记忆")
                        .font(.system(size: Theme.F.body))
                        .foregroundColor(Theme.textMuted)
                }
                .listRowBackground(Theme.mainBg)
                .listRowSeparator(.hidden)
            }

            // 手动添加
            Section("手动添加") {
                TextEditor(text: $newNoteText)
                    .font(.system(size: Theme.F.body))
                    .frame(height: 60)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.mainBg))
                    .scrollContentBackground(.hidden)

                Button {
                    let text = newNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    let store = SwiftDataMemoryStore()
                    try? store.add(
                        content: text, category: "fact", keywords: [],
                        profileId: profileId, isUserExplicit: true, extractedBy: "manual",
                        sourceConversationId: nil, context: modelContext
                    )
                    newNoteText = ""
                    refreshMemories()
                } label: {
                    Text("添加")
                        .font(.system(size: Theme.F.secondary, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Theme.branchIndicator))
                }
                .buttonStyle(.plain)
            }
            .listRowBackground(Theme.mainBg)
            .listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.sidebarBg)
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("记忆")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refreshMemories() }
        // 切楼层 race defense，见 docs/plan-profile-switch-atomic.md
        .onReceive(NotificationCenter.default.publisher(for: .profileWillSwitch)) { _ in
            memories = []
        }
    }

    // MARK: - Helpers

    private func memoryExplanationLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: Theme.F.caption))
            .foregroundColor(Theme.textSecondary)
    }

    private var iosMemoryModelDisplayName: String {
        guard let pm = providerManager else { return "—" }
        if !memoryExtractModelId.isEmpty,
           let m = pm.enabledProviders.flatMap(\.models).first(where: { $0.id == memoryExtractModelId }) {
            return m.name
        }
        return "自动"
    }

    private func memoryStatBadge(_ label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(label) \(count)")
                .font(.system(size: Theme.F.secondary))
                .foregroundColor(Theme.textSecondary)
        }
    }

    private func memoryRow(_ memory: Memory, tierColor: Color, profileId: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(spacing: 6) {
                Circle().fill(tierColor).frame(width: 5, height: 5)

                let categoryLabels: [String: String] = [
                    "preference": "偏好", "fact": "事实", "relationship": "关系",
                    "goal": "目标", "context": "情境",
                ]
                Text(categoryLabels[memory.category] ?? memory.category)
                    .font(.system(size: Theme.F.badge, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(tierColor.opacity(0.7)))

                if memory.isUserExplicit {
                    Image(systemName: "pin.fill")
                        .font(.system(size: Theme.F.badge))
                        .foregroundColor(Theme.branchIndicator)
                }

                Spacer()

                Text(memory.updatedAt.formatted(.dateTime.month().day().hour().minute()))
                    .font(.system(size: Theme.F.caption))
                    .foregroundColor(Theme.textMuted.opacity(0.6))
            }

            // Content
            if editingNoteId == memory.id {
                TextEditor(text: $editingNoteText)
                    .font(.system(size: Theme.F.body))
                    .frame(height: 50)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.mainBg))
                    .scrollContentBackground(.hidden)

                HStack(spacing: 8) {
                    Button("取消") { editingNoteId = nil }
                        .font(.caption).foregroundColor(Theme.textMuted).buttonStyle(.plain)
                    Button("保存") {
                        let store = SwiftDataMemoryStore()
                        try? store.update(id: memory.id, content: editingNoteText, keywords: memory.keywords, context: modelContext)
                        editingNoteId = nil
                        refreshMemories()
                    }
                    .font(.caption).foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.branchIndicator))
                    .buttonStyle(.plain)
                }
            } else {
                Text(memory.content)
                    .font(.system(size: Theme.F.body))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(3)
            }

            // Actions
            if editingNoteId != memory.id {
                HStack(spacing: 12) {
                    Button(memory.isUserExplicit ? "取消钉住" : "钉住") {
                        memory.isUserExplicit.toggle()
                        if memory.isUserExplicit { memory.decayWeight = 1.0 }
                        try? modelContext.save()
                        refreshMemories()
                    }
                    .font(.system(size: Theme.F.secondary)).foregroundColor(Theme.textMuted).buttonStyle(.plain)

                    Button("编辑") {
                        editingNoteText = memory.content
                        editingNoteId = memory.id
                    }
                    .font(.system(size: Theme.F.secondary)).foregroundColor(Theme.textMuted).buttonStyle(.plain)

                    Button("删除") {
                        modelContext.delete(memory)
                        try? modelContext.save()
                        refreshMemories()
                    }
                    .font(.system(size: Theme.F.secondary)).foregroundColor(Theme.danger).buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.assistantBubble))
    }

    private func refreshMemories() {
        let profileId = profileManager?.currentProfile.id ?? ""
        let store = SwiftDataMemoryStore()
        memories = store.listAll(profileId: profileId, context: modelContext)
    }
}
#endif
