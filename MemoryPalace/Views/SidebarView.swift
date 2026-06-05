import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// 记忆分区过滤：Chats（本地新建）/ Almond（Claude导入）/ Amber（ChatGPT导入）
fileprivate enum SidebarFilter: Equatable {
    case chats
    case almond
    case amber
}

/// 左栏 tab 标识 —— 文件级可见，让 SidebarCardShape 等 ViewModifier 能引用。
fileprivate enum SidebarTab: Hashable {
    case all
    case favorites
    case trash
    case tag(id: String)

    var displayTitle: String {
        switch self {
        case .all: return "全部"
        case .favorites: return "收藏"
        case .trash: return "回收站"
        case .tag: return ""
        }
    }

    var isCustom: Bool {
        if case .tag = self { return true }
        return false
    }
}

struct SidebarView: View {
    @Binding var searchText: String
    @Binding var showFavoritesOnly: Bool
    @Binding var showTrash: Bool
    @Binding var showImporter: Bool
    @Binding var showSettings: Bool
    var viewModel: ConversationViewModel
    /// 路线 B 必填：@Query ConversationTag 用 init(profileId:) 构造 predicate。
    /// Parent (ContentView 在 App.body 层 `.id(profile.id)` 保证 profile 变化时 SidebarView
    /// 整个 re-init，@Query 带新 profileId predicate 自动 refetch。
    let profileId: String

    @Environment(\.modelContext) private var modelContext
    @Query private var tags: [ConversationTag]

    init(
        searchText: Binding<String>,
        showFavoritesOnly: Binding<Bool>,
        showTrash: Binding<Bool>,
        showImporter: Binding<Bool>,
        showSettings: Binding<Bool>,
        viewModel: ConversationViewModel,
        profileId: String
    ) {
        self._searchText = searchText
        self._showFavoritesOnly = showFavoritesOnly
        self._showTrash = showTrash
        self._showImporter = showImporter
        self._showSettings = showSettings
        self.viewModel = viewModel
        self.profileId = profileId
        _tags = Query(
            filter: #Predicate<ConversationTag> { $0.profileId == profileId },
            sort: \ConversationTag.order
        )
    }
    @State private var conversations: [Conversation] = []
    @State private var totalCount: Int = 0
    @State private var lastNavTapTime: Date = .distantPast
    @State private var isLoadingMore = false
    @State private var showNewTagSheet = false
    @State private var selectedTagId: String? = nil
    @State private var favoritedNodes: [(node: MessageNode, convTitle: String)] = []
    @State private var deletedNodes: [(node: MessageNode, convTitle: String)] = []
    @State private var renamingConversationId: String? = nil
    @State private var renameText: String = ""
    @State private var exportingConversation: Conversation? = nil
    @State private var searchResults: [SearchResult] = []
    @State private var stickerSearchResults: [StickerSearchResult] = []
    @State private var characterCardResults: [CharacterCardSearchResult] = []
    @State private var worldBookEntryResults: [WorldBookEntrySearchResult] = []
    @State private var memoryResults: [MemorySearchResult] = []
    @State private var isSearchActive = false
    @State private var searchBarExpanded = false
    @State private var searchFilter = SearchFilter()
    @State private var showAdvancedFilter = false
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var currentMatchIndex: Int = -1
    @State private var showSortPopover = false
    @State private var showProjectsPage = false
    @State private var memoryFilter: SidebarFilter = .chats
    @State private var showAllChats = false
    @AppStorage("exportMode") private var exportMode = "lightweight"
    @AppStorage("userName") private var userName = "你"
    @AppStorage("assistantName") private var assistantName = "助手"
    @Environment(ProfileManager.self) private var profileManager: ProfileManager?
    @Environment(CharacterCardManager.self) private var cardManager: CharacterCardManager?
    @Environment(GlobalWorldBookManager.self) private var globalWBManager: GlobalWorldBookManager?
    @Environment(RightPanelNavigator.self) private var rightPanelNavigator: RightPanelNavigator?
    private let pageSize = 100

    var body: some View {
        VStack(spacing: 0) {
            // ── App 标题行 ──────────────────────────────────────────────────
            HStack {
                Text("Lost in Blossom")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Button { showSettings = true } label: {
                    ZStack {
                        Circle()
                            .fill(Color(UIColor.secondarySystemFill))
                            .frame(width: 32, height: 32)
                        Image(systemName: "gearshape")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, screenSafeAreaTop + 8)
            .padding(.bottom, 12)

            // ── 搜索栏 ──────────────────────────────────────────────────────
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Theme.textMuted)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.95)) {
                                if searchBarExpanded && searchText.isEmpty {
                                    searchBarExpanded = false
                                } else if !searchBarExpanded {
                                    searchBarExpanded = true
                                }
                            }
                        }

