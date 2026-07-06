import SwiftUI

/// 网关控制台：网关(4567/blossom.amberrib.com)所有内容的管理页。
/// Phase 1（App 侧只读 + 添加记忆）：状态 / 通道模型 / 记忆库 / 梦境日记 /
/// 碎碎念 / MCP 工具。删除与通道管理需网关侧 admin API，待 Phase 2。
/// 设计语言完全复用 Caelum's Console（白卡 16 圆角 / 暖灰标签，ConsoleView 设计 tokens）。
struct GatewayConsoleView: View {

    @State private var health: GatewayConsoleClient.HealthInfo? = nil
    @State private var healthLoaded = false
    @State private var models: [GatewayConsoleClient.GatewayModel] = []
    @State private var memories: [GatewayConsoleClient.GatewayMemory] = []
    @State private var memoryTotal = 0
    @State private var dreams: [GatewayConsoleClient.GatewayDream] = []
    @State private var desires: [GatewayConsoleClient.GatewayDesire] = []
    @State private var tools: [GatewayConsoleClient.GatewayTool] = []

    @State private var modelsExpanded = false
    @State private var toolsExpanded = false
    @State private var dreamsExpanded = false
    @State private var showAddMemory = false
    @State private var addMemoryResult: String? = nil

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                statusCard
                modelsCard
                memoriesCard
                dreamsCard
                desiresCard
                toolsCard
                Color.clear.frame(height: 32)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ConsoleView.pageBg.ignoresSafeArea())
        .navigationTitle("网关控制台")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await loadAll() }
        .task { await loadAll() }
        .sheet(isPresented: $showAddMemory) {
            AddGatewayMemorySheet { added in
                addMemoryResult = added ? "已入库（source: manual）" : "没有入库——可能与已有记忆重复"
                Task { await loadMemories() }
            }
            .presentationDetents([.medium])
        }
        .alert("添加记忆", isPresented: Binding(
            get: { addMemoryResult != nil },
            set: { if !$0 { addMemoryResult = nil } }
        )) {
            Button("好") { addMemoryResult = nil }
        } message: {
            Text(addMemoryResult ?? "")
        }
    }

    // MARK: - 数据加载

    private func loadAll() async {
        async let h = GatewayConsoleClient.health()
        async let m = GatewayConsoleClient.models()
        async let d = GatewayConsoleClient.dreams()
        async let de = GatewayConsoleClient.desires(limit: 10)
        async let t = GatewayConsoleClient.mcpTools()
        health = await h
        healthLoaded = true
        models = await m
        dreams = await d
        desires = await de
        tools = await t
        await loadMemories()
    }

    private func loadMemories() async {
        let r = await GatewayConsoleClient.memories(limit: 5)
        memories = r.items
        memoryTotal = r.total
    }

    // MARK: - 状态卡

    private var statusCard: some View {
        GatewayCard {
            gwLabel("GATEWAY", icon: "server.rack")
            HStack(spacing: 10) {
                Circle()
                    .fill(health?.ok == true ? Color(red: 0.55, green: 0.72, blue: 0.46) : Color(red: 0.78, green: 0.45, blue: 0.45))
                    .frame(width: 10, height: 10)
                Text(statusText)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(ConsoleView.textPrimary)
                Spacer()
                if let h = health {
                    Text("\(h.latencyMs) ms")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(ConsoleView.textMuted)
                }
            }
            .padding(.top, 6)
            Text(GatewayConsoleClient.baseURL)
                .font(.system(size: 12))
                .foregroundColor(ConsoleView.textMuted)
                .lineLimit(1)
                .padding(.top, 2)
            if let h = health {
                gwSubRow(icon: "brain", text: h.memoryConnected ? "记忆库已连接（Supabase）" : "记忆库未配置")
                    .padding(.top, 6)
            }
        }
    }

    private var statusText: String {
        if !healthLoaded { return "检查中…" }
        return health?.ok == true ? "在线" : "离线"
    }

    // MARK: - 通道 & 模型卡

    private var modelsCard: some View {
        GatewayCard {
            HStack {
                gwLabel("通道 & 模型", icon: "shippingbox")
                Spacer()
                expandChevron($modelsExpanded, enabled: !models.isEmpty)
            }
            Text("\(models.count)")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(ConsoleView.textPrimary)
                .padding(.top, 6)
            // 按 owned_by 分组统计
            let groups = Dictionary(grouping: models, by: { $0.owned_by })
                .map { (key: $0.key, count: $0.value.count) }
                .sorted { $0.count > $1.count }
            FlowChips(items: groups.map { "\($0.key) · \($0.count)" })
                .padding(.top, 6)
            if modelsExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(models) { m in
                        HStack {
                            Text(m.id)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(ConsoleView.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text(m.owned_by)
                                .font(.system(size: 10))
                                .foregroundColor(ConsoleView.textMuted)
                        }
                    }
                }
                .padding(.top, 10)
            }
        }
        .onTapGesture {
            guard !models.isEmpty else { return }
            withAnimation(.easeInOut(duration: 0.15)) { modelsExpanded.toggle() }
        }
    }

    // MARK: - 记忆库卡

    private var memoriesCard: some View {
        GatewayCard {
            HStack {
                gwLabel("记忆库", icon: "brain.head.profile")
                Spacer()
                Button {
                    showAddMemory = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(ConsoleView.textLabel)
                }
                .buttonStyle(.plain)
            }
            Text("\(memoryTotal)")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(ConsoleView.textPrimary)
                .padding(.top, 6)
            Text("条长期记忆 · 置顶 > 热度 > 时间")
                .font(.system(size: 12))
                .foregroundColor(ConsoleView.textMuted)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(memories.prefix(3)) { m in
                    memoryRow(m)
                }
            }
            .padding(.top, 10)
            NavigationLink {
                GatewayMemoriesPage()
            } label: {
                HStack {
                    Text("浏览全部记忆")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(ConsoleView.textLabel)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                        .foregroundColor(ConsoleView.textMuted)
                }
                .padding(.top, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func memoryRow(_ m: GatewayConsoleClient.GatewayMemory) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if m.is_pinned == true {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundColor(ConsoleView.textLabel)
                    .padding(.top, 3)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(m.content)
                    .font(.system(size: 13))
                    .foregroundColor(ConsoleView.textPrimary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let cat = m.category, !cat.isEmpty {
                        gwBadge(cat)
                    }
                    if let t = m.tier { gwBadge("T\(t)") }
                    Text(gwShortDate(m.created_at))
                        .font(.system(size: 10))
                        .foregroundColor(ConsoleView.textMuted)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - 梦境日记卡

    private var dreamsCard: some View {
        GatewayCard {
            HStack {
                gwLabel("梦境日记", icon: "moon.stars")
                Spacer()
                expandChevron($dreamsExpanded, enabled: dreams.count > 2)
            }
            Text("\(dreams.count)")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(ConsoleView.textPrimary)
                .padding(.top, 6)
            Text("篇日/周/月摘要（AI 夜间自动生成）")
                .font(.system(size: 12))
                .foregroundColor(ConsoleView.textMuted)
            if dreams.isEmpty {
                Text("还没有梦境日记")
                    .font(.system(size: 12))
                    .foregroundColor(ConsoleView.textMuted)
                    .padding(.top, 8)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(dreamsExpanded ? dreams : Array(dreams.prefix(2))) { d in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                gwBadge(d.layer ?? "daily")
                                Text(d.date ?? gwShortDate(d.created_at))
                                    .font(.system(size: 10))
                                    .foregroundColor(ConsoleView.textMuted)
                            }
                            Text(d.summary ?? "")
                                .font(.system(size: 13))
                                .foregroundColor(ConsoleView.textPrimary)
                                .lineLimit(dreamsExpanded ? 6 : 2)
                        }
                    }
                }
                .padding(.top, 10)
            }
        }
        .onTapGesture {
            guard dreams.count > 2 else { return }
            withAnimation(.easeInOut(duration: 0.15)) { dreamsExpanded.toggle() }
        }
    }

    // MARK: - 碎碎念卡

    private var desiresCard: some View {
        GatewayCard {
            gwLabel("碎碎念", icon: "bubble.left.and.text.bubble.right")
            Text("\(desires.count)")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(ConsoleView.textPrimary)
                .padding(.top, 6)
            Text("条主动念头（欲望系统生成）")
                .font(.system(size: 12))
                .foregroundColor(ConsoleView.textMuted)
            if desires.isEmpty {
                Text("最近没有碎碎念")
                    .font(.system(size: 12))
                    .foregroundColor(ConsoleView.textMuted)
                    .padding(.top, 8)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(desires.prefix(3)) { d in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.content)
                                .font(.system(size: 13))
                                .foregroundColor(ConsoleView.textPrimary)
                                .lineLimit(2)
                            Text(gwShortDate(d.created_at))
                                .font(.system(size: 10))
                                .foregroundColor(ConsoleView.textMuted)
                        }
                    }
                }
                .padding(.top, 10)
            }
        }
    }

    // MARK: - MCP 工具卡

    private var toolsCard: some View {
        GatewayCard {
            HStack {
                gwLabel("MCP & 内建工具", icon: "wrench.and.screwdriver")
                Spacer()
                expandChevron($toolsExpanded, enabled: !tools.isEmpty)
            }
            Text("\(tools.count)")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(ConsoleView.textPrimary)
                .padding(.top, 6)
            let groups = Dictionary(grouping: tools, by: { $0.source ?? "mcp" })
                .map { (key: $0.key, count: $0.value.count) }
                .sorted { $0.count > $1.count }
            FlowChips(items: groups.map { "\($0.key) · \($0.count)" })
                .padding(.top, 6)
            if toolsExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(tools) { t in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.name)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(ConsoleView.textPrimary)
                            if let desc = t.description, !desc.isEmpty {
                                Text(desc)
                                    .font(.system(size: 11))
                                    .foregroundColor(ConsoleView.textMuted)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
                .padding(.top, 10)
            }
        }
        .onTapGesture {
            guard !tools.isEmpty else { return }
            withAnimation(.easeInOut(duration: 0.15)) { toolsExpanded.toggle() }
        }
    }

    // MARK: - 小组件

    private func expandChevron(_ expanded: Binding<Bool>, enabled: Bool) -> some View {
        Image(systemName: expanded.wrappedValue ? "chevron.down" : "chevron.right")
            .font(.system(size: 11))
            .foregroundColor(ConsoleView.textMuted.opacity(enabled ? 1 : 0.3))
    }
}

