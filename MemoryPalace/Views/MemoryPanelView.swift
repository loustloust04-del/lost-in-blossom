import SwiftUI
import SwiftData

// MARK: - Right Panel (Tool-based Container)

struct RightPanelView: View {
    @Binding var selectedToolId: String
    var viewModel: ConversationViewModel
    var stickerVM: StickerViewModel

    @Environment(ProfileManager.self) private var profileManager: ProfileManager?
    @State private var bounceTrigger: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            ToolBarView(selectedToolId: $selectedToolId)
                .background(Theme.sidebarBg)
                .zIndex(selectedToolId == "calendar" ? 0 : 1)

            panelContent
                .phaseAnimator(
                    [false, true],
                    trigger: bounceTrigger
                ) { content, phase in
                    content
                        .scaleEffect(phase ? 0.995 : 1.0, anchor: .top)
                        .offset(y: phase ? 2 : 0)
                } animation: { phase in
                    phase
                        ? .spring(duration: 0.35, bounce: 0.2)   // 弹回：柔和微弹
                        : .easeOut(duration: 0.08)               // 下压：快速平滑
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.sidebarBg)
        .onChange(of: selectedToolId) { _, _ in
            bounceTrigger += 1
        }
    }

    @ViewBuilder
    private var panelContent: some View {
        switch selectedToolId {
        case "calendar":
            CalendarPanelView(viewModel: viewModel, profileId: profileManager?.currentProfile.id ?? "")
        case "memory":
            // PR-3: 本地记忆 / 网关记忆 双轨容器（MemoryPanelView 本体未改）
            MemoryDualTrackView(viewModel: viewModel)
        case "worldBook":
            WorldBookPanelView()
        case "cardLibrary":
            CardLibraryPanelView()
        case "sticker":
            StickerLibraryView(viewModel: viewModel, stickerVM: stickerVM)
        case "prompt":
            PersonaSettingsTab(useSheetNavigation: true)
        case "ccTerminal":
            CCTerminalPanelView(viewModel: viewModel)
        case "fileLibrary":
            FileLibraryPanelView()
        default:
            Text("未知工具")
                .foregroundColor(Theme.textMuted)
        }
    }
}

struct RightPanelTopBar: View {
    @Binding var selectedToolId: String
    var onImport: () -> Void
    var onSettings: () -> Void

    var body: some View {
        ToolBarView(selectedToolId: $selectedToolId)
            .background(Theme.sidebarBg)
    }
}


// MARK: - Memory Panel（page2 主体）
//
// 重构方案 B：主体 List + MemoryPageContent(.compact) 共用核 + 三温区 Section。
// 删旧的 ScrollView+LazyVStack+自画 sectionHeader+memoryHeader+addMemoryInput。
// 长按多选复活：EditMode + List(selection:) + bottom toolbar。

struct MemoryPanelView: View {
    var viewModel: ConversationViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(ProfileManager.self) private var profileManager: ProfileManager?
    @Environment(RightPanelNavigator.self) private var navigator: RightPanelNavigator?

    @State private var memories: [Memory] = []
<<<<<<< HEAD
    @State private var showAddInput = false
    @State private var newMemoryText = ""
    @State private var newMemoryCategory = "fact"
    @State private var highlightedId: String? = nil
=======
    @State private var showGraph = false
    @State private var highlightedId: String? = nil
    @State private var selection: Set<UUID> = []
    @State private var showAddSheet = false
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    #endif
>>>>>>> 1420789 (feat(memory): 第三波 — MemoryPanelView 改 List+Section+EditMode 多选)

    private let store = SwiftDataMemoryStore()