                    if searchBarExpanded {
                        TextField("搜索对话...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: Theme.F.body))
                            .onSubmit { triggerSearch() }
                            .transition(.opacity)

                        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button(action: { triggerSearch() }) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: Theme.F.body))
                                    .foregroundColor(Theme.branchIndicator)
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showAdvancedFilter.toggle()
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(searchFilter.hasActiveFilters ? Theme.branchIndicator : Theme.textMuted)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, searchBarExpanded ? 16 : 0)
                .frame(width: searchBarExpanded ? nil : 44, height: 44)
                .frame(maxWidth: searchBarExpanded ? .infinity : nil)
                .clipShape(Capsule())
                .glassEffectCompat(tint: Color.white.opacity(0.15), in: Capsule())
                .animation(.spring(response: 0.35, dampingFraction: 0.95), value: searchBarExpanded)

                if !searchBarExpanded { Spacer() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            // ── 导航入口 ─────────────────────────────────────────────────────
            VStack(spacing: 0) {
                sidebarNavEntry(
                    icon: "bubble.left.and.bubble.right",
                    title: "Chats",
                    isSelected: !showProjectsPage && memoryFilter == .chats
                ) {
                    debouncedNavAction {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showProjectsPage = false
                            memoryFilter = .chats
                        }
                    }
                }
                sidebarNavEntry(
                    icon: "folder",
                    title: "Projects",
                    isSelected: showProjectsPage
                ) {
                    debouncedNavAction {
                        withAnimation(.easeInOut(duration: 0.2)) { showProjectsPage = true }
                    }
                }
                sidebarMemoryEntry(emoji: "🌰", title: "Almond", isSelected: !showProjectsPage && memoryFilter == .almond) {
                    debouncedNavAction {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showProjectsPage = false
                            memoryFilter = .almond
                        }
                    }
                }
                sidebarMemoryEntry(emoji: "🪨", title: "Amber", isSelected: !showProjectsPage && memoryFilter == .amber) {
                    debouncedNavAction {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showProjectsPage = false
                            memoryFilter = .amber
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            // Advanced filter panel
            if showAdvancedFilter {
                AdvancedSearchPanel(
                    filter: $searchFilter,
                    userName: userName,
                    assistantName: assistantName,
                    // 角色筛选只在「对话 + 搜 content + 已按➡️」场景有意义
                    isContentSearchActive: isSearchActive && searchFilter.resourceKind == .conversation && searchFilter.scope != .titleOnly,
                    onFilterChanged: { triggerSearchIfActive() }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // ── 标签列表（iOS 模式，支持 swipe-to-delete）─────────────────
            if isIOSStyle && !tags.isEmpty {
                List {
                    ForEach(tags) { tag in
                        Button {
                            if selectedTagId == tag.id {
                                selectTab(.all)
                            } else {
                                selectTab(.tag(id: tag.id))
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text(tag.emoji)
                                    .font(.system(size: 16))
                                Text(tag.name)
                                    .font(.system(size: 15))
                                    .foregroundColor(selectedTagId == tag.id ? Theme.textPrimary : Theme.textSecondary)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            selectedTagId == tag.id
                                ? Theme.accent.opacity(0.3)
                                : Color.clear
                        )
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteTag(id: tag.id)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .listRowSpacing(0)
                .frame(height: min(CGFloat(tags.count) * 44 + 8, 176))
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
            }

            // Chrome-style tab bar + content card
            // iOS 简化模式：隐藏 tab bar，只显示对话列表（固定「全部」视图）
            VStack(spacing: 0) {
                if !isIOSStyle {
                    sidebarTabBar
                }

            if isSearchActive {
                // MARK: - Search Results View
                if isSearching {
                    VStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("搜索中...")
                            .font(.caption)
                            .foregroundColor(Theme.textMuted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 40)
                } else {
                    let allEmpty = searchResults.isEmpty && stickerSearchResults.isEmpty && characterCardResults.isEmpty && worldBookEntryResults.isEmpty && memoryResults.isEmpty
                    if isIOSStyle && allEmpty {
                        compactEmptyCard(
                            icon: "magnifyingglass",
                            title: "没有找到结果",
                            subtitle: "换个关键词试试"
                        )
                        .sidebarCardShape(for: currentTab)

                        Spacer(minLength: 0)
                    } else if searchFilter.resourceKind == .sticker {
                        // 贴纸搜索结果
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                Color.clear.frame(height: 4)
                                ForEach(stickerSearchResults) { result in
                                    StickerMatchRow(result: result)
                                        .onTapGesture {
                                            navigateToStickerResult(result)
                                        }
                                }
                                if stickerSearchResults.isEmpty {
                                    VStack(spacing: 8) {
                                        Image(systemName: "star.circle")
                                            .font(.system(size: 28))
                                            .foregroundColor(Theme.textMuted.opacity(0.3))
                                        Text("没有找到贴纸")
                                            .font(.caption)
                                            .foregroundColor(Theme.textMuted)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 40)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                        .scrollDismissesKeyboard(.immediately)
                        .refreshable {
                            viewModel.flushPendingRefresh()
                            try? await Task.sleep(nanoseconds: 400_000_000)
                        }
                        .sidebarCardShape(for: currentTab)
                    } else if searchFilter.resourceKind == .characterCard {
                        resourceResultsView(kind: .characterCard)
                    } else if searchFilter.resourceKind == .worldBook {
                        resourceResultsView(kind: .worldBook)
                    } else if searchFilter.resourceKind == .memory {
                        resourceResultsView(kind: .memory)
                    } else {
                        let titleCount = searchResults.filter { $0.isTitleMatch }.count
                        let contentCount = searchResults.count - titleCount
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                Color.clear.frame(height: 4)

                                // 标题块
                                if titleCount > 0 {
                                    searchBucketLabel("标题 · \(titleCount)")
                                    ForEach($searchResults) { $group in
                                        if group.isTitleMatch {
                                            searchTitleRow(group: group)
                                        }
                                    }
                                }

                                // 分隔（两块都存在时）
                                if titleCount > 0 && contentCount > 0 {
                                    Divider()
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 6)
                                }

                                // 内容块
                                if contentCount > 0 {
                                    searchBucketLabel("内容 · \(contentCount)")
                                    ForEach($searchResults) { $group in
                                        if !group.isTitleMatch {
                                            searchContentRow(group: $group)
                                        }
                                    }
                                }

                                if searchResults.isEmpty {
                                    VStack(spacing: 8) {
                                        Image(systemName: "magnifyingglass")
                                            .font(.system(size: Theme.F.sectionHeader))
                                            .foregroundColor(Theme.textMuted.opacity(0.5))
                                        Text("没有找到结果")
                                            .font(.system(size: Theme.F.secondary))
                                            .foregroundColor(Theme.textMuted)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 40)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                    }
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                        .scrollDismissesKeyboard(.immediately)
                        .refreshable {
                            viewModel.flushPendingRefresh()
                            try? await Task.sleep(nanoseconds: 400_000_000)
                        }
                        .sidebarCardShape(for: currentTab)
                    }
                }
            } else if showProjectsPage {
                // MARK: - Projects (Coming Soon)
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 36))
                        .foregroundColor(Theme.textMuted.opacity(0.4))
                    Text("Projects")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                    Text("Coming Soon")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 60)

                Spacer(minLength: 0)
            } else {
                // MARK: - Normal Conversation List
                if isIOSStyle && shouldShowCompactListEmptyState {
                    compactEmptyCard(
                        icon: compactListEmptyStateIcon,
                        title: compactListEmptyStateTitle,
                        subtitle: compactListEmptyStateSubtitle
                    )
                    .sidebarCardShape(for: currentTab)

                    Spacer(minLength: 0)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            Color.clear.frame(height: 4)
                            let sourceFiltered = filteredConversations
                            let displayedConversations = showAllChats ? sourceFiltered : Array(sourceFiltered.prefix(8))
                            let hasMoreChats = !showAllChats && sourceFiltered.count > 8
                            ForEach(displayedConversations, id: \.id) { conversation in
                                if renamingConversationId == conversation.id {
                                    TextField("对话名称", text: $renameText)
                                        .textFieldStyle(.plain)
                                        .font(.system(size: Theme.F.label, weight: .medium))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .background(Theme.accent.opacity(0.5))
                                        .onSubmit {
                                            let newTitle = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                                            if !newTitle.isEmpty {
                                                conversation.title = newTitle
                                                conversation.updateTime = Date()
                                                viewModel.markConversationDirty()
                                            }
                                            renamingConversationId = nil
                                        }
                                } else {
                                    conversationRowView(conversation)
                                    .contextMenu {
                                        if showTrash {
                                            Button(action: {
                                                viewModel.restoreConversation(conversation)
                                                refreshList()
                                            }) {
                                                Label("恢复", systemImage: "arrow.uturn.backward")
                                            }

                                            Button(role: .destructive, action: {
                                                viewModel.permanentlyDeleteConversation(conversation, context: modelContext)
                                                refreshList()
                                            }) {
                                                Label("永久删除", systemImage: "trash.slash")
                                            }
                                        } else {
                                            Button(action: {
                                                renameText = conversation.title
                                                renamingConversationId = conversation.id
                                            }) {
                                                Label("重命名", systemImage: "pencil")
                                            }

                                            Button(action: { conversation.isFavorite.toggle() }) {
                                                Label(conversation.isFavorite ? "取消收藏" : "收藏整个对话", systemImage: conversation.isFavorite ? "star.slash" : "star")
                                            }

                                            Button(action: { conversation.memoryEnabled.toggle() }) {
                                                Label(conversation.memoryEnabled ? "关闭记忆参与" : "开启记忆参与", systemImage: conversation.memoryEnabled ? "brain" : "brain.head.profile")
                                            }

                                            if !tags.isEmpty {
                                                Menu("加标签") {
                                                    ForEach(tags) { tag in
                                                        Button(action: {
                                                            let item = FavoriteItem(
                                                                conversationId: conversation.id,
                                                                tagId: tag.id,
                                                                contentPreview: conversation.title,
                                                                profileId: profileId
                                                            )
                                                            modelContext.insert(item)
                                                        }) {
                                                            Label("\(tag.emoji) \(tag.name)", systemImage: "tag")
                                                        }
                                                    }
                                                }
                                            }

                                            Divider()

                                            Button("新建标签...") {
                                                showNewTagSheet = true
                                            }

                                            Divider()

                                            Button(action: {
                                                exportConversation(conversation)
                                            }) {
                                                Label("导出为 Markdown", systemImage: "doc.text")
                                            }

                                            Divider()

                                            Button(role: .destructive, action: {
                                                viewModel.softDeleteConversation(conversation)
                                                refreshList()
                                            }) {
                                                Label("删除", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                                if showAllChats && conversation.id == conversations.last?.id {
                                    Color.clear.frame(height: 0)
                                        .onAppear { loadMore() }
                                }
                            }

                            // "All Chats ›" footer — 仅在超过 8 条时显示
                            if hasMoreChats {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showAllChats = true
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text("All Chats")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(Theme.textMuted)
                                        Spacer()
                                        Text("\(totalCount)")
                                            .font(.system(size: 12))
                                            .foregroundColor(Theme.textMuted.opacity(0.7))
                                            .monospacedDigit()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(Theme.textMuted.opacity(0.5))
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 11)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }

                            // Favorited individual bubbles section
                            if showFavoritesOnly && !favoritedNodes.isEmpty {
                                Divider().opacity(0.3).padding(.horizontal, 12).padding(.vertical, 6)

                                HStack {
                                    Image(systemName: "text.bubble")
                                        .font(.caption2)
                                        .foregroundColor(Theme.textMuted)
                                    Text("收藏的气泡")
                                        .font(.caption)
                                        .foregroundColor(Theme.textMuted)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 2)

                                ForEach(favoritedNodes, id: \.node.id) { item in
                                    FavoritedBubbleRow(
                                        node: item.node,
                                        convTitle: item.convTitle,
                                        isSelected: viewModel.selectedConversation?.id == item.node.conversationId
                                    )
                                    .onTapGesture {
                                        navigateToNode(item.node)
                                    }
                                    .contextMenu {
                                        Button(action: {
                                            item.node.isFavorite = false
                                            fetchFavoritedNodes()
                                        }) {
                                            Label("取消收藏", systemImage: "star.slash")
                                        }
                                    }
                                }
                            }

                            // Deleted individual bubbles section (in trash mode)
                            if showTrash && !deletedNodes.isEmpty {
                                Divider().opacity(0.3).padding(.horizontal, 12).padding(.vertical, 6)

                                HStack {
                                    Image(systemName: "text.bubble")
                                        .font(.caption2)
                                        .foregroundColor(Theme.textMuted)
                                    Text("已删除的气泡")
                                        .font(.caption)
                                        .foregroundColor(Theme.textMuted)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 2)

                                ForEach(deletedNodes, id: \.node.id) { item in
                                    DeletedBubbleRow(
                                        node: item.node,
                                        convTitle: item.convTitle
                                    )
                                    .contextMenu {
                                        Button(action: {
                                            viewModel.restore(item.node)
                                            fetchDeletedNodes()
                                        }) {
                                            Label("恢复", systemImage: "arrow.uturn.backward")
                                        }

                                        Button(role: .destructive, action: {
                                            viewModel.permanentlyDeleteNode(item.node, context: modelContext)
                                            fetchDeletedNodes()
                                        }) {
                                            Label("永久删除", systemImage: "trash.slash")
                                        }
                                    }
                                }
                            }

                            // Empty state for trash
                            if showTrash && conversations.isEmpty && deletedNodes.isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "trash")
                                        .font(.system(size: Theme.F.sectionHeader))
                                        .foregroundColor(Theme.textMuted.opacity(0.5))
                                    Text("回收站是空的")
                                        .font(.system(size: Theme.F.secondary))
                                        .foregroundColor(Theme.textMuted)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                }
                            }

                            if isLoadingMore {
                                ProgressView()
                                    .padding()
                            }

                            // Bottom breathing room
                            Color.clear.frame(height: 4)
                        }
                    }
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.immediately)
                    .refreshable {
                        viewModel.flushPendingRefresh()
                        try? await Task.sleep(nanoseconds: 400_000_000)
                    }
                    .sidebarCardShape(for: currentTab)
                }
            }
            } // end card container
            .frame(maxHeight: .infinity)

            // Stats footer + settings
            HStack(spacing: 8) {
                if isSearchActive {
                    Button(action: { clearSearch() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: Theme.F.caption))
                            Text("清除搜索")
                                .font(.caption2)
                        }
                        .foregroundColor(Theme.branchIndicator)
                    }
                    .buttonStyle(.plain)

                    // 搜索结果计数
                    if !isSearching {
                        resultCountLabel()
                            .font(.caption2)
                            .foregroundColor(Theme.textMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    Spacer()

                    // 匹配索引 + 上下快速翻页
                    if !flatMatches.isEmpty {
                        Text("\(currentMatchIndex + 1)/\(flatMatches.count)")
                            .font(.caption2)
                            .foregroundColor(Theme.textMuted)
                            .monospacedDigit()
                        Button(action: { navigatePrev() }) {
                            Image(systemName: "chevron.up")
                                .font(.system(size: Theme.F.caption, weight: .medium))
                                .foregroundColor(Theme.branchIndicator)
                        }
                        .buttonStyle(.plain)
                        Button(action: { navigateNext() }) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: Theme.F.caption, weight: .medium))
                                .foregroundColor(Theme.branchIndicator)
                        }
                        .buttonStyle(.plain)
                    }
                } else if showTrash {
                    Text("回收站中 \(totalCount) 条对话")
                        .font(.caption2)
                        .foregroundColor(Theme.textMuted)
                    Spacer()
                } else {
                    Text("显示 \(conversations.count) / \(totalCount) 条对话")
                        .font(.caption2)
                        .foregroundColor(Theme.textMuted)
                    Spacer()
                }
            }
            .padding(.horizontal, isIOSStyle ? 20 : 16)
            .padding(.vertical, isIOSStyle ? 6 : 6)

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottomTrailing) {
            if isIOSStyle {
                Button(action: createNewConversation) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                        Text("New chat")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(Color.black))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 20)
                .padding(.bottom, 32)
            }
        }

        .background {
            if isIOSStyle {
                Theme.sidebarBg.ignoresSafeArea()
            } else {
                Theme.sidebarBg
            }
        }
        .onAppear { refreshList() }
        // 路线 B 下 ContentView.id(profileId) 已经让 SidebarView 在 profile 切换时
        // 整棵 re-init，@State 自然清空。保留此 observer 作为 defense-in-depth：
        // 若 SidebarView 恰好处于某个 edge case 不 re-init（比如外层 sheet 直接调 switchTo），
        // 这里也能兜底清理 @State 里的 @Model ref。
        .onReceive(NotificationCenter.default.publisher(for: .profileWillSwitch)) { _ in
            conversations = []
            exportingConversation = nil
            favoritedNodes = []
            deletedNodes = []
            searchResults = []
            stickerSearchResults = []
            characterCardResults = []
            worldBookEntryResults = []
            memoryResults = []
            totalCount = 0
            renamingConversationId = nil
            selectedTagId = nil
            searchText = ""
            showAllChats = false
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty { clearSearch() }
            refreshList()
        }
        .onChange(of: selectedTagId) { _, _ in refreshList() }
        .onChange(of: memoryFilter) { _, _ in showAllChats = false; refreshList() }
        .onChange(of: showImporter) { _, showing in if !showing { refreshList() } }
        .onChange(of: showSettings) { _, showing in if !showing { refreshList() } }
        .onChange(of: viewModel.sidebarRefreshTrigger) { _, _ in refreshList() }
        .sheet(isPresented: $showNewTagSheet) {
            NewTagSheet(profileId: profileId)
        }
        // Settings sheet is presented from ContentView for proper centering
        .sheet(item: $exportingConversation) { conversation in
            ExportOptionsSheet(
                conversation: conversation,
                viewModel: viewModel,
                userName: userName,
                assistantName: assistantName
            )
        }
    }

    @ViewBuilder
    private func conversationRowView(_ conversation: Conversation) -> some View {
        let row = ConversationRow(
            conversation: conversation,
            isSelected: viewModel.selectedConversation?.id == conversation.id,
            isFirst: conversation.id == conversations.first?.id
        )
        row.onTapGesture {
            viewModel.loadConversation(conversation, context: modelContext)
        }
    }

    private func exportConversation(_ conversation: Conversation) {
        if exportMode == "full" {
            // Delay to let context menu dismiss first
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                exportingConversation = conversation
            }
        } else {
        }
    }

    private var shouldShowCompactListEmptyState: Bool {
        guard isIOSStyle else { return false }
        if showTrash {
            return conversations.isEmpty && deletedNodes.isEmpty
        }
        if showFavoritesOnly {
            return conversations.isEmpty && favoritedNodes.isEmpty
        }
        return conversations.isEmpty
    }

    private var compactListEmptyStateIcon: String {
        if showTrash { return "trash" }
        if showFavoritesOnly { return "star" }
        if selectedTagId != nil { return "tag" }
        return "bubble.left.and.bubble.right"
    }

    private var compactListEmptyStateTitle: String {
        if showTrash { return "回收站是空的" }
        if showFavoritesOnly { return "还没有收藏" }
        if selectedTagId != nil { return "这个标签还没有对话" }
        return "还没有对话"
    }

    private var compactListEmptyStateSubtitle: String {
        if showTrash { return "删除的对话和气泡会出现在这里" }
        if showFavoritesOnly { return "收藏的对话和气泡会出现在这里" }
        if selectedTagId != nil { return "在对话上右键/长按可以加标签" }
        return "导入或新建后会出现在这里"
    }

    @ViewBuilder
    private func compactEmptyCard(icon: String, title: String, subtitle: String) -> some View {
        let cardBody = VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: Theme.F.sectionHeader))
                .foregroundColor(Theme.textMuted.opacity(0.45))

            Text(title)
                .font(.system(size: Theme.F.sectionHeader, weight: .medium))
                .foregroundColor(Theme.textPrimary)

            Text(subtitle)
                .font(.system(size: Theme.F.caption))
                .foregroundColor(Theme.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 170)

        // iOS 空态：ScrollView + 系统 .refreshable，和大卡下拉动画一致
        // （卡片跟手指下移 + 顶部 spinner 滑进）。frame(height: 170) 锁死小卡高度。
        // .scrollBounceBehavior(.always) 让没内容也能 bounce → refresh 可触发。
        // .scrollIndicators(.hidden) 去掉滚动条。
        ScrollView {
            cardBody
        }
        .frame(height: 170)
        .scrollBounceBehavior(.always)
        .scrollIndicators(.hidden)
        .refreshable {
            viewModel.flushPendingRefresh()
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private var sortLabel: String {
        switch searchFilter.sortOrder {
        case .recent: return "最近"
        case .oldest: return "最早"
        case .titleAZ: return "A→Z"
        case .titleZA: return "Z→A"
        }
    }

    @ViewBuilder
    private func sidebarNavEntry(icon: String, title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isSelected ? Theme.textPrimary : Theme.textMuted)
                    .frame(width: 24, alignment: .center)
                Text(title)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? Theme.textPrimary : Theme.textMuted)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.textMuted.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Theme.accent.opacity(0.5) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func sidebarMemoryEntry(emoji: String, title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(emoji)
                    .font(.system(size: 16))
                    .frame(width: 24, alignment: .center)
                Text(title)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? Theme.textPrimary : Theme.textMuted)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.textMuted.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Theme.accent.opacity(0.5) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var filteredConversations: [Conversation] {
        switch memoryFilter {
        case .chats:   return conversations.filter { $0.source == nil }
        case .almond:  return conversations.filter { $0.source == "claude" }
        case .amber:   return conversations.filter { $0.source == "chatgpt" }
        }
    }

    private var isIOSStyle: Bool {
        true
    }

    /// 从 UIKit window 读取真实的状态栏 / notch 高度。
    /// SidebarView 所在的 ZStack 使用 .ignoresSafeArea()，SwiftUI 环境里
    /// safeAreaInsets 归零，必须走 UIKit 层获取正确值。
    private var screenSafeAreaTop: CGFloat {
        guard
            let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first,
            let window = scene.windows.first(where: { $0.isKeyWindow })
                ?? scene.windows.first
        else { return 59 }   // iPhone 常见 fallback
        return max(0, window.safeAreaInsets.top)
    }

    // MARK: - Chrome-style Tab Bar

    private var currentTab: SidebarTab {
        if showTrash { return .trash }
        if showFavoritesOnly { return .favorites }
        if let id = selectedTagId { return .tag(id: id) }
        return .all
    }

    private var allTabs: [SidebarTab] {
        var result: [SidebarTab] = [.all, .favorites, .trash]
        result.append(contentsOf: tags.map { .tag(id: $0.id) })
        return result
    }

    private func debouncedNavAction(_ action: @escaping () -> Void) {
        let now = Date()
        guard now.timeIntervalSince(lastNavTapTime) > 0.3 else { return }
        lastNavTapTime = now
        action()
    }

    private func selectTab(_ tab: SidebarTab) {
        HapticService.shared.navigation()
        switch tab {
        case .all:
            showFavoritesOnly = false
            showTrash = false
            selectedTagId = nil
        case .favorites:
            showFavoritesOnly = true
            showTrash = false
            selectedTagId = nil
        case .trash:
            showTrash = true
            showFavoritesOnly = false
            selectedTagId = nil
        case .tag(let id):
            selectedTagId = id
            showFavoritesOnly = false
            showTrash = false
        }
        refreshList()
        // 如果正在搜索，切 tab 后用新 scope 重跑搜索
        triggerSearchIfActive()
    }

    private let tabCornerRadius: CGFloat = 16

    @State private var draggingTagId: String? = nil
    @State private var snappedTabId: SidebarTab? = nil

    private var sidebarTabBar: some View {
        // iOS：包一层 TabBarGestureContainer（UIHostingController wrapper），
        // 在容器 view 上挂 pan gesture，配合 TabView(.page) 的
        // require(toFail:) 屏蔽翻页
        return TabBarGestureContainer { sidebarTabBarBody }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var sidebarTabBarBody: some View {
        let tabs = allTabs
        let hasCustomTags = !self.tags.isEmpty

        if hasCustomTags {
            // 有自定义 tag：「全部」锁定在左，其余进 ScrollView 横滚
            HStack(spacing: 0) {
                // 锁定的「全部」tab
                tabButton(tabs[0], index: 0, total: tabs.count, fillWidth: false)

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            HStack(spacing: 0) {
                                ForEach(Array(tabs.dropFirst().enumerated()), id: \.element) { offset, tab in
                                    tabButton(tab, index: offset + 1, total: tabs.count, fillWidth: false)
                                        .id(tab)
                                }
                            }
                            .scrollTargetLayout()  // 只有 tab 是 snap 目标，加号不是
                            plusButton.id("plusButton")
                        }
                    }
                    .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollPosition(id: $snappedTabId)
                    // 两侧都 clip 会切掉第一个 tab 的反向圆角（offset -8pt），
                    // 两侧都 clip off（scrollClipDisabled）又会让 tab 横滑时盖到「全部」上。
                    // 用 mask 自定义：leading 只延伸 8pt 给反向圆角，trailing 正常 clip。
                    .scrollClipDisabled()
                    .mask(
                        GeometryReader { geo in
                            Rectangle()
                                .frame(width: geo.size.width + 8, height: geo.size.height)
                                .offset(x: -8)
                        }
                    )
                    .onChange(of: snappedTabId) { oldTab, newTab in
                        // Clock 齿轮手感：划过每个 tab 都震一下
                        if oldTab != nil && newTab != nil && oldTab != newTab {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
                    .onChange(of: currentTab) { _, newTab in
                        guard newTab != .all else { return }
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(newTab, anchor: .center)
                        }
                    }
                }
            }
            .padding(.leading, isIOSStyle ? 20 : 12)
            .padding(.trailing, isIOSStyle ? 20 : 12)
        } else {
            // 只有内置 tab：平分宽度铺满
            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                    tabButton(tab, index: index, total: tabs.count, fillWidth: true)
                }
                plusButton
            }
            .padding(.horizontal, isIOSStyle ? 20 : 12)
        }
    }

    private var plusButton: some View {
        Button {
            showNewTagSheet = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: Theme.F.secondary, weight: .medium))
                .foregroundColor(Theme.textMuted)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 4)
    }

    @ViewBuilder
    private func tabButton(_ tab: SidebarTab, index: Int, total: Int, fillWidth: Bool) -> some View {
        let isSelected = currentTab == tab
        let isFirst = index == 0

        let label = tab.isCustom ? tagLabel(for: tab) : tab.displayTitle

        Button { selectTab(tab) } label: {
            Text(label)
                .font(.system(size: Theme.F.secondary, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1)
                .if(!fillWidth) { $0.fixedSize() }
                .padding(.horizontal, isIOSStyle ? 16 : 12)
                .padding(.vertical, isIOSStyle ? 8 : 6)
                .if(fillWidth) { $0.frame(maxWidth: .infinity) }
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: tabCornerRadius,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: tabCornerRadius
                    )
                    .fill(isSelected ? Theme.mainBg : Color.clear)
                )
                .overlay(alignment: .bottomLeading) {
                    if isSelected && !isFirst {
                        InverseTabCorner(radius: 8, flipped: true)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    // 选中即显示右凹弧 — 最后一个 tab 右边是 "+" 按钮（sidebarBg），也需要过渡
                    if isSelected {
                        InverseTabCorner(radius: 8, flipped: false)
                    }
                }
                .contentShape(Rectangle())   // 整个 frame 都响应点击，不只是 Text 区域
        }
        .buttonStyle(.plain)
        .zIndex(isSelected ? 1 : 0)
        .if(tab.isCustom) { view in
            view
                .onDrag {
                    if case .tag(let id) = tab {
                        draggingTagId = id
                        return NSItemProvider(object: id as NSString)
                    }
                    return NSItemProvider()
                }
                .onDrop(of: [UTType.text], delegate: TagReorderDropDelegate(
                    targetTagId: tagIdOf(tab) ?? "",
                    tags: tags,
                    modelContext: modelContext,
                    draggingTagId: $draggingTagId
                ))
                .contextMenu {
                    if case .tag(let id) = tab {
                        Button(role: .destructive) {
                            deleteTag(id: id)
                        } label: {
                            Label("删除标签", systemImage: "trash")
                        }
                    }
                }
        }
    }

    private func tagIdOf(_ tab: SidebarTab) -> String? {
        if case .tag(let id) = tab { return id }
        return nil
    }

    private func tagLabel(for tab: SidebarTab) -> String {
        guard case .tag(let id) = tab,
              let t = tags.first(where: { $0.id == id }) else { return "" }
        return "\(t.emoji) \(t.name)"
    }

    private func deleteTag(id: String) {
        HapticService.shared.deleteAction()
        guard let tag = tags.first(where: { $0.id == id }) else { return }
        let pid = profileManager?.currentProfile.id ?? ""
        // 删除该 tag 的所有 FavoriteItem（仅当前楼层）
        let descriptor = FetchDescriptor<FavoriteItem>(
            predicate: #Predicate<FavoriteItem> { item in item.tagId == id && item.profileId == pid }
        )
        if let items = try? modelContext.fetch(descriptor) {
            for item in items { modelContext.delete(item) }
        }
        modelContext.delete(tag)
        try? modelContext.save()
        // 如果当前选中的就是被删的，回落
        if selectedTagId == id {
            selectedTagId = nil
            refreshList()
        }
    }

    private func navigateToNode(_ node: MessageNode) {
        // Find the conversation for this node
        let convId = node.conversationId
        let pid = profileManager?.currentProfile.id ?? ""
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate<Conversation> { conv in
                conv.id == convId && conv.profileId == pid
            }
        )
        guard let conversation = try? modelContext.fetch(descriptor).first else { return }

        // Set pending scroll BEFORE loadConversation — it fires after tree loads
        viewModel.pendingScrollNodeId = node.id
        viewModel.loadConversation(conversation, context: modelContext)
    }

    /// Fetch all Conversation titles in one query, return as [id: title] map
    private func fetchConversationTitleMap() -> [String: String] {
        let pid = profileManager?.currentProfile.id ?? ""
        let desc = FetchDescriptor<Conversation>(
            predicate: #Predicate<Conversation> { $0.profileId == pid }
        )
        guard let allConvs = try? modelContext.fetch(desc) else { return [:] }
        var map: [String: String] = [:]
        map.reserveCapacity(allConvs.count)
        for conv in allConvs { map[conv.id] = conv.title }
        return map
    }

    private func fetchFavoritedNodes() {
        let pid = profileManager?.currentProfile.id ?? ""
        let descriptor = FetchDescriptor<MessageNode>(
            predicate: #Predicate<MessageNode> { node in
                node.profileId == pid && node.isFavorite == true && node.isDeleted == false
            },
            sortBy: [SortDescriptor(\MessageNode.createTime, order: .reverse)]
        )
        guard let nodes = try? modelContext.fetch(descriptor) else {
            favoritedNodes = []
            return
        }

        let titleMap = fetchConversationTitleMap()
        favoritedNodes = nodes.map { node in
            (node: node, convTitle: titleMap[node.conversationId] ?? "未知对话")
        }
    }

    private func fetchDeletedNodes() {
        let pid = profileManager?.currentProfile.id ?? ""
        let descriptor = FetchDescriptor<MessageNode>(
            predicate: #Predicate<MessageNode> { node in
                node.profileId == pid && node.isDeleted == true
            },
            sortBy: [SortDescriptor(\MessageNode.deletedAt, order: .reverse)]
        )
        guard let nodes = try? modelContext.fetch(descriptor) else {
            deletedNodes = []
            return
        }

        let titleMap = fetchConversationTitleMap()
        deletedNodes = nodes.map { node in
            (node: node, convTitle: titleMap[node.conversationId] ?? "未知对话")
        }
    }

    private func conversationSortDescriptors() -> [SortDescriptor<Conversation>] {
        switch searchFilter.sortOrder {
        case .recent:
            return [SortDescriptor(\Conversation.updateTime, order: .reverse)]
        case .oldest:
            return [SortDescriptor(\Conversation.updateTime, order: .forward)]
        case .titleAZ:
            return [SortDescriptor(\Conversation.title, order: .forward)]
        case .titleZA:
            return [SortDescriptor(\Conversation.title, order: .reverse)]
        }
    }

    private func sortOptionButton(_ title: String, sort: SearchSort) -> some View {
        Button(action: {
            searchFilter.sortOrder = sort
            showSortPopover = false
            if isSearchActive { triggerSearch() }
            refreshList()
        }) {
            HStack(spacing: 6) {
                Image(systemName: searchFilter.sortOrder == sort ? "checkmark" : "")
                    .font(.system(size: Theme.F.secondary))
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: Theme.F.secondary))
            }
            .foregroundColor(Theme.textPrimary)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var flatMatches: [MatchedNode] {
        searchResults.flatMap { $0.matchedNodes }
    }

    private func clearSearch() {
        isSearchActive = false
        isSearching = false
        searchResults = []
        stickerSearchResults = []
        characterCardResults = []
        worldBookEntryResults = []
        memoryResults = []
        currentMatchIndex = -1
        searchTask?.cancel()
    }

    private func triggerSearch() {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        searchFilter.keyword = keyword
        guard !keyword.isEmpty || searchFilter.dateRange != .all else {
            clearSearch()
            return
        }
        isSearchActive = true
        isSearching = true
        currentMatchIndex = -1

        // 根据当前 tab 限定搜索范围：切到空 tag 时 scope 是空 Set → 直接没结果
        searchFilter.conversationIdScope = scopeForCurrentTab()
        // 回收站 tab 下：搜的是已删除的对话
        searchFilter.includeDeletedConversations = (currentTab == .trash)

        searchTask?.cancel()
        let filter = searchFilter
        let container = modelContext.container
        let pid = profileManager?.currentProfile.id ?? ""
        let kind = filter.resourceKind

        // MainActor 取 snapshot（避免跨 actor 访问 @Observable）
        let cardsSnapshot = cardManager?.cards ?? []
        let globalBooksSnapshot = globalWBManager?.books ?? []

        searchTask = Task {
            switch kind {
            case .conversation:
                async let msgResults = SearchService.performSearch(filter: filter, profileId: pid, container: container)
                async let stickerResults = SearchService.searchPlacedStickers(keyword: keyword, profileId: pid, container: container)
                let (msgs, stickers) = await (msgResults, stickerResults)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    searchResults = msgs
                    stickerSearchResults = stickers
                    characterCardResults = []
                    worldBookEntryResults = []
                    memoryResults = []
                    isSearching = false
                }
            case .branchContent:
                let msgs = await SearchService.performSearch(filter: filter, profileId: pid, container: container)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    searchResults = msgs
                    stickerSearchResults = []
                    characterCardResults = []
                    worldBookEntryResults = []
                    memoryResults = []
                    isSearching = false
                }
            case .sticker:
                let stickers = await SearchService.searchPlacedStickers(keyword: keyword, profileId: pid, container: container)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    stickerSearchResults = stickers
                    searchResults = []
                    characterCardResults = []
                    worldBookEntryResults = []
                    memoryResults = []
                    isSearching = false
                }
            case .characterCard:
                let cards = SearchService.searchCharacterCards(keyword: keyword, cards: cardsSnapshot, filter: filter)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    characterCardResults = cards
                    searchResults = []
                    stickerSearchResults = []
                    worldBookEntryResults = []
                    memoryResults = []
                    isSearching = false
                }
            case .worldBook:
                let entries = await SearchService.searchWorldBookEntries(
                    keyword: keyword, globalBooks: globalBooksSnapshot,
                    profileId: pid, container: container, filter: filter
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    worldBookEntryResults = entries
                    searchResults = []
                    stickerSearchResults = []
                    characterCardResults = []
                    memoryResults = []
                    isSearching = false
                }
            case .memory:
                let mems = await SearchService.searchMemories(
                    keyword: keyword, profileId: pid, container: container, filter: filter
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    memoryResults = mems
                    searchResults = []
                    stickerSearchResults = []
                    characterCardResults = []
                    worldBookEntryResults = []
                    isSearching = false
                }
            }
        }
    }

    /// 把当前 tab 翻译成搜索范围。
    /// - 「全部」/「回收站」：nil（不限；回收站搜索仍受 performSearch 里 isDeleted==false 的约束）
    /// - 「收藏」：所有 isFavorite 的 conv id
    /// - 自定义 tag：这个 tag 的 FavoriteItem 里对应的 conv id（空 tag 返回空 Set → 搜不到任何东西）
    private func scopeForCurrentTab() -> Set<String>? {
        let pid = profileManager?.currentProfile.id ?? ""
        switch currentTab {
        case .all, .trash:
            return nil
        case .favorites:
            let desc = FetchDescriptor<Conversation>(
                predicate: #Predicate<Conversation> { $0.profileId == pid && $0.isDeleted == false && $0.isFavorite == true }
            )
            let convs = (try? modelContext.fetch(desc)) ?? []
            return Set(convs.map(\.id))
        case .tag(let id):
            let tid = id
            let desc = FetchDescriptor<FavoriteItem>(
                predicate: #Predicate<FavoriteItem> { $0.profileId == pid && $0.tagId == tid }
            )
            let items = (try? modelContext.fetch(desc)) ?? []
            return Set(items.map(\.conversationId))
        }
    }

    private func navigateNext() {
        let matches = flatMatches
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % matches.count
        let match = matches[currentMatchIndex]
        navigateToNodeById(match.id, conversationId: match.conversationId)
    }

    private func navigatePrev() {
        let matches = flatMatches
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex - 1 + matches.count) % matches.count
        let match = matches[currentMatchIndex]
        navigateToNodeById(match.id, conversationId: match.conversationId)
    }

    /// Re-trigger search when filter changes.
    /// - 资源类型（非对话）：没有"列表过滤"对应概念 → 有关键词就直接进全量搜索，否则清空
    /// - 对话类型：已按 ➡️ → 重新跑全量；未按 → 只刷新列表
    private func triggerSearchIfActive() {
        if searchFilter.resourceKind != .conversation {
            let kw = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !kw.isEmpty {
                triggerSearch()
            } else {
                clearSearch()
            }
            return
        }
        if isSearchActive {
            triggerSearch()
        } else {
            refreshList()
        }
    }

    private func navigateToNodeById(_ nodeId: String, conversationId: String) {
        let cid = conversationId
        let pid = profileManager?.currentProfile.id ?? ""
        let convDesc = FetchDescriptor<Conversation>(
            predicate: #Predicate<Conversation> { conv in conv.id == cid && conv.profileId == pid }
        )
        guard let conversation = try? modelContext.fetch(convDesc).first else { return }
        // B20 part 2: 走 ViewModel 统一入口（去抖 + 主线/分支判断 + page 切换通知 + toast）
        viewModel.navigateToSearchResult(nodeId: nodeId, conversation: conversation, context: modelContext)
    }

    // MARK: - Resource Result Navigation
    // 只发请求，ContentView 监听 pendingTarget 决定 iOS/macOS 怎么显示右栏

    private func navigateToCardResult(_ result: CharacterCardSearchResult) {
        rightPanelNavigator?.pendingTarget = .init(tool: "cardLibrary", id: result.cardId)
    }

    private func navigateToWorldBookResult(_ result: WorldBookEntrySearchResult) {
        rightPanelNavigator?.pendingTarget = .init(tool: "worldBook", id: result.id)
    }

    private func navigateToMemoryResult(_ result: MemorySearchResult) {
        rightPanelNavigator?.pendingTarget = .init(tool: "memory", id: result.id)
    }

    private func navigateToStickerResult(_ result: StickerSearchResult) {
        if let nearestId = result.nearestMessageId {
            // 同一对话不重载，只滚动（延迟让 UI 更新完成）
            if viewModel.selectedConversation?.id == result.conversationId {
                viewModel.highlightedNodeId = nearestId
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    viewModel.scrollToNodeId = nearestId
                }
            } else {
                navigateToNodeById(nearestId, conversationId: result.conversationId)
            }
        } else {
            // 没有 nearestMessageId，至少跳到对话
            let cid = result.conversationId
            let pid = profileManager?.currentProfile.id ?? ""
            let convDesc = FetchDescriptor<Conversation>(
                predicate: #Predicate<Conversation> { conv in conv.id == cid && conv.profileId == pid }
            )
            if let conv = try? modelContext.fetch(convDesc).first {
                viewModel.loadConversation(conv, context: modelContext)
            }
        }
    }

    private func createNewConversation() {
        let profileId = profileManager?.currentProfile.id ?? ""
        let conversation = viewModel.createNewConversation(title: "新对话", profileId: profileId, context: modelContext)
        refreshList()
        viewModel.loadConversation(conversation, context: modelContext)
    }

    private func refreshList() {
        conversations.removeAll()
        fetchPage(offset: 0)
        if showFavoritesOnly {
            fetchFavoritedNodes()
        } else {
            favoritedNodes = []
        }
        if showTrash {
            fetchDeletedNodes()
        } else {
            deletedNodes = []
        }
    }

    private func loadMore() {
        guard !isLoadingMore else { return }
        fetchPage(offset: conversations.count)
    }

    private func fetchPage(offset: Int) {
        isLoadingMore = true

        let interval = searchFilter.dateRange.dateInterval
        let defaultSort = [SortDescriptor(\Conversation.updateTime, order: .reverse)]
        // 有关键词 / 有时间筛选 / 改过排序 → 都用用户选的 sortOrder
        let usingFilters = !searchText.isEmpty || searchFilter.dateRange != .all || searchFilter.sortOrder != .recent
        let sortBy = usingFilters ? conversationSortDescriptors() : defaultSort

        // Trash mode
        if showTrash {
            var descriptor = FetchDescriptor<Conversation>(sortBy: sortBy)
            descriptor.predicate = trashPredicate(search: searchText, interval: interval)

            if let count = try? modelContext.fetchCount(descriptor) {
                totalCount = count
            }

            descriptor.fetchOffset = offset
            descriptor.fetchLimit = pageSize

            if let results = try? modelContext.fetch(descriptor) {
                if offset == 0 {
                    conversations = results
                } else {
                    conversations.append(contentsOf: results)
                }
            }

            isLoadingMore = false
            return
        }

        // If a tag is selected, fetch only non-deleted conversations then filter by tag membership
        if let tagId = selectedTagId {
            let tid = tagId
            let pid = profileManager?.currentProfile.id ?? ""
            let favDescriptor = FetchDescriptor<FavoriteItem>(
                predicate: #Predicate<FavoriteItem> { item in
                    item.profileId == pid && item.tagId == tid
                }
            )
            if let items = try? modelContext.fetch(favDescriptor) {
                let convIds = Set(items.map(\.conversationId))
                // Fetch only non-deleted conversations (not all 1700+)
                var convDescriptor = FetchDescriptor<Conversation>(sortBy: sortBy)
                convDescriptor.predicate = normalPredicate(search: searchText, interval: interval, favoritesOnly: false)
                if let allConvs = try? modelContext.fetch(convDescriptor) {
                    let filtered = allConvs.filter { convIds.contains($0.id) }
                    totalCount = filtered.count
                    conversations = Array(filtered.prefix(pageSize))
                }
            }
            isLoadingMore = false
            return
        }

        var descriptor = FetchDescriptor<Conversation>(sortBy: sortBy)
        descriptor.predicate = normalPredicate(search: searchText, interval: interval, favoritesOnly: showFavoritesOnly)

        if memoryFilter == .chats {
            // Chats：分页加载
            if let count = try? modelContext.fetchCount(descriptor) {
                totalCount = count
            }
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = pageSize
            if let results = try? modelContext.fetch(descriptor) {
                if offset == 0 {
                    conversations = results
                } else {
                    conversations.append(contentsOf: results)
                }
            }
        } else {
            // Amber / Almond：全量加载 + 前端 source 过滤
            // 124 条 chatgpt 对话不会有性能问题，分页会导致 source 过滤后数量不准
            if let results = try? modelContext.fetch(descriptor) {
                let sourceKey = memoryFilter == .amber ? "chatgpt" : "claude"
                let filtered = results.filter { $0.source == sourceKey }
                conversations = Array(filtered.sorted { ($0.updateTime ?? .distantPast) > ($1.updateTime ?? .distantPast) })
                totalCount = filtered.count
            }
        }

        isLoadingMore = false
    }

    /// 构造非 trash 会话的 predicate（关键词 × 时间范围 × favoritesOnly 组合）
    /// 所有分支都加 `$0.profileId == pid` —— 路线 B 单 container 下必须按 profileId 隔离。
    private func normalPredicate(search: String, interval: (start: Date, end: Date)?, favoritesOnly: Bool) -> Predicate<Conversation> {
        let hasKeyword = !search.isEmpty
        let kw = search
        let pid = profileManager?.currentProfile.id ?? ""
        if let interval = interval {
            let s = interval.start
            let e = interval.end
            if favoritesOnly && hasKeyword {
                return #Predicate<Conversation> { conv in
                    conv.profileId == pid &&
                    conv.isDeleted == false && conv.isFavorite == true &&
                    conv.title.localizedStandardContains(kw) &&
                    conv.createTime >= s && conv.createTime <= e
                }
            } else if favoritesOnly {
                return #Predicate<Conversation> { conv in
                    conv.profileId == pid &&
                    conv.isDeleted == false && conv.isFavorite == true &&
                    conv.createTime >= s && conv.createTime <= e
                }
            } else if hasKeyword {
                return #Predicate<Conversation> { conv in
                    conv.profileId == pid &&
                    conv.isDeleted == false &&
                    conv.title.localizedStandardContains(kw) &&
                    conv.createTime >= s && conv.createTime <= e
                }
            } else {
                return #Predicate<Conversation> { conv in
                    conv.profileId == pid &&
                    conv.isDeleted == false &&
                    conv.createTime >= s && conv.createTime <= e
                }
            }
        } else {
            if favoritesOnly && hasKeyword {
                return #Predicate<Conversation> { conv in
                    conv.profileId == pid &&
                    conv.isDeleted == false && conv.isFavorite == true &&
                    conv.title.localizedStandardContains(kw)
                }
            } else if favoritesOnly {
                return #Predicate<Conversation> { conv in
                    conv.profileId == pid &&
                    conv.isDeleted == false && conv.isFavorite == true
                }
            } else if hasKeyword {
                return #Predicate<Conversation> { conv in
                    conv.profileId == pid &&
                    conv.isDeleted == false && conv.title.localizedStandardContains(kw)
                }
            } else {
                return #Predicate<Conversation> { conv in
                    conv.profileId == pid && conv.isDeleted == false
                }
            }
        }
    }

    /// 构造 trash（已删除）会话的 predicate（关键词 × 时间范围）
    private func trashPredicate(search: String, interval: (start: Date, end: Date)?) -> Predicate<Conversation> {
        let hasKeyword = !search.isEmpty
        let kw = search
        let pid = profileManager?.currentProfile.id ?? ""
        if let interval = interval {
            let s = interval.start
            let e = interval.end
            if hasKeyword {
                return #Predicate<Conversation> { conv in
                    conv.profileId == pid &&
                    conv.isDeleted == true &&
                    conv.title.localizedStandardContains(kw) &&
                    conv.createTime >= s && conv.createTime <= e
                }
            } else {
                return #Predicate<Conversation> { conv in
                    conv.profileId == pid &&
                    conv.isDeleted == true &&
                    conv.createTime >= s && conv.createTime <= e
                }
            }
        } else {
            if hasKeyword {
                return #Predicate<Conversation> { conv in
                    conv.profileId == pid &&
                    conv.isDeleted == true && conv.title.localizedStandardContains(kw)
                }
            } else {
                return #Predicate<Conversation> { conv in
                    conv.profileId == pid && conv.isDeleted == true
                }
            }
        }
    }

    // MARK: - Footer Result Count

    private func resultCountLabel() -> Text {
        switch searchFilter.resourceKind {
        case .conversation:
            let totalMatches = searchResults.reduce(0) { $0 + max(1, $1.matchedNodes.count) }
            return Text("\(searchResults.count) 个对话，\(totalMatches) 条结果")
        case .branchContent:
            let totalMatches = searchResults.reduce(0) { $0 + max(1, $1.matchedNodes.count) }
            return Text("\(searchResults.count) 个对话，\(totalMatches) 条分支结果")
        case .sticker:
            return Text("\(stickerSearchResults.count) 个贴纸")
        case .characterCard:
            return Text("\(characterCardResults.count) 个助手模板")
        case .worldBook:
            return Text("\(worldBookEntryResults.count) 条世界书")
        case .memory:
            return Text("\(memoryResults.count) 条记忆")
        }
    }

    // MARK: - Resource Results View

    @ViewBuilder
    private func resourceResultsView(kind: SearchResourceKind) -> some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                Color.clear.frame(height: 4)
                switch kind {
                case .characterCard:
                    if characterCardResults.isEmpty {
                        resourceEmptyState(icon: "person.crop.rectangle", text: "没有找到助手模板")
                    } else {
                        ForEach(characterCardResults) { result in
                            CharacterCardMatchRow(result: result)
                                .contentShape(Rectangle())
                                .onTapGesture { navigateToCardResult(result) }
                        }
                    }
                case .worldBook:
                    if worldBookEntryResults.isEmpty {
                        resourceEmptyState(icon: "book.closed", text: "没有找到世界书条目")
                    } else {
                        ForEach(worldBookEntryResults) { result in
                            WorldBookEntryMatchRow(result: result)
                                .contentShape(Rectangle())
                                .onTapGesture { navigateToWorldBookResult(result) }
                        }
                    }
                case .memory:
                    if memoryResults.isEmpty {
                        resourceEmptyState(icon: "brain", text: "没有找到记忆")
                    } else {
                        ForEach(memoryResults) { result in
                            MemoryMatchRow(result: result)
                                .contentShape(Rectangle())
                                .onTapGesture { navigateToMemoryResult(result) }
                        }
                    }
                default:
                    EmptyView()
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .sidebarCardShape(for: currentTab)
    }

    @ViewBuilder
    private func resourceEmptyState(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(Theme.textMuted.opacity(0.3))
            Text(text)
                .font(.caption)
                .foregroundColor(Theme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Search Result Rendering Helpers

    /// 搜索结果块的分隔标签（"标题 · 5" / "内容 · 12"）
    @ViewBuilder
    private func searchBucketLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: Theme.F.badge, weight: .medium))
            .foregroundColor(Theme.textMuted)
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 标题块的 row：纯标题，无 chevron、无展开
    @ViewBuilder
    private func searchTitleRow(group: SearchResult) -> some View {
        HStack(spacing: 6) {
            highlightedText(group.convTitle, keyword: searchFilter.keyword)
                .font(.system(size: Theme.F.sectionHeader, weight: .medium))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(viewModel.selectedConversation?.id == group.convId ? Theme.accent.opacity(0.5) : Color.clear)
        )
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            let cid = group.convId
            let pid = profileManager?.currentProfile.id ?? ""
            let convDesc = FetchDescriptor<Conversation>(
                predicate: #Predicate<Conversation> { conv in conv.id == cid && conv.profileId == pid }
            )
            if let conv = try? modelContext.fetch(convDesc).first {
                viewModel.loadConversation(conv, context: modelContext)
            }
        }
    }

    /// 内容块的 row：可展开的 conv header + matchedNodes 列表
    @ViewBuilder
    private func searchContentRow(group: Binding<SearchResult>) -> some View {
        let g = group.wrappedValue
        Button(action: { group.isExpanded.wrappedValue.toggle() }) {
            HStack(spacing: 6) {
                Image(systemName: g.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: Theme.F.caption, weight: .semibold))
                    .foregroundColor(Theme.textMuted)
                    .frame(width: 10)

                highlightedText(g.convTitle, keyword: searchFilter.keyword)
                    .font(.system(size: Theme.F.sectionHeader, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)

                Spacer()

                if g.matchedNodes.count > 0 {
                    Text("\(g.matchedNodes.count)")
                        .font(.caption2)
                        .foregroundColor(Theme.textMuted)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(viewModel.selectedConversation?.id == g.convId ? Theme.accent.opacity(0.5) : Color.clear)
            )
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .onTapGesture {
            let cid = g.convId
            let pid = profileManager?.currentProfile.id ?? ""
            let convDesc = FetchDescriptor<Conversation>(
                predicate: #Predicate<Conversation> { conv in conv.id == cid && conv.profileId == pid }
            )
            if let conv = try? modelContext.fetch(convDesc).first {
                viewModel.loadConversation(conv, context: modelContext)
            }
        }

        if g.isExpanded {
            let isBranch = searchFilter.resourceKind == .branchContent
            ForEach(g.matchedNodes) { match in
                ContentMatchRow(
                    nodeId: match.id,
                    role: match.role,
                    convTitle: "",
                    preview: match.preview,
                    createTime: match.createTime,
                    userName: userName,
                    assistantName: assistantName,
                    keyword: match.keyword
                )
                .padding(.leading, isBranch ? 32 : 16)
                .overlay(alignment: .topLeading) {
                    if isBranch {
                        Text("🌿")
                            .font(.system(size: 11))
                            .padding(.leading, 10)
                            .padding(.top, 6)
                            .opacity(0.7)
                    }
                }
                .onTapGesture {
                    if let idx = flatMatches.firstIndex(where: { $0.id == match.id }) {
                        currentMatchIndex = idx
                    }
                    navigateToNodeById(match.id, conversationId: match.conversationId)
                }
            }
        }
    }
}

// MARK: - New Tag Sheet

struct NewTagSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(ProfileManager.self) private var profileManager: ProfileManager?
    let profileId: String
    @Query private var tags: [ConversationTag]
    @State private var name = ""
    @State private var emoji = "🏷"

    init(profileId: String) {
        self.profileId = profileId
        _tags = Query(
            filter: #Predicate<ConversationTag> { $0.profileId == profileId },
            sort: \ConversationTag.order
        )
    }

    private let emojis = ["🏷", "⭐", "❤️", "💡", "🎯", "📝", "🔖", "💎", "🌸", "🎪", "🏠", "🌙"]

    var body: some View {
        VStack(spacing: 16) {
            Text("新建标签")
                .font(.headline)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                ForEach(emojis, id: \.self) { e in
                    Button(action: { emoji = e }) {
                        Text(e)
                            .font(.title3)
                            .padding(4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(emoji == e ? Theme.accent : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            TextField("标签名称", text: $name)
                .textFieldStyle(.plain)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.accent.opacity(0.3)))

            HStack {
                Button("取消") { dismiss() }
                    .foregroundColor(Theme.textMuted)
                Spacer()
                Button("创建") {
                    guard !name.isEmpty else { return }
                    let tag = ConversationTag(name: name, emoji: emoji, order: tags.count, profileId: profileId)
                    modelContext.insert(tag)
                    dismiss()
                }
                .disabled(name.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 280)
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    let conversation: Conversation
    let isSelected: Bool
    var showDivider: Bool = true
    var isFirst: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(conversation.title)
                    .font(.system(size: Theme.F.label, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 2)

                if conversation.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: Theme.F.badge))
                        .foregroundColor(Theme.favorite)
                }

                Text(conversation.updateTime.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.system(size: Theme.F.secondary))
                    .foregroundColor(Theme.textMuted.opacity(0.7))
                    .fixedSize()

                if conversation.nodeCount > 0 {
                    Text("\(conversation.nodeCount)")
                        .font(.system(size: Theme.F.secondary))
                        .foregroundColor(Theme.textMuted.opacity(0.7))
                        .fixedSize()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Theme.accent.opacity(0.45) : Color.clear)
            )
            .padding(.horizontal, 4)

            if showDivider && !isSelected {
                Divider().opacity(0.15).padding(.leading, 16)
            }
        }
    }
}