// MARK: - 共享样式（网关控制台系列页面共用）

func gwLabel(_ text: String, icon: String) -> some View {
    HStack(spacing: 5) {
        Image(systemName: icon)
            .font(.system(size: 11))
            .foregroundColor(ConsoleView.textLabel)
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(ConsoleView.textLabel)
            .tracking(1)
    }
}

func gwBadge(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 9, weight: .medium))
        .foregroundColor(ConsoleView.textLabel)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(ConsoleView.pageBg))
}

func gwSubRow(icon: String, text: String) -> some View {
    HStack(spacing: 6) {
        Image(systemName: icon)
            .font(.system(size: 11))
            .foregroundColor(ConsoleView.textLabel)
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(ConsoleView.textMuted)
    }
}

func gwShortDate(_ iso: String?) -> String {
    guard let iso, iso.count >= 10 else { return "" }
    return String(iso.prefix(10))
}

/// 白卡容器：与 Caelum's Console 的 ConsoleCard 同一视觉（那边是 private，这里独立一份）
struct GatewayCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)
        )
    }
}

/// 简易 chip 行（自动换行）
struct FlowChips: View {
    let items: [String]

    var body: some View {
        // 简化：横向可滚动一行，chips 少时看起来就是静态行
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items, id: \.self) { text in
                    Text(text)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(ConsoleView.textUnit)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(ConsoleView.pageBg))
                }
            }
        }
    }
}