    var body: some View {
<<<<<<< HEAD
        VStack(spacing: 0) {
            // Stats header
            memoryHeader
                .padding(.horizontal, isIOSStyle ? 16 : 12)
                .padding(.top, isIOSStyle ? 4 : 8)
                .padding(.bottom, isIOSStyle ? 12 : 8)

            // Memory list
            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    let grouped = groupedMemories
                    if !grouped.hot.isEmpty {
                        sectionHeader("活跃", count: grouped.hot.count, color: Color(hex: 0xD4A574))
                        ForEach(grouped.hot, id: \.id) { mem in
                            memoryRowWithHighlight(mem)
                        }
                    }
                    if !grouped.warm.isEmpty {
                        sectionHeader("休眠", count: grouped.warm.count, color: Theme.branchIndicator)
                            .padding(.top, grouped.hot.isEmpty ? 0 : 8)
                        ForEach(grouped.warm, id: \.id) { mem in
                            memoryRowWithHighlight(mem)
                        }
                    }
                    if !grouped.cold.isEmpty {
                        sectionHeader("将忘", count: grouped.cold.count, color: Color(red: 0.6, green: 0.65, blue: 0.7))
                            .padding(.top, (grouped.hot.isEmpty && grouped.warm.isEmpty) ? 0 : 8)
                        ForEach(grouped.cold, id: \.id) { mem in
                            memoryRowWithHighlight(mem)
                        }
                    }

                    if memories.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "brain")
                                .font(.system(size: 24))
                                .foregroundColor(Theme.textMuted.opacity(0.4))
                            Text("还没有记忆")
                                .font(.system(size: Theme.F.body))
                                .foregroundColor(Theme.textMuted)
                            Text("和{{char}}聊天时会自动记住重要的事".expandingMacros(profile: profileManager?.currentProfile))
                                .font(.system(size: Theme.F.caption))
                                .foregroundColor(Theme.textMuted.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
=======
        NavigationStack {
            List(selection: $selection) {
                MemoryPageContent(mode: .compact)

                if showGraph {
                    Section {
                        MemoryGraphView(memories: memories)
                            .frame(minHeight: 320)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
>>>>>>> 1420789 (feat(memory): 第三波 — MemoryPanelView 改 List+Section+EditMode 多选)
                    }
                } else {
                    listSections
                }
            }
<<<<<<< HEAD
            .onAppear { consumeTarget(navigator?.pendingTarget, proxy: proxy) }
            .onChange(of: navigator?.pendingTarget) { _, target in
                consumeTarget(target, proxy: proxy)
            }
            } // end ScrollViewReader

            Spacer(minLength: 0)

            // Add memory input
            if showAddInput {
                addMemoryInput
            }

            // Bottom: add button + token bar
            VStack(spacing: 6) {
                if !showAddInput {
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showAddInput = true } }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: isIOSStyle ? 12 : 11))
                            Text("添加记忆")
                                .font(.system(size: Theme.F.secondary))
                        }
                        .foregroundColor(Theme.branchIndicator)
                    }
                    .buttonStyle(.plain)
=======
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.plain)
            #endif
            .scrollContentBackground(.hidden)
            .background(Theme.sidebarBg)
            #if os(iOS)
            .environment(\.editMode, $editMode)
            #endif
            .toolbar { toolbarItems }
            .sheet(isPresented: $showAddSheet) {
                AddMemorySheet(profileId: profileManager?.currentProfile.id ?? "") {
                    refreshMemories()
>>>>>>> 1420789 (feat(memory): 第三波 — MemoryPanelView 改 List+Section+EditMode 多选)
                }
            }
<<<<<<< HEAD
            .padding(.horizontal, isIOSStyle ? 16 : 12)
            .padding(.top, isIOSStyle ? 10 : 8)
            .padding(.bottom, isIOSStyle ? 14 : 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { refreshMemories() }
        // 切楼层前清空 memories，避免 @State 里持有旧 store 的 Memory 实例让 body
        // 在 container reset 后访问失效实例。Plan: docs/plan-profile-switch-atomic.md
        .onReceive(NotificationCenter.default.publisher(for: .profileWillSwitch)) { _ in
            memories = []
=======
            .onAppear { refreshMemories() }
            .onReceive(NotificationCenter.default.publisher(for: .profileWillSwitch)) { _ in
                memories = []
                selection = []
                #if os(iOS)
                editMode = .inactive
                #endif
            }
            .onReceive(NotificationCenter.default.publisher(for: .memoryDidChange)) { _ in
                refreshMemories()
            }
>>>>>>> 1420789 (feat(memory): 第三波 — MemoryPanelView 改 List+Section+EditMode 多选)
        }
    }

    // MARK: - 三温区 Sections