// MARK: - Favorited Bubble Row

struct FavoritedBubbleRow: View {
    let node: MessageNode
    let convTitle: String
    let isSelected: Bool
    @AppStorage("userName") private var userName = "你"
    @AppStorage("assistantName") private var assistantName = "助手"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "star.fill")
                .font(.system(size: Theme.F.badge))
                .foregroundColor(Theme.favorite)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 3) {
                Text(convTitle)
                    .font(.caption2)
                    .foregroundColor(Theme.textMuted)
                    .lineLimit(1)

                Text(node.content.prefix(80).replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: Theme.F.body))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(2)
            }

            Spacer()

            Text(node.role == "user" ? userName : assistantName)
                .font(.caption2)
                .foregroundColor(Theme.textMuted.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Theme.accent.opacity(0.5) : Color.clear)
        )
        .padding(.horizontal, 8)
    }
}

// MARK: - Deleted Bubble Row

struct DeletedBubbleRow: View {
    let node: MessageNode
    let convTitle: String
    @AppStorage("userName") private var userName = "你"
    @AppStorage("assistantName") private var assistantName = "助手"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "trash")
                .font(.system(size: Theme.F.badge))
                .foregroundColor(Theme.textMuted.opacity(0.6))
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 3) {
                Text(convTitle)
                    .font(.caption2)
                    .foregroundColor(Theme.textMuted)
                    .lineLimit(1)

                Text(node.content.prefix(80).replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: Theme.F.body))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(2)
            }

            Spacer()

            Text(node.role == "user" ? userName : assistantName)
                .font(.caption2)
                .foregroundColor(Theme.textMuted.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
    }
}