// MARK: - 添加记忆 sheet

struct AddGatewayMemorySheet: View {
    var onDone: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var content = ""
    @State private var category = "fact"
    @State private var submitting = false

    private let categories = ["fact", "preference", "goal", "event", "emotion"]

    var body: some View {
        NavigationStack {
            Form {
                Section("记忆内容") {
                    TextEditor(text: $content)
                        .frame(minHeight: 100)
                }
                Section("分类") {
                    Picker("分类", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Text("将写入网关记忆库（source: manual），与已有记忆自动查重。")
                        .font(.system(size: 12))
                        .foregroundColor(ConsoleView.textMuted)
                }
            }
            .navigationTitle("添加记忆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if submitting {
                        ProgressView()
                    } else {
                        Button("保存") {
                            let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !text.isEmpty else { return }
                            submitting = true
                            Task {
                                let ok = await GatewayConsoleClient.addMemory(content: text, category: category)
                                await MainActor.run {
                                    submitting = false
                                    dismiss()
                                    onDone(ok)
                                }
                            }
                        }
                        .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }
}

// MARK: - 全部记忆浏览页

struct GatewayMemoriesPage: View {
    @State private var items: [GatewayConsoleClient.GatewayMemory] = []
    @State private var total = 0
    @State private var loading = false
    @State private var category: String? = nil

    private let pageSize = 50
    private let categories = ["fact", "preference", "goal", "event", "emotion"]

    var body: some View {
        List {
            Section {
                ForEach(items) { m in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(m.content)
                            .font(.system(size: 14))
                            .foregroundColor(ConsoleView.textPrimary)
                        HStack(spacing: 6) {
                            if m.is_pinned == true {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(ConsoleView.textLabel)
                            }
                            if let cat = m.category, !cat.isEmpty { gwBadge(cat) }
                            if let t = m.tier { gwBadge("T\(t)") }
                            if let s = m.source, !s.isEmpty { gwBadge(s) }
                            Text(gwShortDate(m.created_at))
                                .font(.system(size: 10))
                                .foregroundColor(ConsoleView.textMuted)
                        }
                    }
                    .listRowBackground(Color.white)
                    .onAppear {
                        if m.id == items.last?.id { Task { await loadMore() } }
                    }
                }
            } header: {
                Text("\(total) 条 · \(category ?? "全部分类")")
            } footer: {
                if loading { ProgressView().frame(maxWidth: .infinity) }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ConsoleView.pageBg.ignoresSafeArea())
        .navigationTitle("记忆库")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("全部分类") { category = nil; Task { await reload() } }
                    ForEach(categories, id: \.self) { c in
                        Button(c) { category = c; Task { await reload() } }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundColor(ConsoleView.textLabel)
                }
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        loading = true
        let r = await GatewayConsoleClient.memories(limit: pageSize, offset: 0, category: category)
        items = r.items
        total = r.total
        loading = false
    }

    private func loadMore() async {
        guard !loading, items.count < total else { return }
        loading = true
        let r = await GatewayConsoleClient.memories(limit: pageSize, offset: items.count, category: category)
        items += r.items
        total = r.total
        loading = false
    }
}
