import SwiftUI
import SwiftData

// MARK: - Memory Page Content（共用核：设置-记忆 full / page2 compact）
//
// 按 cc-rp 六组分组（感知 / 提取 / 整理 / 注入 / 检索 / 基建）拼装 Section。
// 单一来源 — 改一处两边生效。

struct MemoryPageContent: View {
    enum Mode { case full, compact }
    let mode: Mode

    @Environment(\.modelContext) private var modelContext
    @Environment(ProfileManager.self) private var profileManager: ProfileManager?
    @Environment(ProviderManager.self) private var providerManager: ProviderManager?

    // 记忆系统全集 AppStorage（六组）
    @AppStorage("memoryExtractModelId") private var memoryExtractModelId = ""
    @AppStorage("customMemoryExtractionPrompt") private var customMemoryPrompt = ""
    @AppStorage("mem_master") private var memMaster = true
    @AppStorage("mem_decay_enabled") private var memDecayEnabled = true
    @AppStorage("mem_extract_firstperson") private var memFirstPerson = false
    @AppStorage("mem_extract_interval") private var memExtractInterval = 3
    @AppStorage("mem_supersede_soft") private var memSupersedeSoft = true
    @AppStorage("mem_inject_full") private var memInjectFull = true
    @AppStorage("mem_inject_keyword") private var memInjectKeyword = false
    @AppStorage("mem_inject_tag") private var memInjectTag = false
    @AppStorage("mem_inject_vector") private var memInjectVector = false
    @AppStorage("mem_inject_graph") private var memInjectGraph = false
    @AppStorage("mem_content_facts") private var memContentFacts = true
    @AppStorage("mem_content_profile") private var memContentProfile = false
    @AppStorage("mem_content_summary") private var memContentSummary = true
    @AppStorage("mem_content_convhistory") private var memContentConvHistory = true
    @AppStorage("mem_inject_catalog") private var memInjectCatalog = false
    @AppStorage("mem_content_filehistory") private var memContentFileHistory = false
    @AppStorage("mem_content_timeline") private var memContentTimeline = false
    @AppStorage("mem_content_heartvoice") private var memContentHeartvoice = false
    @AppStorage("heartvoice_show_in_chat") private var heartvoiceShowInChat = false
    @AppStorage("mem_infra_gateway") private var memInfraGateway = false
    @AppStorage("mem_inject_budget") private var memInjectBudget = 2000

    @State private var profileDream: UserProfileDream? = nil
    @State private var dreamStatus = ""
    @State private var latestDiary: DailyNote? = nil
    @State private var diaryStatus = ""
    @State private var hygieneStatus = ""
    @State private var hygieneConfirm = false
    @State private var hygieneResultMessage: String? = nil
    @State private var isHygieneRunning = false
    @State private var editingProfile: ProfileEditingContext? = nil
    @State private var memoryStats = MemoryStats()

    private struct MemoryStats {
        var total: Int = 0
        var hot: Int = 0
        var warm: Int = 0
        var cold: Int = 0
        var hotTokens: Int = 0
    }