// MARK: - Content Match Row

// MARK: - Sticker Match Row（贴纸搜索结果）

struct StickerMatchRow: View {
    let result: StickerSearchResult

    var body: some View {
        HStack(spacing: 8) {
            // 贴纸图标/缩略图
            if result.isNote {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(red: 1, green: 0.96, blue: 0.75))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Text(String((result.noteContent ?? "").prefix(2)))
                            .font(.system(size: 8))
                            .foregroundColor(Theme.textPrimary)
                    )
            } else {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.branchIndicator.opacity(0.6))
                    .frame(width: 28, height: 28)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("🎨")
                        .font(.system(size: 9))
                    Text(result.assetName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                }
                Text(result.conversationTitle)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textMuted)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.clear)
        )
        .padding(.horizontal, 8)
    }
}

// MARK: - Character Card Match Row

struct CharacterCardMatchRow: View {
    let result: CharacterCardSearchResult

    var body: some View {
        HStack(spacing: 8) {
            // 头像缩略
            Group {
                if let data = result.imageData {
                    if let img = UIImage(data: data) {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else { Image(systemName: "person.crop.rectangle") }
                } else {
                    Image(systemName: "person.crop.rectangle")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textMuted)
                }
            }
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    highlightedText(result.cardName, keyword: result.keyword)
                        .font(.system(size: Theme.F.label, weight: .medium))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                    Text(result.matchedField)
                        .font(.system(size: Theme.F.badge))
                        .foregroundColor(Theme.textMuted)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Theme.textMuted.opacity(0.15)))
                }
                highlightedText(result.preview, keyword: result.keyword)
                    .font(.system(size: Theme.F.caption))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
    }
}