<<<<<<< HEAD
    private var memoryHeader: some View {
        HStack(spacing: 8) {
            let grouped = groupedMemories
            HStack(spacing: 4) {
                Circle().fill(Color(hex: 0xD4A574)).frame(width: 6, height: 6)
                Text("\(grouped.hot.count)")
                    .font(.system(size: Theme.F.secondary, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
            }
            HStack(spacing: 4) {
                Circle().fill(Theme.branchIndicator).frame(width: 6, height: 6)
                Text("\(grouped.warm.count)")
                    .font(.system(size: Theme.F.secondary, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
            }
            HStack(spacing: 4) {
                Circle().fill(Color(red: 0.6, green: 0.65, blue: 0.7)).frame(width: 6, height: 6)
                Text("\(grouped.cold.count)")
                    .font(.system(size: Theme.F.secondary, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
            Text("\(memories.count) 条")
                .font(.system(size: Theme.F.secondary))
=======
    @ViewBuilder
    private var listSections: some View {
        let grouped = groupedMemories
        if memories.isEmpty {
            Section {
                emptyState
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        if !grouped.hot.isEmpty {
            Section("活跃 · \(grouped.hot.count)") {
                ForEach(grouped.hot, id: \.id) { mem in
                    memoryRow(mem).tag(mem.id)
                }
            }
            .listRowBackground(Theme.mainBg)
        }
        if !grouped.warm.isEmpty {
            Section("休眠 · \(grouped.warm.count)") {
                ForEach(grouped.warm, id: \.id) { mem in
                    memoryRow(mem).tag(mem.id)
                }
            }
            .listRowBackground(Theme.mainBg)
        }
        if !grouped.cold.isEmpty {
            Section("将忘 · \(grouped.cold.count)") {
                ForEach(grouped.cold, id: \.id) { mem in
                    memoryRow(mem).tag(mem.id)
                }
            }
            .listRowBackground(Theme.mainBg)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "brain")
                .font(.system(size: 24))
                .foregroundColor(Theme.textMuted.opacity(0.4))
            Text("还没有记忆")
                .font(.system(size: Theme.F.body))
>>>>>>> 1420789 (feat(memory): 第三波 — MemoryPanelView 改 List+Section+EditMode 多选)
                .foregroundColor(Theme.textMuted)
            Text("和{{char}}聊天时会自动记住重要的事".expandingMacros(profile: profileManager?.currentProfile))
                .font(.system(size: Theme.F.caption))
                .foregroundColor(Theme.textMuted.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

<<<<<<< HEAD
    // MARK: - Navigation Target Consumer

    private func consumeTarget(_ target: RightPanelNavigator.Target?, proxy: ScrollViewProxy) {
        guard let t = target, t.tool == "memory" else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(t.id, anchor: .center)
            }
        }
        highlightedId = t.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if highlightedId == t.id { highlightedId = nil }
        }
        navigator?.pendingTarget = nil
    }

    // MARK: - Memory Row With Highlight

=======
>>>>>>> 1420789 (feat(memory): 第三波 — MemoryPanelView 改 List+Section+EditMode 多选)
    @ViewBuilder
    private func memoryRow(_ mem: Memory) -> some View {
        let idStr = mem.id.uuidString
        MemoryCardView(
            memory: mem,
            effectiveWeight: effectiveWeight(mem),
            onPin: { togglePin(mem) },
            onDelete: { deleteMemory(mem) },
            onRevive: mem.supersededAt != nil ? { reviveMemory(mem) } : nil,
            onJumpToSource: mem.sourceConversationId != nil ? { jumpToSource(mem) } : nil
        )
        .id(idStr)
        .listRowBackground(
            highlightedId == idStr
                ? Theme.branchIndicator.opacity(0.35)
                : Color.clear
        )
        .animation(.easeInOut(duration: 0.35), value: highlightedId)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("", selection: $showGraph) {
                Text("列表").tag(false)
                Text("图谱 🕸").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        ToolbarItemGroup(placement: .primaryAction) {
            #if os(iOS)
            EditButton()
            #endif
            Button {
                showAddSheet = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(Theme.branchIndicator)
            }
        }
        #if os(iOS)
        if editMode == .active {
            ToolbarItemGroup(placement: .bottomBar) {
                Button { reviveSelected() } label: {
                    Label("复活", systemImage: "arrow.uturn.backward")
                }
                .disabled(!hasSelectedSuperseded)
                Button { pinSelected() } label: {
                    Label("钉住", systemImage: "pin")
                }
                .disabled(selection.isEmpty)
                Spacer()
                Text("\(selection.count) 已选")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(role: .destructive) { deleteSelected() } label: {
                    Label("删除", systemImage: "trash")
                }
                .disabled(selection.isEmpty)
            }
        }
        #endif
    }

    private var hasSelectedSuperseded: Bool {
        selection.contains { id in
            memories.first(where: { $0.id == id })?.supersededAt != nil
        }
    }

    // MARK: - Multi-select Actions

    private func resetSelection() {
        selection = []
        #if os(iOS)
        editMode = .inactive
        #endif
    }

    private func reviveSelected() {
        for id in selection {
            if let m = memories.first(where: { $0.id == id }), m.supersededAt != nil {
                m.supersededAt = nil
                m.updatedAt = Date()
            }
        }
        try? modelContext.save()
        resetSelection()
        refreshMemories()
    }

    private func pinSelected() {
        for id in selection {
            if let m = memories.first(where: { $0.id == id }) {
                m.isUserExplicit = true
                m.decayWeight = 1.0
                m.updatedAt = Date()
            }
        }
        try? modelContext.save()
        resetSelection()
        refreshMemories()
    }

    private func deleteSelected() {
        for id in selection {
            if let m = memories.first(where: { $0.id == id }) {
                modelContext.delete(m)
            }
        }
        try? modelContext.save()
        resetSelection()
        refreshMemories()
    }

<<<<<<< HEAD
    private func effectiveWeight(_ memory: Memory) -> Double {
        DecayEngine.effectiveWeight(memory)
    }

    private func refreshMemories() {
        let profileId = profileManager?.currentProfile.id ?? ""
        memories = (try? store.listAll(profileId: profileId, context: modelContext)) ?? []
    }

    private func togglePin(_ memory: Memory) {
        store.togglePin(memory, touchUpdatedAt: true, context: modelContext)
=======
    // MARK: - Single Memory Actions（保留：MemoryCardView 内部按钮回调）

    private func togglePin(_ memory: Memory) {
        memory.isUserExplicit.toggle()
        if memory.isUserExplicit { memory.decayWeight = 1.0 }
        memory.updatedAt = Date()
        try? modelContext.save()
>>>>>>> 1420789 (feat(memory): 第三波 — MemoryPanelView 改 List+Section+EditMode 多选)
        refreshMemories()
    }

    private func deleteMemory(_ memory: Memory) {
        store.delete(memory, context: modelContext)
        refreshMemories()
    }

    private func reviveMemory(_ memory: Memory) {
        store.revive(memory, context: modelContext)
        refreshMemories()
    }

<<<<<<< HEAD
    /// 出处跳转（SC-B2 v1）：跳到源对话，不定位消息（消息级定位等 B23 修好一起做）
=======
>>>>>>> 1420789 (feat(memory): 第三波 — MemoryPanelView 改 List+Section+EditMode 多选)
    private func jumpToSource(_ memory: Memory) {
        guard let cid = memory.sourceConversationId else { return }
        let pid = profileManager?.currentProfile.id ?? ""
        if let conv = ConversationListStore.conversation(id: cid, profileId: pid, context: modelContext) {
            viewModel.loadConversation(conv, context: modelContext)
        }
    }

<<<<<<< HEAD
    private func addMemory() {
        let text = newMemoryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let profileId = profileManager?.currentProfile.id ?? ""
        store.addUserPinned(
            content: text,
            category: newMemoryCategory,
            keywords: text.components(separatedBy: .whitespaces).filter { $0.count > 1 },
            profileId: profileId,
            context: modelContext
        )
=======
    // MARK: - Data
>>>>>>> 1420789 (feat(memory): 第三波 — MemoryPanelView 改 List+Section+EditMode 多选)

    private var groupedMemories: (hot: [Memory], warm: [Memory], cold: [Memory]) {
        var hot: [Memory] = []
        var warm: [Memory] = []
        var cold: [Memory] = []
        for mem in memories {
            let w = effectiveWeight(mem)
            if mem.isUserExplicit || w >= 0.3 { hot.append(mem) }
            else if w >= 0.05 { warm.append(mem) }
            else { cold.append(mem) }
        }
        return (hot, warm, cold)
    }

<<<<<<< HEAD
    private var isIOSStyle: Bool {
        true
=======
    private func effectiveWeight(_ memory: Memory) -> Double {
        DecayEngine.effectiveWeight(memory)
    }

    private func refreshMemories() {
        let profileId = profileManager?.currentProfile.id ?? ""
        memories = (try? store.listAll(profileId: profileId, context: modelContext)) ?? []
>>>>>>> 1420789 (feat(memory): 第三波 — MemoryPanelView 改 List+Section+EditMode 多选)
    }
}

// MARK: - Memory Card

struct MemoryCardView: View {
    let memory: Memory
    let effectiveWeight: Double
    var isFlashing: Bool = false
    var onPin: () -> Void
    var onDelete: () -> Void
    var onRevive: (() -> Void)? = nil          // 已失效记忆的复活（SC-B2）
    var onJumpToSource: (() -> Void)? = nil    // 出处跳转源对话（SC-B2）

    @State private var isHovering = false
    @State private var breathPhase: Double = 0
    @State private var flashOpacity: Double = 0

    private let categoryLabels: [String: String] = [
        "preference": "偏好", "fact": "事实", "relationship": "关系",
        "goal": "目标", "context": "情境"
    ]

    // Opacity: 0.25 (dead) to 1.0 (fresh)；已失效统一灰显
    private var baseOpacity: Double {
        if memory.supersededAt != nil { return 0.45 }
        return memory.isUserExplicit ? 1.0 : (0.25 + 0.75 * effectiveWeight)
    }

    // Breath: stronger memories breathe faster and more visibly
    private var breathAmplitude: Double { 0.03 * effectiveWeight }
    private var breathPeriod: Double { 3.0 + (1.0 - effectiveWeight) * 4.0 }

    // Border color: warm amber(1.0) → mint(0.5) → cool grey(0.0)
    private var borderColor: Color {
        if memory.isUserExplicit { return Color(hex: 0xD4A574) }
        if effectiveWeight > 0.5 {
            let t = (effectiveWeight - 0.5) * 2  // 0→1
            return blend(Theme.branchIndicator, Color(hex: 0xD4A574), t: t)
        } else {
            let t = effectiveWeight * 2  // 0→1
            return blend(Color(red: 0.6, green: 0.65, blue: 0.7), Theme.branchIndicator, t: t)
        }
    }

    private var borderWidth: CGFloat {
        if effectiveWeight > 0.3 { return 3 }
        if effectiveWeight > 0.05 { return 2 }
        return 1
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left border
            RoundedRectangle(cornerRadius: 1.5)
                .fill(borderColor)
                .frame(width: borderWidth)
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 4) {
                // Content
                Text(memory.content)
                    .font(.system(size: Theme.F.body))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(isIOSStyle ? 4 : 3)

                // 出处行（SC-B2）：有 quote 显示，可点跳源对话（v1 跳对话不定位消息）
                if let quote = memory.sourceQuote {
                    Button { onJumpToSource?() } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "quote.opening")
                                .font(.system(size: 7))
                            Text(quote)
                                .font(.system(size: Theme.F.caption))
                                .lineLimit(1)
                        }
                        .foregroundColor(Theme.textMuted)
                    }
                    .buttonStyle(.plain)
                    .disabled(onJumpToSource == nil)
                }

                // Meta row
                HStack(spacing: 6) {
                    // Category tag
                    Text(categoryLabels[memory.category] ?? memory.category)
                        .font(.system(size: Theme.F.badge, weight: .medium))
                        .foregroundColor(Theme.branchIndicator)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(Theme.branchIndicator.opacity(0.12))
                        )

                    // Access info
                    Text("\(memory.accessCount)次")
                        .font(.system(size: Theme.F.secondary))
                        .foregroundColor(Theme.textMuted)

                    Text(relativeDate(memory.lastAccessedAt))
                        .font(.system(size: Theme.F.secondary))
                        .foregroundColor(Theme.textMuted)

                    Spacer()

                    // 已失效标记（SC-B2）
                    if memory.supersededAt != nil {
                        Text("已失效")
                            .font(.system(size: Theme.F.badge))
                            .foregroundColor(Theme.textMuted)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().stroke(Theme.textMuted.opacity(0.5), lineWidth: 0.5))
                    }

                    // Pin icon
                    if memory.isUserExplicit {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .foregroundColor(Color(hex: 0xD4A574))
                    }

                    Menu {
                        Button(memory.isUserExplicit ? "取消钉住" : "钉住", action: onPin)
                        if memory.supersededAt != nil, let onRevive {
                            Button("复活", action: onRevive)
                        }
                        Button("删除", role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Theme.textMuted)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                }

                // Decay bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Theme.accent.opacity(0.2))
                        RoundedRectangle(cornerRadius: 1)
                            .fill(borderColor.opacity(0.5))
                            .frame(width: geo.size.width * effectiveWeight)
                    }
                }
                .frame(height: 2)
            }
            .padding(.leading, 8)
            .padding(.vertical, 6)
            .padding(.trailing, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.mainBg.opacity(0.6))
        )
        // Phosphor flash overlay
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: 0xD4A574).opacity(flashOpacity))
                .allowsHitTesting(false)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(baseOpacity + breathAmplitude * breathPhase)
        .blur(radius: effectiveWeight < 0.1 && !memory.isUserExplicit ? 1.5 : 0)
        .onHover { isHovering = $0 }
        .onAppear {
            withAnimation(
                .easeInOut(duration: breathPeriod)
                .repeatForever(autoreverses: true)
            ) {
                breathPhase = 1
            }
        }
        .onChange(of: isFlashing) { _, flashing in
            if flashing {
                withAnimation(.easeIn(duration: 0.2)) { flashOpacity = 0.4 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation(.easeOut(duration: 0.6)) { flashOpacity = 0 }
                }
            }
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let days = Int(-date.timeIntervalSinceNow / 86400)
        if days == 0 { return "今天" }
        if days == 1 { return "昨天" }
        if days < 30 { return "\(days)天前" }
        return "\(days / 30)月前"
    }

    private var isIOSStyle: Bool {
        true
    }

    /// Simple color blend between two colors
    private func blend(_ a: Color, _ b: Color, t: Double) -> Color {
        // Use opacity-based approximation since Color doesn't expose components easily
        // At t=0 → a, at t=1 → b
        return t > 0.5 ? b.opacity(1.0) : a.opacity(1.0)
    }
}
<<<<<<< HEAD
=======

// MARK: - Profile Editing（FileEditorSheet 复用 + 独立提示词 sheet）

/// 画像编辑 sheet 上下文（Identifiable 让 .sheet(item:) 触发）
struct ProfileEditingContext: Identifiable {
    let id = UUID()
    let text: String
    let modifiedAt: Date?
}

>>>>>>> 1420789 (feat(memory): 第三波 — MemoryPanelView 改 List+Section+EditMode 多选)