    var body: some View {
        Group {
            switch mode {
            case .full:
                sectionPerception
                sectionExtraction
                sectionOrganize
                sectionInjection
                sectionRetrieval
                sectionInfra
            case .compact:
                sectionOrganizeCompact
            }
        }
        .sheet(item: $editingProfile) { ctx in
            FileEditorSheet(
                path: "profile.md",
                initialContent: ctx.text,
                initialModifiedAt: ctx.modifiedAt,
                currentModifiedAt: { profileModifiedAt() },
                reloadExternalContent: {
                    let pid = profileManager?.currentProfile.id ?? ""
                    let latest = ProfileFileStore.load(profileId: pid)?.text ?? ""
                    return ReloadedFileContent(content: latest, modifiedAt: profileModifiedAt())
                },
                onSave: { newContent, _ in saveEditedProfile(newContent) },
                onCancel: { editingProfile = nil }
            )
        }
        .alert("整理记忆", isPresented: $hygieneConfirm) {
            Button("取消", role: .cancel) {}
            Button("开始整理") { runManualHygiene() }
        } message: {
            Text("这会扫描全部记忆：\n① 触发一次做梦聚合，凝成新画像\n② 把已凝入画像的非钉住碎片标记为「已毕业」\n③ 把语义近似的碎片对合并（保新去旧）\n原始数据不删除，可在面板恢复。")
        }
        .alert("整理完成", isPresented: Binding(
            get: { hygieneResultMessage != nil },
            set: { if !$0 { hygieneResultMessage = nil } }
        )) {
            Button("好") {}
        } message: {
            Text(hygieneResultMessage ?? "")
        }
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .profileWillSwitch)) { _ in
            profileDream = nil
            memoryStats = MemoryStats()
        }
        .onReceive(NotificationCenter.default.publisher(for: .memoryDidChange)) { _ in
            refresh()
        }
    }

    // MARK: - Section ① 感知·记什么

    @ViewBuilder
    private var sectionPerception: some View {
        Section("感知 · 记什么") {
            Toggle(isOn: $memMaster) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("记忆系统总开关")
                        .font(.system(size: Theme.F.body, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                    Text("关 = 不注入、不提取、不强化；数据不动")
                        .font(.system(size: Theme.F.caption))
                        .foregroundColor(Theme.textMuted)
                }
            }
            .tint(Theme.branchIndicator)
            memSwitchRow("原子事实", "AUDN 提取的事实（现状）", $memContentFacts, true)
            memSwitchRow("心声", "AI 聊到触动处自己写一小篇本能独白", $memContentHeartvoice, true)
            if memContentHeartvoice {
                memSwitchRow("心声进聊天流", "开=实时显示；关=只默默落盘，翻日历偷看", $heartvoiceShowInChat, true)
            }
            memSwitchRow("文件 / 发图历史", "记得发过什么", $memContentFileHistory, false)
            unimplementedRow("Moment（事件感知）", "AI 主动写事件记录（未来）")
        }
        .listRowBackground(Theme.mainBg)
        .listRowSeparator(.hidden)
    }

    // MARK: - Section ② 提取·怎么记

    @ViewBuilder
    private var sectionExtraction: some View {
        Section("提取 · 怎么记") {
            HStack {
                Text("提取模型")
                    .font(.system(size: Theme.F.body))
                    .foregroundColor(Theme.textSecondary)
                Spacer()
                Text(memoryModelDisplayName)
                    .font(.system(size: Theme.F.body, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
            }
            Text("在 API 设置里点击模型旁 🌛 切换副模型；不选则用主 provider 的便宜款")
                .font(.system(size: Theme.F.caption))
                .foregroundColor(Theme.textMuted)

            NavigationLink {
                PromptEditorPage(
                    title: "提取提示词",
                    storageKey: "customMemoryExtractionPrompt",
                    defaultTemplate: MemoryExtractor.extractionPrompt,
                    hint: "可用占位符：{{SYSTEM_PROMPT}}、{{PROFILE}}、{{MEMORIES}}"
                )
            } label: {
                HStack {
                    Text("提取提示词")
                        .font(.system(size: Theme.F.body))
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    Text(customMemoryPrompt.isEmpty ? "默认" : "自定义")
                        .font(.system(size: Theme.F.caption))
                        .foregroundColor(Theme.textMuted)
                }
            }

            Stepper(value: $memExtractInterval, in: 1...10) {
                HStack {
                    Text("提取间隔")
                        .font(.system(size: Theme.F.body))
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    Text("每 \(memExtractInterval) 轮一次")
                        .font(.system(size: Theme.F.caption, design: .monospaced))
                        .foregroundColor(Theme.textMuted)
                }
            }

            memSwitchRow("第一人称提取", "AI 以「我」视角带情感地记；关=第三人称客观", $memFirstPerson, true)
            unimplementedRow("提取门槛", "记忆 > 50 条时收紧（未来）")
        }
        .listRowBackground(Theme.mainBg)
        .listRowSeparator(.hidden)
    }

    // MARK: - Section ③ 整理·怎么管（full）

    @ViewBuilder
    private var sectionOrganize: some View {
        Section("整理 · 怎么管") {
            memSwitchRow("热度衰减", "7 天不提就降温（paramecium 实测删了它、kiwi 留着）", $memDecayEnabled, true)
            memSwitchRow("用户画像 · 做梦聚合", "定期把记忆凝成画像（每天一次）", $memContentProfile, true)
            memSwitchRow("碎片毕业制", "做梦凝入画像后碎片标失效（cc-rp 命脉刀）", $memSupersedeSoft, true)
            organizeProfileRow
            organizeButtons
            organizeStatsRow
        }
        .listRowBackground(Theme.mainBg)
        .listRowSeparator(.hidden)
    }

    // MARK: - Section ③ 整理（compact，page2 用：只画像 + 按钮 + "更多设置")

    @ViewBuilder
    private var sectionOrganizeCompact: some View {
        Section {
            organizeProfileRow
            organizeButtons
            NavigationLink {
                List { fullSectionsList }
                    #if os(iOS)
                    .listStyle(.insetGrouped)
                    #else
                    .listStyle(.plain)
                    #endif
                    .scrollContentBackground(.hidden)
                    .background(Theme.sidebarBg)
                    .navigationTitle("记忆设置")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
            } label: {
                HStack {
                    Label("更多设置", systemImage: "slider.horizontal.3")
                        .font(.system(size: Theme.F.body))
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                }
            }
        } header: { Text("整理 · 怎么管") }
        .listRowBackground(Theme.mainBg)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var fullSectionsList: some View {
        sectionPerception
        sectionExtraction
        sectionOrganize
        sectionInjection
        sectionRetrieval
        sectionInfra
    }

    // 画像入口 row（compact 和 full 都用）
    @ViewBuilder
    private var organizeProfileRow: some View {
        if let d = profileDream {
            Button {
                editingProfile = ProfileEditingContext(text: d.text, modifiedAt: profileModifiedAt())
            } label: {
                HStack {
                    Label("\(d.text.count) 字 · \(d.updatedAt.formatted(.dateTime.month().day().hour().minute()))",
                          systemImage: "moon.stars")
                        .font(.system(size: Theme.F.body))
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: Theme.F.caption))
                        .foregroundColor(Theme.textMuted)
                }
            }
            .contextMenu {
                NavigationLink {
                    PromptEditorPage(
                        title: "画像生成提示词",
                        storageKey: "customDreamPrompt",
                        defaultTemplate: DreamConsolidator.dreamPrompt,
                        hint: "做梦时用这个提示词把零散事实凝成画像"
                    )
                } label: {
                    Label("编辑生成提示词", systemImage: "wand.and.stars")
                }
                Button(role: .destructive) { deleteProfile() } label: {
                    Label("删除画像", systemImage: "trash")
                }
            }
        } else {
            Text("还没有画像 — 聊一轮自动做梦，或点下面")
                .font(.system(size: Theme.F.caption))
                .foregroundColor(Theme.textMuted)
        }
    }

    @ViewBuilder
    private var organizeButtons: some View {
        HStack(spacing: 12) {
            Button {
                runManualDream()
            } label: {
                Text("重新做梦 🌙")
                    .font(.system(size: Theme.F.secondary, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.branchIndicator))
            }
            .buttonStyle(.plain)
            .disabled(isHygieneRunning)

            Button {
                hygieneConfirm = true
            } label: {
                Text("整理记忆 🧹")
                    .font(.system(size: Theme.F.secondary, weight: .medium))
                    .foregroundColor(Theme.branchIndicator)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().stroke(Theme.branchIndicator, lineWidth: 1.2))
            }
            .buttonStyle(.plain)
            .disabled(isHygieneRunning)
        }
        if !dreamStatus.isEmpty {
            Text(dreamStatus).font(.system(size: Theme.F.caption)).foregroundColor(Theme.textMuted)
        }
        if !hygieneStatus.isEmpty {
            Text(hygieneStatus).font(.system(size: Theme.F.caption)).foregroundColor(Theme.textMuted)
        }
    }

    @ViewBuilder
    private var organizeStatsRow: some View {
        HStack(spacing: 12) {
            statBadge("总计", count: memoryStats.total, color: Theme.textSecondary)
            statBadge("活跃", count: memoryStats.hot, color: Theme.branchIndicator)
            statBadge("休眠", count: memoryStats.warm, color: .orange)
            statBadge("冷藏", count: memoryStats.cold, color: Theme.textMuted)
        }
        Text("注入 \(memoryStats.hotTokens) / \(MemoryInjector.tokenBudget) token")
            .font(.system(size: Theme.F.caption))
            .foregroundColor(Theme.textMuted)
    }

    // MARK: - Section ④ 注入·塞什么进 prompt

    @ViewBuilder
    private var sectionInjection: some View {
        Section("注入 · 塞什么进 prompt") {
            memSwitchRow("画像注入", "把当前画像塞进 system prompt（跟做梦开关共用 key，未来拆分）", $memContentProfile, true)
            memSwitchRow("上下文摘要", "长对话压缩成累计记忆并注入", $memContentSummary, true)
            memSwitchRow("时间轴日记", "楼层日记：每天聊了什么凝成一篇", $memContentTimeline, true)
            memSwitchRow("目录式注入", "命中记忆只注一行目录省 token，细节靠 recall 取回", $memInjectCatalog, false)

            Stepper(value: $memInjectBudget, in: 500...20000, step: 500) {
                HStack {
                    Text("注入预算")
                        .font(.system(size: Theme.F.body))
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    Text("\(memInjectBudget) token")
                        .font(.system(size: Theme.F.caption, design: .monospaced))
                        .foregroundColor(Theme.textMuted)
                }
            }

            HStack(spacing: 10) {
                Text(latestDiary.map { "最近日记：\($0.date) · \($0.text.count) 字" } ?? "还没有日记")
                    .font(.system(size: Theme.F.caption))
                    .foregroundColor(Theme.textMuted)
                Spacer()
                Button("补写昨日 📅") { runManualDiary() }
                    .font(.system(size: Theme.F.secondary))
                    .foregroundColor(Theme.branchIndicator)
                    .buttonStyle(.plain)
            }
            if !diaryStatus.isEmpty {
                Text(diaryStatus).font(.system(size: Theme.F.caption)).foregroundColor(Theme.textMuted)
            }
        }
        .listRowBackground(Theme.mainBg)
        .listRowSeparator(.hidden)
    }

    // MARK: - Section ⑤ 检索·怎么挑记忆（可叠加）

    @ViewBuilder
    private var sectionRetrieval: some View {
        Section("检索 · 怎么挑记忆（可叠加）") {
            memSwitchRow("全量注入", "不挑、全塞（最蠢）", $memInjectFull, true)
            memSwitchRow("关键词命中", "对话命中关键词才注（复用世界书逻辑）", $memInjectKeyword, true)
            memSwitchRow("向量语义", "按意思相近检索（Apple 本地模型，首次自动下载）", $memInjectVector, true)
                .onChange(of: memInjectVector) { _, on in
                    if on { AppleMemoryEmbedder.shared.requestAssetsIfNeeded() }
                }
            memSwitchRow("关联扩展", "命中一条顺带它的关联记忆（图谱一跳）", $memInjectGraph, true)
            memSwitchRow("对话历史搜索（recall）", "AI 可调 recall 工具翻旧对话原话和记忆库", $memContentConvHistory, true)
            memSwitchRow("语境 / tag", "如亲密时注入亲密条（未来）", $memInjectTag, false)
            unimplementedRow("随机联想", "偶然想起旧记忆（未来）")

            if memInjectVector {
                HStack(spacing: 8) {
                    Text("向量模型")
                        .font(.system(size: Theme.F.caption))
                        .foregroundColor(Theme.textMuted)
                    if AppleMemoryEmbedder.shared.assetState == .downloading {
                        ProgressView().controlSize(.small)
                    }
                    Text(AppleMemoryEmbedder.shared.assetState.rawValue)
                        .font(.system(size: Theme.F.caption, weight: .medium))
                        .foregroundColor(AppleMemoryEmbedder.shared.assetState == .ready ? Theme.branchIndicator : Theme.textSecondary)
                    Spacer()
                }
            }
        }
        .listRowBackground(Theme.mainBg)
        .listRowSeparator(.hidden)
    }

    // MARK: - Section ⑥ 基建

    @ViewBuilder
    private var sectionInfra: some View {
        Section("基建") {
            memSwitchRow("记忆网关（缝 kiwi）", "重活下沉到 Mac（未来）", $memInfraGateway, false)
        }
        .listRowBackground(Theme.mainBg)
        .listRowSeparator(.hidden)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func memSwitchRow(_ title: String, _ sub: String, _ isOn: Binding<Bool>, _ enabled: Bool) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: Theme.F.body))
                    .foregroundColor(enabled ? Theme.textPrimary : Theme.textMuted)
                Text(enabled ? sub : "\(sub) · 未实现")
                    .font(.system(size: Theme.F.caption))
                    .foregroundColor(Theme.textMuted.opacity(enabled ? 1 : 0.55))
            }
        }
        .tint(Theme.branchIndicator)
        .disabled(!enabled)
    }

    @ViewBuilder
    private func unimplementedRow(_ title: String, _ sub: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: Theme.F.body))
                    .foregroundColor(Theme.textMuted)
                Text(sub)
                    .font(.system(size: Theme.F.caption))
                    .foregroundColor(Theme.textMuted.opacity(0.55))
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func statBadge(_ label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(label) \(count)")
                .font(.system(size: Theme.F.secondary))
                .foregroundColor(Theme.textSecondary)
        }
    }

    private var memoryModelDisplayName: String {
        guard let pm = providerManager else { return "—" }
        if !memoryExtractModelId.isEmpty,
           let m = pm.enabledProviders.flatMap(\.models).first(where: { $0.id == memoryExtractModelId }) {
            return m.name
        }
        return "自动"
    }

    private func profileModifiedAt() -> Date? {
        let pid = profileManager?.currentProfile.id ?? ""
        let url = FileLibraryStore.memoryRoot(profileId: pid).appendingPathComponent("profile.md")
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.modificationDate] as? Date
    }

    // MARK: - Actions

    private func refresh() {
        let profileId = profileManager?.currentProfile.id ?? ""
        let store = SwiftDataMemoryStore()
        let all = store.listAll(profileId: profileId, context: modelContext)
        let hot = all.filter { DecayEngine.tier($0) == .hot }
        let warm = all.filter { DecayEngine.tier($0) == .warm }
        let cold = all.filter { DecayEngine.tier($0) == .cold }
        memoryStats = MemoryStats(
            total: all.count, hot: hot.count, warm: warm.count, cold: cold.count,
            hotTokens: hot.reduce(0) { $0 + $1.tokenCount }
        )
        profileDream = ProfileFileStore.load(profileId: profileId)
        latestDiary = DailyFileStore.latest(profileId: profileId)
    }

    private func saveEditedProfile(_ newText: String) {
        let pid = profileManager?.currentProfile.id ?? ""
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = profileDream
        let saved = UserProfileDream(
            text: trimmed,
            sourceCount: existing?.sourceCount ?? 0,
            updatedAt: Date()
        )
        ProfileFileStore.save(saved, profileId: pid)
        profileDream = saved
        editingProfile = nil
    }

    private func deleteProfile() {
        let pid = profileManager?.currentProfile.id ?? ""
        let url = FileLibraryStore.memoryRoot(profileId: pid).appendingPathComponent("profile.md")
        try? FileManager.default.removeItem(at: url)
        profileDream = nil
    }

    private func runManualDream() {
        guard memContentProfile else { dreamStatus = "先打开「用户画像」开关"; return }
        guard let pm = providerManager, let model = DreamConsolidator.resolveModel(providerManager: pm) else {
            dreamStatus = "没有可用模型（先在 API 设置选模型）"; return
        }
        let profileId = profileManager?.currentProfile.id ?? ""
        let store = SwiftDataMemoryStore()
        let mems = store.listHotAndWarm(profileId: profileId, context: modelContext)
        guard !mems.isEmpty else { dreamStatus = "还没有记忆，先聊几轮"; return }
        let facts = mems.map { (content: $0.content, category: $0.category) }
        let consumedIds = DreamConsolidator.consumedIdsFromCandidates(mems)
        let ctx = modelContext
        dreamStatus = "做梦中…"
        Task {
            let result = try? await DreamConsolidator.dream(profileId: profileId, facts: facts, model: model, providerManager: pm)
            await MainActor.run {
                if let result {
                    let graduated = DreamConsolidator.graduateConsumedMemories(consumedIds: consumedIds, store: store, context: ctx)
                    let suffix = graduated > 0 ? " · 毕业 \(graduated)" : ""
                    dreamStatus = "✅ \(result.sourceCount) 条 → \(result.text.count) 字\(suffix)"
                    profileDream = result
                } else {
                    dreamStatus = "失败，看「设置→调试」日志"
                }
            }
        }
    }

    private func runManualHygiene() {
        guard memContentProfile else { hygieneStatus = "先打开「用户画像」开关"; return }
        guard let pm = providerManager, let model = DreamConsolidator.resolveModel(providerManager: pm) else {
            hygieneStatus = "没有可用模型（先在 API 设置选模型）"; return
        }
        let profileId = profileManager?.currentProfile.id ?? ""
        let ctx = modelContext
        isHygieneRunning = true
        hygieneStatus = "🌙 做梦中…"
        Task { @MainActor in
            do {
                let report = try await MemoryHygiene.sweep(profileId: profileId, model: model, providerManager: pm, context: ctx)
                hygieneStatus = ""
                hygieneResultMessage = "✨ 凝入画像 \(report.graduated) · 合并 \(report.merged) · 剩余 \(report.remaining)"
                refresh()
            } catch {
                hygieneStatus = ""
                hygieneResultMessage = "❌ \(error.localizedDescription)"
            }
            isHygieneRunning = false
        }
    }

    private func runManualDiary() {
        guard memContentTimeline else { diaryStatus = "先打开「时间轴摘要」开关"; return }
        guard let pm = providerManager, let model = DreamConsolidator.resolveModel(providerManager: pm) else {
            diaryStatus = "没有可用模型（先在 API 设置选模型）"; return
        }
        let profileId = profileManager?.currentProfile.id ?? ""
        guard let mat = TimelineConsolidator.pendingMaterials(profileId: profileId, context: modelContext, forceYesterday: true) else {
            diaryStatus = "昨天没有对话活动"; return
        }
        diaryStatus = "写日记中…"
        Task {
            let note = try? await TimelineConsolidator.consolidate(
                profileId: profileId, day: mat.day, summaries: mat.summaries, titles: mat.titles,
                userLines: mat.userLines, sampled: mat.sampled,
                model: model, providerManager: pm
            )
            await MainActor.run {
                if let note {
                    diaryStatus = "✅ \(note.date) → \(note.text.count) 字"
                    latestDiary = note
                } else {
                    diaryStatus = "失败，看「设置→调试」日志"
                }
            }
        }
    }
}