// MARK: - World Book Entry Match Row

struct WorldBookEntryMatchRow: View {
    let result: WorldBookEntrySearchResult

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: result.isGlobal ? "globe" : "book.closed")
                .font(.system(size: 14))
                .foregroundColor(Theme.branchIndicator)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(result.bookName)
                        .font(.system(size: Theme.F.badge))
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(1)
                    Text("›")
                        .font(.system(size: Theme.F.badge))
                        .foregroundColor(Theme.textMuted)
                    highlightedText(result.entryTitle, keyword: result.keyword)
                        .font(.system(size: Theme.F.label, weight: .medium))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                    Text(result.matchedField)
                        .font(.system(size: Theme.F.badge))
                        .foregroundColor(Theme.textMuted)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Theme.textMuted.opacity(0.15)))
                }
                highlightedText(result.preview, keyword: result.keyword)
                    .font(.system(size: Theme.F.caption))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
    }
}

// MARK: - Memory Match Row

struct MemoryMatchRow: View {
    let result: MemorySearchResult

    private var categoryLabel: String {
        switch result.category {
        case "fact": return "事实"
        case "preference": return "偏好"
        case "relationship": return "关系"
        case "goal": return "目标"
        case "context": return "情境"
        default: return result.category
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain")
                .font(.system(size: 13))
                .foregroundColor(Theme.branchIndicator)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(categoryLabel)
                        .font(.system(size: Theme.F.badge))
                        .foregroundColor(Theme.textMuted)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Theme.textMuted.opacity(0.15)))
                }
                highlightedText(result.preview, keyword: result.keyword)
                    .font(.system(size: Theme.F.caption))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(3)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
    }
}

// MARK: - Content Match Row

struct ContentMatchRow: View {
    let nodeId: String
    let role: String
    let convTitle: String
    let preview: String
    let createTime: Date?
    let userName: String
    let assistantName: String
    var keyword: String = ""

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: Theme.F.badge))
                .foregroundColor(Theme.branchIndicator)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 3) {
                if !convTitle.isEmpty {
                    Text(convTitle)
                        .font(.caption2)
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(1)
                }

                highlightedText(preview, keyword: keyword)
                    .font(.system(size: Theme.F.body))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(2)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(role == "user" ? userName : assistantName)
                    .font(.caption2)
                    .foregroundColor(Theme.textMuted.opacity(0.7))
                if let time = createTime {
                    Text(Self.dateFormatter.string(from: time))
                        .font(.system(size: Theme.F.caption))
                        .foregroundColor(Theme.textMuted.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.clear)
        )
        .padding(.horizontal, 8)
    }
}

// MARK: - Keyword Highlighting Helper

func highlightedText(_ text: String, keyword: String) -> Text {
    guard !keyword.isEmpty else { return Text(text) }
    var result = Text("")
    var searchStart = text.startIndex

    while let range = text.range(of: keyword, options: .caseInsensitive, range: searchStart..<text.endIndex) {
        let before = text[searchStart..<range.lowerBound]
        if !before.isEmpty {
            result = result + Text(before)
        }
        let matched = text[range]
        result = result + Text(matched)
            .foregroundColor(Theme.branchIndicator)
            .bold()
        searchStart = range.upperBound
    }
    let tail = text[searchStart...]
    if !tail.isEmpty {
        result = result + Text(tail)
    }
    return result
}

// MARK: - Advanced Search Panel

struct AdvancedSearchPanel: View {
    @Binding var filter: SearchFilter
    let userName: String
    let assistantName: String
    /// 是否处于全量内容搜索模式（按过 ➡️）。false = 列表标题过滤模式，角色筛选无意义 → 灰掉
    let isContentSearchActive: Bool
    var onFilterChanged: () -> Void

    /// 资源类型下（角色卡/世界书/记忆），范围/角色筛选无意义 → 灰掉
    private var isResourceSearch: Bool {
        filter.resourceKind == .characterCard ||
        filter.resourceKind == .worldBook ||
        filter.resourceKind == .memory
    }

    @State private var customStart = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customEnd = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            // 范围
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                categoryLabel("范围")
                scopeChip("标题", scope: .titleOnly)
                scopeChip("内容", scope: .contentOnly)
                scopeChip("标题+内容", scope: .both)
            }

            // 时间
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    categoryLabel("时间")
                    dateChip("全部", range: .all)
                    dateChip("今天", range: .today)
                    dateChip("7 天", range: .last7Days)
                    dateChip("30 天", range: .last30Days)
                    dateChip("90 天", range: .last90Days)
                    dateChip("自定义", range: .custom(start: customStart, end: customEnd))
                }

                if case .custom = filter.dateRange {
                    HStack(spacing: 8) {
                        DatePicker("", selection: $customStart, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .frame(maxWidth: 110)
                        Text("—")
                            .font(.caption)
                            .foregroundColor(Theme.textMuted)
                        DatePicker("", selection: $customEnd, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .frame(maxWidth: 110)
                    }
                    .onChange(of: customStart) { _, _ in
                        filter.dateRange = .custom(start: customStart, end: customEnd)
                        onFilterChanged()
                    }
                    .onChange(of: customEnd) { _, _ in
                        filter.dateRange = .custom(start: customStart, end: customEnd)
                        onFilterChanged()
                    }
                }
            }

            // 角色
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                categoryLabel("角色")
                roleChip(userName, role: "user")
                roleChip(assistantName, role: "assistant")
            }

            // 排序
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                categoryLabel("排序")
                sortChip("最近", sort: .recent)
                sortChip("最早", sort: .oldest)
                sortChip("A→Z", sort: .titleAZ)
                sortChip("Z→A", sort: .titleZA)
            }

            // 类型 — 6 个 chip 一行塞不下，用 FlowLayout 自动换行（B20 part 2 反馈 Bβ）
            VStack(alignment: .leading, spacing: 6) {
                categoryLabel("类型")
                FlowLayout(spacing: 8, lineSpacing: 6) {
                    typeChip("全部", kind: .conversation)
                    typeChip("🌿 分支", kind: .branchContent)
                    typeChip("🎨 贴纸", kind: .sticker)
                    typeChip("👤 助手模板", kind: .characterCard)
                    typeChip("📚 世界书", kind: .worldBook)
                    typeChip("🧠 记忆", kind: .memory)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, isIOSStyle ? 25 : 17)
        .padding(.trailing, isIOSStyle ? 20 : 12)
        .padding(.top, 8)
        .padding(.bottom, 18)
    }

    private var isIOSStyle: Bool {
        true
    }

    /// 分类名（时间/角色/排序/类型）
    private func categoryLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: Theme.F.badge, weight: .medium))
            .foregroundColor(Theme.textMuted)
    }

    /// 统一的纯文字过滤选项：字号 = tab 栏字号，选中态靠字重+颜色，无背景
    private func filterOption(_ title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: Theme.F.secondary, weight: isActive ? .semibold : .regular))
                .foregroundColor(isActive ? Theme.branchIndicator : Theme.textSecondary)
                .lineLimit(1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func dateChip(_ title: String, range: DateRange) -> some View {
        filterOption(title, isActive: filter.dateRange == range) {
            withAnimation(.easeInOut(duration: 0.15)) {
                filter.dateRange = range
            }
            onFilterChanged()
        }
    }

    private func roleChip(_ title: String, role: String) -> some View {
        let isActive = filter.roles.contains(role)
        // 列表标题过滤模式下，角色对 Conversation.title 无意义 → 灰掉 + 禁用
        return Button(action: {
            if isActive && filter.roles.count > 1 {
                filter.roles.remove(role)
            } else if !isActive {
                filter.roles.insert(role)
            }
            onFilterChanged()
        }) {
            Text(title)
                .font(.system(size: Theme.F.secondary, weight: isActive && isContentSearchActive ? .semibold : .regular))
                .foregroundColor(
                    isContentSearchActive
                        ? (isActive ? Theme.branchIndicator : Theme.textSecondary)
                        : Theme.textMuted.opacity(0.4)
                )
                .lineLimit(1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isContentSearchActive)
    }

    private func sortChip(_ title: String, sort: SearchSort) -> some View {
        filterOption(title, isActive: filter.sortOrder == sort) {
            withAnimation(.easeInOut(duration: 0.15)) {
                filter.sortOrder = sort
            }
            onFilterChanged()
        }
    }

    private func scopeChip(_ title: String, scope: SearchScope) -> some View {
        // 资源搜索（角色卡/世界书/记忆）没"标题 vs 内容"二分 → 灰掉 + 禁用
        Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                filter.scope = scope
            }
            onFilterChanged()
        }) {
            Text(title)
                .font(.system(size: Theme.F.secondary, weight: filter.scope == scope && !isResourceSearch ? .semibold : .regular))
                .foregroundColor(
                    isResourceSearch
                        ? Theme.textMuted.opacity(0.4)
                        : (filter.scope == scope ? Theme.branchIndicator : Theme.textSecondary)
                )
                .lineLimit(1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isResourceSearch)
    }

    private func typeChip(_ title: String, kind: SearchResourceKind) -> some View {
        filterOption(title, isActive: filter.resourceKind == kind) {
            withAnimation(.easeInOut(duration: 0.15)) {
                filter.resourceKind = kind
            }
            onFilterChanged()
        }
    }
}

// MARK: - Inverse Tab Corner（Chrome 反向圆角）

struct InverseTabCorner: View {
    let radius: CGFloat
    let flipped: Bool

    var body: some View {
        InverseTabCornerShape()
            .fill(Theme.mainBg)
            .frame(width: radius, height: radius)
            .scaleEffect(x: flipped ? -1 : 1, anchor: .center)
            .offset(x: flipped ? -radius : radius)
    }
}

struct InverseTabCornerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(rect.width, rect.height)
        // 填 mainBg 的区域：左下角 + 凹弧
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: r))
        path.addLine(to: CGPoint(x: r, y: r))
        path.addArc(
            center: CGPoint(x: r, y: 0),
            radius: r,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Sidebar Card Shape（Chrome 风格：选中 tab 下方 topLeading 清零连上 tab）

private struct SidebarCardShape: ViewModifier {
    let tab: SidebarTab

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, horizontalPadding)
    }

    /// iOS 下 tab bar 已隐藏，四角统一圆角；macOS tab bar 常显，全部标签下左上角贴边。
    private var topLeadingRadius: CGFloat {
        16
    }

    private var horizontalPadding: CGFloat {
        20
    }
}

extension View {
    /// 左栏内容卡：Theme.mainBg 底 + 跟随选中 tab 的 UnevenRoundedRectangle + 水平 padding。
    /// 搜索结果卡、空结果卡、正常列表卡、贴纸搜索卡 5 处统一走这条。
    fileprivate func sidebarCardShape(for tab: SidebarTab) -> some View {
        modifier(SidebarCardShape(tab: tab))
    }
}

// MARK: - Tag Reorder Drop Delegate

struct TagReorderDropDelegate: DropDelegate {
    let targetTagId: String
    let tags: [ConversationTag]
    let modelContext: ModelContext
    @Binding var draggingTagId: String?

    func performDrop(info: DropInfo) -> Bool {
        draggingTagId = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let fromId = draggingTagId, fromId != targetTagId else { return }
        reorder(fromId: fromId, toId: targetTagId)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool { true }

    private func reorder(fromId: String, toId: String) {
        var sorted = tags.sorted { $0.order < $1.order }
        guard let fromIdx = sorted.firstIndex(where: { $0.id == fromId }),
              let toIdx = sorted.firstIndex(where: { $0.id == toId }) else { return }
        let moving = sorted.remove(at: fromIdx)
        sorted.insert(moving, at: toIdx)
        for (i, tag) in sorted.enumerated() {
            tag.order = i
        }
        try? modelContext.save()
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    var icon: String? = nil
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption2)
                }
                Text(title)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isActive ? Theme.accent : Theme.mainBg)
            )
            .foregroundColor(isActive ? Theme.textPrimary : Theme.textMuted)
        }
        .buttonStyle(.plain)
    }
}
