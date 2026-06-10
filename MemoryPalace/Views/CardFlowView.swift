import SwiftUI
import SwiftData
import UIKit
import MarkdownUI
import UniformTypeIdentifiers
import VariableBlur

private struct TextSelectItem: Identifiable {
    let id: String
    let text: String
    let thinkingText: String?
}

struct CardFlowView: View {
    var viewModel: ConversationViewModel
    var stickerVM: StickerViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(ProfileManager.self) private var profileManager: ProfileManager?
    @Environment(ProviderManager.self) private var providerManager: ProviderManager?
    @Environment(PresetManager.self) private var presetManager: PresetManager?
    // globalWBManager 通过 ContentView 同步到 viewModel.globalWorldBookEntries
    @AppStorage("blurRadius") private var blurRadius = 1.3
    @AppStorage("bubbleSpacing") private var bubbleSpacing: Double = 31
    @State private var showInConvSearch = false
    @FocusState private var inConvSearchFocused: Bool
    @State private var showStickerPanel = false
    @State private var showAddToChat = false
    @State private var showFilePicker = false
    @State private var fileErrorMessage: String?
    @State private var pendingImageData: Data?
    @State private var pendingFileData: Data?
    @State private var pendingFileName: String?
    // iOS 下 PinBar 已挪到 ContentView.iOSChatTopBar，state 同步搬走。
    // macOS 下 PinBar 仍作为 VStack 子项留在 CardFlowView，保留这两个 state。
    @State private var isAtBottom: Bool = true
    @State private var lastStreamingScrollTime: Date = .distantPast
    @State private var textSelectItem: TextSelectItem?

    @ViewBuilder
    private func makeBubbleView(for node: MessageNode) -> some View {
        let info = viewModel.branchInfoMap[node.id]
        let isNodeStreaming = viewModel.providerRouter.isStreaming && node.id == viewModel.currentPath.last?.id && node.role == "assistant"
        let isNodeHighlighted = viewModel.highlightedNodeId == node.id
        let isNodeSearchMatch = viewModel.inConvMatches.contains(node.id)
        // 思考链流式状态（只传给正在流式输出的那个节点）
        let isThinkingNow = isNodeStreaming && viewModel.isThinking
        let streamingThinkingForNode = isNodeStreaming ? viewModel.streamingThinkingText : ""
        let thinkingSummaryForNode = isNodeStreaming ? viewModel.thinkingSummary : ""
        // CC Bridge provider 检测：用于 CCThinkingView 显示条件，防止切换 provider 后 thinking 残留
        let selectedModelId = UserDefaults.standard.string(forKey: "selectedChatModel") ?? ""
        let currentProviderModel = providerManager?.model(byId: selectedModelId) ?? providerManager?.availableModels.first
        let isCCBridge = currentProviderModel.flatMap { providerManager?.provider(for: $0) }?.type == .ccBridge
        BubbleView(
            node: node,
            hasBranches: info != nil,
            branchInfo: info,
            isStreaming: isNodeStreaming,
            isThinking: isThinkingNow,
            streamingThinkingText: streamingThinkingForNode,
            thinkingSummary: thinkingSummaryForNode,
            isHighlighted: isNodeHighlighted,
            isSearchMatch: isNodeSearchMatch,
            isLastAssistant: node.role == "assistant" && node.id == viewModel.currentPath.last?.id,
            isCCBridgeProvider: isCCBridge,
            onToggleFavorite: { viewModel.toggleFavorite(node) },
            onTogglePin: { viewModel.togglePin(node) },
            onSoftDelete: { viewModel.softDelete(node) },
            onSwitchBranch: { nodeId, idx in viewModel.switchBranch(at: nodeId, to: idx) },
            onRegenerate: makeRegenerateAction(for: node),
            onEdit: makeEditAction(for: node),
            regexScripts: {
                let profileScripts = profileManager?.currentProfile.regexScripts ?? []
                let presetId = profileManager?.currentProfile.presetId ?? ""
                let presetScripts = presetManager?.preset(byId: presetId)?.regexScripts ?? []
                return presetScripts + profileScripts
            }()
        )
    }

    private func makeRegenerateAction(for node: MessageNode) -> (() -> Void)? {
        guard node.role == "assistant", let pm = providerManager else { return nil }
        return {
            let prof = self.profileManager!.currentProfile
            let preset = self.presetManager?.preset(byId: prof.presetId) ?? Preset.balanced
            let modelId = UserDefaults.standard.string(forKey: "selectedChatModel") ?? ""
            let model = pm.model(byId: modelId) ?? pm.availableModels.first ?? ProviderModel(providerId: "openrouter", modelId: "anthropic/claude-sonnet-4", name: "Claude Sonnet 4")
            self.viewModel.regenerate(assistantNodeId: node.id, model: model, profile: prof, preset: preset, providerManager: pm, context: self.modelContext)
        }
    }

    private func makeEditAction(for node: MessageNode) -> ((String) -> Void)? {
        guard node.role == "user", let pm = providerManager else { return nil }
        return { newText in
            let prof = self.profileManager!.currentProfile
            let preset = self.presetManager?.preset(byId: prof.presetId) ?? Preset.balanced
            let modelId = UserDefaults.standard.string(forKey: "selectedChatModel") ?? ""
            let model = pm.model(byId: modelId) ?? pm.availableModels.first ?? ProviderModel(providerId: "openrouter", modelId: "anthropic/claude-sonnet-4", name: "Claude Sonnet 4")
            self.viewModel.editAndResend(node.id, newText: newText, model: model, profile: prof, preset: preset, providerManager: pm, context: self.modelContext)
        }
    }

    // Pin Bar handlers：iOS 版已挪到 ContentView；macOS 版保留（PinBar 仍在 CardFlowView）

    /// 三步回底（滚到底部哨兵 = content 真正的底）：
    /// 1. 先无动画滚到 lastId（让 LazyVStack 载入长 bubble，此时哨兵可能还没 mount）
    /// 2. withAnimation 0.3s 滚到哨兵（精准到真正底）
    /// 3. 0.5s 后无动画再滚哨兵一次（MarkdownUI async 撑大 lastId 后补位）
    ///
    /// 之前 scrollTo(lastId, anchor: .bottom) 只让 lastId 底对齐可视底，但 lastId 下方
    /// 还有 spacing 22 + 哨兵 1 + padding 16 + sticker canvas ≈ 几十到几百 pt，导致
    /// 滚不到真正的底（log 显示 offY=3116 size=3876 差 200 pt）
    /// force=false（默认）：只在用户已经在底部时才滚，避免流式时弹跳
    /// force=true：强制滚底（切换对话、消息完成、用户点回底按钮）
    private func scrollToLastMessage(proxy: ScrollViewProxy, force: Bool = false) {
        guard force || isAtBottom else { return }
        guard let lastId = viewModel.currentPath.last?.id else { return }
        // 统一禁动画：避免 scrollTo 与 WebView 高度变化同帧竞争导致白屏
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            proxy.scrollTo(lastId, anchor: .bottom)
        }
        // 延迟滚到哨兵（content 真正的底），同样禁动画
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            var tx2 = Transaction()
            tx2.disablesAnimations = true
            withTransaction(tx2) {
                proxy.scrollTo("__bottom_sentinel__", anchor: .bottom)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            proxy.scrollTo("__bottom_sentinel__", anchor: .bottom)
        }
    }

    var body: some View {
        if viewModel.isLoading {
            VStack {
                Spacer()
                ProgressView("加载中...")
                    .foregroundColor(Theme.textMuted)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // iOS 下路线 C chat page 有 wallpaper，loading 区透明让 wallpaper 可见
        } else {
            VStack(spacing: 0) {
                // In-conversation search bar
                if showInConvSearch {
                    InConversationSearchBar(
                        viewModel: viewModel,
                        focused: $inConvSearchFocused,
                        onDismiss: {
                            showInConvSearch = false
                            viewModel.clearInConvSearch()
                        }
                    )
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        // 方案 2 v2：恢复 ZStack sibling 结构（之前 .overlay() 把 sticker overlay
                        // frame 锁定到 LazyVStack 大小，sticker 拖到 LazyVStack 之外就接不到 touch）。
                        // StickerCanvasLayer 自己声明 minHeight = max sticker maxY + buffer，让
                        // ZStack 自然 layout 时 height = max(LazyVStack.h, sticker overlay 声明 h)，
                        // 保证 overlay 永远覆盖所有 sticker 实际位置。
                        // 详见 docs/plan-sticker-pan-relationship-fix-2026-04-25.md 方案 2 v2。
                        ZStack(alignment: .topLeading) {
                            LazyVStack(spacing: bubbleSpacing) {
                                ForEach(viewModel.currentPath, id: \.id) { node in
                                    makeBubbleView(for: node)
                                        .id(node.id)
                                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                                        .background(
                                            GeometryReader { geo in
                                                Color.clear.task(id: geo.frame(in: .named("scrollContent")).midY) {
                                                    stickerVM.bubblePositions[node.id] = geo.frame(in: .named("scrollContent")).midY
                                                }
                                            }
                                        )
                                }
                                // 底部哨兵：scrollToLastMessage 精准回底 target
                                Color.clear
                                    .frame(height: 1)
                                    .id("__bottom_sentinel__")
                            }
                            // 新消息入场动画：路径长度变化时触发 ForEach item transition
                            .animation(.easeOut(duration: 0.2), value: viewModel.currentPath.count)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                            .frame(maxWidth: .infinity)

                            StickerCanvasLayer(
                                stickerVM: stickerVM,
                                profileId: profileManager?.currentProfile.id ?? ""
                            )
                        }
                        .coordinateSpace(name: "scrollContent")
                        .onDrop(of: [UTType.plainText], isTargeted: nil) { providers, location in
                            handleStickerDrop(providers: providers, location: location)
                        }
                    }
                    .contentMargins(.top, 50, for: .scrollContent)
                    // 路线 C + PinBar 挪位后：PinBar 已进 ContentView.iOSChatTopBar HStack。
                    // 这里只剩 blur + gradient 130pt 的视觉柔化层（z 层：blur < nav HStack）。
                    .overlay(alignment: .top) {
                        ZStack {
                            VariableBlurView(maxBlurRadius: blurRadius, direction: .blurredTopClearBottom)
                            LinearGradient(
                                stops: [
                                    .init(color: Theme.mainBg, location: 0.0),
                                    .init(color: Theme.mainBg.opacity(0.7), location: 0.15),
                                    .init(color: Theme.mainBg.opacity(0.5), location: 0.28),
                                    .init(color: Theme.mainBg.opacity(0.3), location: 0.45),
                                    .init(color: Theme.mainBg.opacity(0.1), location: 0.75),
                                    .init(color: Theme.mainBg.opacity(0), location: 1.0),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                        .frame(height: 130)
                        .ignoresSafeArea(.all, edges: .top)
                        .allowsHitTesting(false)
                    }

                    .onScrollGeometryChange(for: Bool.self) { geometry in
                        // tolerance 200pt：content 下方有 padding + 哨兵 + sticker canvas
                        // 大约这么多 pt，用户视觉"到底"时 offset 距离数学 size 还有 100-200pt
                        geometry.contentOffset.y + geometry.containerSize.height
                            >= geometry.contentSize.height - 200
                    } action: { _, atBottom in
                        isAtBottom = atBottom
                    }
                    .onChange(of: viewModel.isLoading) { _, loading in
                        // 对话加载完成 → 滚到最后一条（applyTreeData 只在搜索跳转时设 scrollToNodeId，
                        // 普通切对话不会自动滚，ScrollView 保留上一对话的 offset，所以要在这里兜底）
                        if !loading, !viewModel.currentPath.isEmpty {
                            // B20 修复：先把 currentPathCount 同步给 stickerVM，再 migrate 飞远的贴纸
                            stickerVM.currentPathCount = viewModel.currentPath.count
                            stickerVM.migrateStickerPositions(context: modelContext)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                scrollToLastMessage(proxy: proxy, force: true)
                            }
                        }
                    }
                    .onChange(of: viewModel.currentPath.count) { _, n in
                        // B20 修复：path 变（新消息进来等）→ 同步给 stickerVM，让 clampStickerY
                        // 在 drag end 时拿到最新 path 长度
                        stickerVM.currentPathCount = n
                    }
                    .onChange(of: viewModel.scrollToNodeId) { _, nodeId in
                        if let nodeId {
                            // 先无动画跳（让 LazyVStack 加载目标），再动画微调
                            proxy.scrollTo(nodeId, anchor: .center)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    proxy.scrollTo(nodeId, anchor: .center)
                                }
                                viewModel.scrollToNodeId = nil
                            }
                        }
                    }
                    .onChange(of: viewModel.streamingText) { oldText, newText in
                        if newText.isEmpty && !oldText.isEmpty {
                            lastStreamingScrollTime = .distantPast
                            scrollToLastMessage(proxy: proxy, force: true)
                            return
                        }
                        guard !newText.isEmpty else { return }
                        // 用户手动上滑时暂停自动滚底，避免弹跳
                        guard isAtBottom else { return }
                        let now = Date()
                        guard now.timeIntervalSince(lastStreamingScrollTime) >= 0.3 else { return }
                        lastStreamingScrollTime = now
                        // 不带动画滚底：避免 withAnimation 与 WebView 高度变化同帧竞争导致白屏
                        var tx = Transaction()
                        tx.disablesAnimations = true
                        withTransaction(tx) {
                            if let lastId = viewModel.currentPath.last?.id {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                    // 编辑贴纸时锁住纵向滚动，否则纵向 pinch 被 ScrollView 吃掉
                    .scrollDisabled(stickerVM.isEditingStickers)
                    .scrollDismissesKeyboard(.immediately)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if showStickerPanel {
                            // 透明占位：把滚动内容推上去，真正的面板在外层 overlay
                            Color.clear.frame(height: 320)
                        } else if stickerVM.isEditingStickers {
                            // 编辑模式：工具栏在 overlay，这里只占位
                            Color.clear.frame(height: 60)
                        } else if let pm = providerManager {
                            VStack(spacing: 0) {
                                // 回底按钮：离底时淡入，占位最小（只在可见时 54pt）
                                if !isAtBottom && !viewModel.currentPath.isEmpty {
                                    HStack {
                                        Spacer()
                                        ScrollToBottomButton(
                                            isVisible: true,
                                            action: { scrollToLastMessage(proxy: proxy, force: true) }
                                        )
                                        .padding(.trailing, 16)
                                    }
                                    .padding(.bottom, 4)
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                                }

                                ChatInputBar(
                                    viewModel: viewModel, modelContext: modelContext,
                                    profileManager: profileManager, providerManager: pm, presetManager: presetManager,
                                    pendingImageData: $pendingImageData,
                                    pendingFileData: $pendingFileData,
                                    pendingFileName: $pendingFileName,
                                    onStickerTap: {
                                        // + 号 → Add to Chat 功能面板（iOS）
                                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                        showAddToChat = true
                                    }
                                )
                                .equatable()
                            }
                            .animation(.easeOut(duration: 0.25), value: isAtBottom)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .animation(.easeInOut(duration: 0.25), value: showStickerPanel)
                    .animation(.easeInOut(duration: 0.25), value: stickerVM.isEditingStickers)
                }

                // 底栏：编辑模式 = 工具栏，普通模式 = 输入框（仅 macOS，iOS 合并在 StickerKeyboardPanel）
            }
            .animation(.easeInOut(duration: 0.25), value: stickerVM.isEditingStickers)
            .overlay(alignment: .bottom) {
                if showStickerPanel || stickerVM.isEditingStickers {
                    StickerKeyboardPanel(
                        stickerVM: stickerVM,
                        viewModel: viewModel,
                        showCard: showStickerPanel,
                        onDismiss: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                if showStickerPanel {
                                    showStickerPanel = false
                                } else {
                                    // 只有工具栏时，键盘按钮 = 退出编辑
                                    stickerVM.isEditingStickers = false
                                    stickerVM.selectedPlacedStickerId = nil
                                }
                            }
                        },
                        onStickerTap: {
                            withAnimation(.easeInOut(duration: 0.25)) { showStickerPanel.toggle() }
                        }
                    )
                    .ignoresSafeArea(.container, edges: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: showStickerPanel)
            .animation(.easeInOut(duration: 0.25), value: stickerVM.isEditingStickers)
            .background {
                // Hidden button for Cmd+F shortcut
                Button("") {
                    showInConvSearch.toggle()
                    if showInConvSearch {
                        inConvSearchFocused = true
                    } else {
                        viewModel.clearInConvSearch()
                    }
                }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
            }
            .onChange(of: viewModel.selectedConversation?.id) { _, convId in
                loadStickersForConversation(convId)
                isAtBottom = true   // 避免上一对话的 false 泄漏到新对话（会让 safeAreaInset 错位）
            }
            .onAppear {
                loadStickersForConversation(viewModel.selectedConversation?.id)
                // 注入贴纸 mutation callback：加/删贴纸时推对话走 3s debounce 重排
                stickerVM.onConversationMutated = { [viewModel] convId in
                    if let conv = viewModel.selectedConversation, conv.id == convId {
                        conv.updateTime = Date()
                        viewModel.markConversationDirty()
                    }
                }
            }
            .toolbarBackground(Theme.mainBg, for: .navigationBar)
            .overlay(alignment: .top) {
                // B20 part 2: transient toast (e.g. "已切换到分支")
                if let notice = viewModel.transientNotice {
                    TransientNoticeCapsule(text: notice.text)
                        .id(notice.id)
                        .padding(.top, 16)
                        .onAppear {
                            let id = notice.id
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                                if viewModel.transientNotice?.id == id {
                                    viewModel.transientNotice = nil
                                }
                            }
                        }
                }
            }
            // Add to Chat 功能面板（+ 号触发）
            // 从 Files App "用 Lost in Blossom 打开" 接收文件
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("incomingFileReceived"))) { notif in
                if let data = notif.userInfo?["data"] as? Data,
                   let name = notif.userInfo?["name"] as? String {
                    pendingFileData = data
                    pendingFileName = name
                }
            }
            .sheet(isPresented: $showAddToChat) {
                AddToChatSheet(
                    onOpenSticker: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showStickerPanel = true
                            stickerVM.isEditingStickers = true
                        }
                    },

                    pendingImageData: $pendingImageData,
                    pendingFileData: $pendingFileData,
                    pendingFileName: $pendingFileName
                )
            }
            .alert("文件添加失败", isPresented: Binding(
                get: { fileErrorMessage != nil },
                set: { if !$0 { fileErrorMessage = nil } }
            )) {
                Button("好的") { fileErrorMessage = nil }
            } message: {
                Text(fileErrorMessage ?? "")
            }
            // 双击消息气泡 → 文本选取 sheet
            .sheet(item: $textSelectItem) { item in
                TextSelectSheet(text: item.text, thinkingText: item.thinkingText)
            }
        }
    }

    // MARK: - Sticker Helpers

    private func loadStickersForConversation(_ convId: String?) {
        stickerVM.bubblePositions.removeAll()
        guard let convId, let pid = profileManager?.currentProfile.id else {
            stickerVM.placedStickers = []
            return
        }
        stickerVM.loadPlacedStickers(conversationId: convId, profileId: pid, context: modelContext)
    }

    private func handleStickerDrop(providers: [NSItemProvider], location: CGPoint) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { data, _ in
            guard let data = data as? Data,
                  let idString = String(data: data, encoding: .utf8),
                  let assetId = UUID(uuidString: idString),
                  let convId = viewModel.selectedConversation?.id,
                  let pid = profileManager?.currentProfile.id else { return }

            let nearestId = findNearestMessageId(y: location.y)
            print("[贴纸定位] drop y=\(location.y), bubblePositions=\(stickerVM.bubblePositions.count)条, nearest=\(nearestId ?? "nil")")

            // 查 asset 类型——便签需要复制 noteContent/noteStyle
            let asset = stickerVM.stickerAssets.first(where: { $0.id == assetId })

            DispatchQueue.main.async {
                if let asset, asset.isNote {
                    stickerVM.placeNote(
                        content: asset.noteContent ?? "",
                        style: asset.noteStyle ?? "yellow_square",
                        conversationId: convId,
                        position: location,
                        nearestMessageId: nearestId,
                        profileId: pid,
                        context: modelContext
                    )
                } else {
                    stickerVM.placeSticker(
                        assetId: assetId,
                        conversationId: convId,
                        position: location,
                        nearestMessageId: nearestId,
                        profileId: pid,
                        context: modelContext
                    )
                }
            }
        }
        return true
    }

    /// 找 Y 坐标最近的消息 ID（用 GeometryReader 测量的真实位置）
    private func findNearestMessageId(y: CGFloat) -> String? {
        guard !stickerVM.bubblePositions.isEmpty else {
            // fallback：没有测量数据时用第一条消息
            return viewModel.currentPath.first?.id
        }
        var bestId: String?
        var bestDist: CGFloat = .greatestFiniteMagnitude
        for (nodeId, centerY) in stickerVM.bubblePositions {
            let dist = abs(centerY - y)
            if dist < bestDist {
                bestDist = dist
                bestId = nodeId
            }
        }
        return bestId
    }
}

// MARK: - In-Conversation Search Bar

struct InConversationSearchBar: View {
    var viewModel: ConversationViewModel
    var focused: FocusState<Bool>.Binding
    var onDismiss: () -> Void
    @State private var keyword: String = ""

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundColor(Theme.textMuted)

            TextField("搜索当前对话...", text: $keyword)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused(focused)
                .onSubmit {
                    viewModel.searchInConversation(keyword: keyword)
                }
                .onChange(of: keyword) { _, newValue in
                    if newValue.isEmpty {
                        viewModel.clearInConvSearch()
                    }
                }

            if !viewModel.inConvMatches.isEmpty {
                Text("\(viewModel.inConvMatchIndex + 1)/\(viewModel.inConvMatches.count)")
                    .font(.caption2)
                    .foregroundColor(Theme.textMuted)
                    .monospacedDigit()

                Button(action: { viewModel.navigateInConvMatch(direction: -1) }) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.branchIndicator)
                }
                .buttonStyle(.plain)

                Button(action: { viewModel.navigateInConvMatch(direction: 1) }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.branchIndicator)
                }
                .buttonStyle(.plain)
            } else if !keyword.isEmpty && viewModel.inConvMatchIndex == -1 {
                Text("无结果")
                    .font(.caption2)
                    .foregroundColor(Theme.textMuted)
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.sidebarBg)
    }
}

// MARK: - Chat Input Bar

struct ChatInputBar: View {
    var viewModel: ConversationViewModel
    var modelContext: ModelContext
    var profileManager: ProfileManager?
    var providerManager: ProviderManager
    var presetManager: PresetManager?
    var pendingImageData: Binding<Data?> = .constant(nil)
    var pendingFileData: Binding<Data?> = .constant(nil)
    var pendingFileName: Binding<String?> = .constant(nil)
    var onStickerTap: (() -> Void)? = nil

    @AppStorage("blurRadius") private var blurRadius = 1.3
    @AppStorage("selectedChatModel") private var selectedModelId = ""
    @State private var showModelPicker = false
    @FocusState private var isFocused: Bool

    private var currentModel: ProviderModel {
        // Try stored selection
        if !selectedModelId.isEmpty, let model = providerManager.model(byId: selectedModelId) {
            return model
        }
        // Fallback to first available model
        return providerManager.availableModels.first ?? ProviderModel(providerId: "openrouter", modelId: "anthropic/claude-sonnet-4", name: "Claude Sonnet 4")
    }

    private var systemPrompt: String? {
        let prompt = profileManager?.currentProfile.systemPrompt ?? ""
        return prompt.isEmpty ? nil : prompt
    }

    private var inputPlaceholder: String {
        "Reply to Caelum"
    }

    var body: some View {
        #if DEBUG
        let _ = {
            PerfCounters.chatInputBarBody += 1
            print(String(format: "[PERF] ChatInputBar.body #%d t=%.3f focused=%@",
                         PerfCounters.chatInputBarBody,
                         CFAbsoluteTimeGetCurrent(),
                         isFocused ? "Y" : "N"))
        }()
        #endif
        // Claude App 风格：InputFieldContainer 自带两层布局（TextEditor + 工具栏），
        // ChatInputBar 只负责外层 padding、环境模糊背景、sheet、alert。
        return InputFieldContainer(
            isFocused: $isFocused,
            isStreaming: viewModel.providerRouter.isStreaming,
            placeholder: inputPlaceholder,
            modelName: currentModel.name,
            pendingImageData: pendingImageData,
            pendingFileData: pendingFileData,
            pendingFileName: pendingFileName,
            onSend: { text in send(text) },
            onCancelStream: { viewModel.providerRouter.cancel() },
            onStickerTap: onStickerTap,
            onModelTap: { showModelPicker.toggle() }
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .padding(.top, 6)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .background(alignment: .bottom) {
            ZStack {
                VariableBlurView(maxBlurRadius: blurRadius, direction: .blurredBottomClearTop)
                LinearGradient(
                    stops: [
                        .init(color: Theme.mainBg.opacity(0), location: 0.0),
                        .init(color: Theme.mainBg.opacity(0.1), location: 0.25),
                        .init(color: Theme.mainBg.opacity(0.3), location: 0.55),
                        .init(color: Theme.mainBg.opacity(0.4), location: 0.72),
                        .init(color: Theme.mainBg.opacity(0.35), location: 0.85),
                        .init(color: Theme.mainBg.opacity(0), location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(height: isFocused ? 80 : 160)
            .offset(y: isFocused ? 10 : 40)
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.25), value: isFocused)
        }
        .sheet(isPresented: $showModelPicker) {
            ModelPickerPopover(
                providerManager: providerManager,
                selectedModelId: currentModel.id
            ) { model in
                selectedModelId = model.id
                providerManager.touchLastUsed(providerId: model.providerId, modelId: model.modelId)
                showModelPicker = false
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            providerManager.resolveStaleSelectedModel()
            providerManager.resolveStaleFavorites()
        }
        .alert("预算保险闸", isPresented: Binding(
            get: { viewModel.budgetBlockedMessage != nil },
            set: { if !$0 { viewModel.budgetBlockedMessage = nil } }
        )) {
            Button("好") { viewModel.budgetBlockedMessage = nil }
        } message: {
            Text(viewModel.budgetBlockedMessage ?? "")
        }
    }

    /// 返回 true 表示发送成功（子 view 应清空 text），false = 预算被拦（text 保留）
    private func send(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageData = pendingImageData.wrappedValue
        let fileData = pendingFileData.wrappedValue
        let fileName = pendingFileName.wrappedValue
        guard !trimmed.isEmpty || imageData != nil || fileData != nil else { return false }

        let prof = profileManager?.currentProfile ?? Profile(name: "", emoji: "", description: "", userName: "你", assistantName: "AI")
        let preset = presetManager?.preset(byId: prof.presetId) ?? Preset.balanced

        // 预算 pre-check：被拦时返回 false，子 view 保留 text
        guard viewModel.preCheckBudget(
            text: trimmed,
            model: currentModel,
            profile: prof,
            preset: preset,
            providerManager: providerManager
        ) else { return false }

        // globalWorldBookEntries 已由 ContentView 同步
        viewModel.sendMessage(trimmed, imageData: imageData, fileData: fileData, fileName: fileName, model: currentModel, profile: prof, preset: preset, providerManager: providerManager, context: modelContext)
        pendingImageData.wrappedValue = nil
        pendingFileData.wrappedValue = nil
        pendingFileName.wrappedValue = nil
        return true
    }
}

// MARK: - ChatInputBar Equatable (B3 性能优化)
//
// 目的：流式响应期间 CardFlowView body 因读 viewModel.providerRouter.streamingText 每
// token 重算 → ContentView.iOSLayout 重算 → PagingContainerView.updatePages 无条件
// 大锤 → child HC.rootView 替换 → ChatInputBar 整棵重 diff（log 实测 326 次 / 19 次
// ContentView.body，放大 17×）。
//
// EquatableView 拦下"父重建传来的 instance 相等" case，body 跳过。@FocusState /
// @State / @AppStorage / @Observable 的 invalidation 走独立通路，focus/打字/流式
// isStreaming/切对话 的响应都还在。
//
// 5 个 class ref 跨 session 稳定，切楼层由 ContentView.id(profile.id) 重建整棵 →
// ref 全换 → == false → 重算。onStickerTap 闭包 nil/non-nil 二值：iOS 永远 non-nil、
// macOS 永远 nil，当前代码下 behavior 稳定；若未来 closure 变条件性，需加 UUID signal。
//
// Research: docs/research-chatinputbar-equatable.md
extension ChatInputBar: Equatable {
    static func == (lhs: ChatInputBar, rhs: ChatInputBar) -> Bool {
        lhs.viewModel === rhs.viewModel
            && lhs.modelContext === rhs.modelContext
            && lhs.profileManager === rhs.profileManager
            && lhs.providerManager === rhs.providerManager
            && lhs.presetManager === rhs.presetManager
            && (lhs.onStickerTap == nil) == (rhs.onStickerTap == nil)
            && (lhs.pendingImageData.wrappedValue != nil) == (rhs.pendingImageData.wrappedValue != nil)
            && (lhs.pendingFileData.wrappedValue != nil) == (rhs.pendingFileData.wrappedValue != nil)
    }
}

// MARK: - InputFieldContainer — 独立子 view 持有 inputText
//
// 把 inputText + TextField + Send Button + glassEffect 封装成 fileprivate 子 view，
// 打字时只重建这个子 view（~80ms），外层 ChatInputBar（底部按钮行 / VariableBlurView /
// sheet / alert）不受影响。粟粟 2026-04-19 log 实测 150-170ms/字 → 预期 ≤80ms/字。

/// Claude App 风格两层输入框：
/// 上层 TextEditor（多行，placeholder）+ 下层工具栏（+ 号 | 模型 ▾ | Spacer | 语音/发送）
private struct InputFieldContainer: View {
    @State private var text: String = ""
    @State private var inputTextHeight: CGFloat = 36  // starts single-line, grows to ≤120
    @FocusState.Binding var isFocused: Bool
    let isStreaming: Bool
    let placeholder: String
    let modelName: String
    @Binding var pendingImageData: Data?
    @Binding var pendingFileData: Data?
    @Binding var pendingFileName: String?
    let onSend: (String) -> Bool
    let onCancelStream: () -> Void
    let onStickerTap: (() -> Void)?
    let onModelTap: () -> Void

    private var canSend: Bool {
        isStreaming || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pendingImageData != nil || pendingFileData != nil
    }
    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pendingImageData != nil || pendingFileData != nil
    }

    var body: some View {
        #if DEBUG
        let _ = {
            PerfCounters.inputFieldBody += 1
            print(String(format: "[PERF] InputFieldContainer.body #%d t=%.3f len=%d",
                         PerfCounters.inputFieldBody,
                         CFAbsoluteTimeGetCurrent(),
                         text.count))
        }()
        #endif
        return VStack(spacing: 0) {
            // ── 图片预览行（pendingImageData 非 nil 时显示）──────────────
            if let imgData = pendingImageData, let uiImg = UIImage(data: imgData) {
                HStack(spacing: 8) {
                    Image(uiImage: uiImg)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Text("photo.jpg")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textMuted)
                    Spacer()
                    Button {
                        pendingImageData = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(Theme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Divider().padding(.horizontal, 12)
            }
            // ── PDF 预览行（pendingFileData 非 nil 时显示）────────────────
            if pendingFileData != nil {
                HStack(spacing: 8) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.red.opacity(0.8))
                        .frame(width: 60, height: 60)
                    Text(pendingFileName ?? "document.pdf")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        pendingFileData = nil
                        pendingFileName = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(Theme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Divider().padding(.horizontal, 12)
            }
            // ── 上层：多行文本输入 ──────────────────────────────────────
            ZStack(alignment: .topLeading) {
                // 隐藏的 Text 尺寸镜像 — 计算 TextEditor 应有的高度
                // Text 和 TextEditor 同字号，高度近似一致，用 GeometryReader 实测
                Text(text.isEmpty ? " " : text)
                    .font(.system(size: 15))
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 9)
                    .padding(.leading, 5)
                    .hidden()
                    .background(
                        GeometryReader { geo in
                            Color.clear.onChange(of: geo.size.height, initial: true) { _, h in
                                let clamped = max(36, min(120, h + 4))
                                if abs(clamped - inputTextHeight) > 1 { inputTextHeight = clamped }
                            }
                        }
                    )
                // placeholder（TextEditor 没有原生 placeholder）
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 15))
                        .foregroundColor(Theme.textMuted.opacity(0.45))
                        .padding(.top, 9)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(.system(size: 15))
                    .scrollContentBackground(.hidden)
                    .frame(height: inputTextHeight)
                    .focused($isFocused)
                    #if DEBUG
                    .onChange(of: text) { _, newVal in
                        print(String(format: "[PERF] TextEditor onChange len=%d t=%.3f", newVal.count, CFAbsoluteTimeGetCurrent()))
                    }
                    #endif
            }
            .animation(.easeInOut(duration: 0.1), value: inputTextHeight)
            .padding(.horizontal, 10)
            .padding(.top, 4)

            // ── 下层：工具栏 ────────────────────────────────────────────
            HStack(spacing: 4) {
                // + 号按钮
                if let onStickerTap {
                    Button(action: onStickerTap) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(Theme.textMuted)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                // 模型选择标签
                Button(action: onModelTap) {
                    HStack(spacing: 4) {
                        Text(modelName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.textSecondary)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                            .foregroundColor(Theme.textMuted.opacity(0.7))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Theme.textMuted.opacity(0.08)))
                }
                .buttonStyle(.plain)

                Spacer()

                // 语音占位（空文本）/ 发送 / 停止 按钮
                ZStack {
                    if hasText || isStreaming {
                        // 有文本 或 正在流式：显示发送 / 停止圆形按钮
                        Button(action: triggerSend) {
                            Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                                .contentTransition(.symbolEffect(.replace))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(canSend ? .white : Theme.textMuted)
                                .frame(width: 30, height: 30)
                                .background(
                                    Circle()
                                        .fill(
                                            isStreaming ? Theme.danger :
                                            canSend     ? Color.black  :
                                                          Theme.textMuted.opacity(0.15)
                                        )
                                        .animation(.easeInOut(duration: 0.15), value: isStreaming)
                                        .animation(.easeInOut(duration: 0.15), value: canSend)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSend)
                        .transition(.scale.combined(with: .opacity))
                    } else {
                        // 空文本：显示语音占位按钮（暂无功能）
                        Button(action: {}) {
                            Image(systemName: "waveform.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.black)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: hasText || isStreaming)
                .padding(.trailing, 4)
            }
            .frame(height: 44)
            .padding(.horizontal, 6)
        }
        // 圆角矩形卡片，跟聊天背景同色 + 细边框
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Theme.mainBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(Theme.textMuted.opacity(0.14), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        )
        .contentShape(RoundedRectangle(cornerRadius: 22))
        .onTapGesture { isFocused = true }
    }

    private func triggerSend() {
        if isStreaming { onCancelStream(); return }
        HapticService.shared.sendMessage()
        if onSend(text) { text = "" }
    }
}

// MARK: - Model Picker Popover

struct ModelPickerPopover: View {
    let providerManager: ProviderManager
    let selectedModelId: String
    let onSelect: (ProviderModel) -> Void

    /// 优先显示收藏；收藏为空时 fallback 展示所有 enabled provider 的 models + 顶部提示。
    private var groupedSource: (items: [(APIProvider, [ProviderModel])], isFallback: Bool) {
        let favs = providerManager.favoritesByProvider
        if !favs.isEmpty {
            return (favs, false)
        }
        return (providerManager.enabledProviders.map { ($0, $0.models) }, true)
    }

    var body: some View {
        let source = groupedSource

        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if source.isFallback && !source.items.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "star")
                            .font(.system(size: Theme.F.caption))
                        Text("在 API 设置点 ★ 收藏常用模型")
                            .font(.system(size: Theme.F.caption))
                    }
                    .foregroundColor(Theme.textMuted)
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                }

                ForEach(source.items, id: \.0.id) { pair in
                    let provider = pair.0
                    let models = pair.1

                    Text(provider.name)
                        .font(.system(size: Theme.F.caption, weight: .semibold))
                        .foregroundColor(Theme.textMuted)
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                        .padding(.bottom, 2)

                    ForEach(models, id: \.id) { model in
                        let isSelected = model.id == selectedModelId
                        Button {
                            onSelect(model)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: Theme.F.body))
                                    .foregroundColor(isSelected ? Theme.branchIndicator : Theme.textMuted.opacity(0.5))
                                Text(model.name)
                                    .font(.system(size: Theme.F.body))
                                    .foregroundColor(Theme.textPrimary)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, Theme.optionRowVerticalPadding)
                            .contentShape(Rectangle())
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isSelected ? Theme.accent.opacity(0.4) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if source.items.isEmpty {
                    Text("请先在设置中添加 API Key")
                        .font(.system(size: Theme.F.caption))
                        .foregroundColor(Theme.textMuted)
                        .padding(12)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Thinking UI

/// 思考进行中的呼吸动画标签
struct ThinkingBreathLabel: View {
    @State private var breathPhase = false

    var body: some View {
        Text("思考中…")
            .opacity(breathPhase ? 0.35 : 1.0)
            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: breathPhase)
            .onAppear { breathPhase = true }
    }
}

/// 思考内容底部 sheet（Claude App 风格）
struct ThinkingPanelView: View {
    let thinkingText: String
    let isThinking: Bool

    @State private var animateProgress = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Spacer()
                Text("Thought process")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Image(systemName: "xmark")
                    .font(.system(size: 16))
                    .hidden()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            // 思考进行中：橙色流动进度线
            if isThinking {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.orange)
                        .frame(width: geo.size.width * 0.3, height: 2)
                        .offset(x: animateProgress
                            ? geo.size.width * 0.7
                            : -geo.size.width * 0.3)
                        .animation(
                            .linear(duration: 1.5).repeatForever(autoreverses: false),
                            value: animateProgress
                        )
                        .onAppear { animateProgress = true }
                }
                .frame(height: 2)
                .clipped()
            }

            // 思考全文
            ScrollView {
                Text(thinkingText)
                    .font(.system(size: 15))
                    .lineSpacing(7.5)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
    }
}

// MARK: - Multimodal User Bubble

private struct MultimodalUserBubble: View {
    let content: String
    let fontScale: Double
    let lineSpacingScale: Double

    @State private var showFullImage = false

    private struct ContentBlock {
        var imageData: Data?
        var documentTitle: String?
        var text: String = ""
    }

    private var parsed: ContentBlock {
        var block = ContentBlock()
        guard let data = content.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            block.text = content
            return block
        }
        for item in arr {
            let type = item["type"] as? String ?? ""
            if type == "image", let source = item["source"] as? [String: Any],
               let b64 = source["data"] as? String,
               let imgData = Data(base64Encoded: b64) {
                block.imageData = imgData
            } else if type == "document" {
                block.documentTitle = item["title"] as? String ?? "document.pdf"
            } else if type == "text" {
                block.text = item["text"] as? String ?? ""
            }
        }
        return block
    }

    var body: some View {
        let block = parsed
        VStack(alignment: .leading, spacing: 6) {
            if let imgData = block.imageData, let uiImg = UIImage(data: imgData) {
                Image(uiImage: uiImg)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture { showFullImage = true }
                    .fullScreenCover(isPresented: $showFullImage) {
                        ZStack(alignment: .topTrailing) {
                            Color.black.ignoresSafeArea()
                            Image(uiImage: uiImg)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            Button {
                                showFullImage = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.white)
                                    .padding(16)
                            }
                            .buttonStyle(.plain)
                        }
                    }
            }
            if let title = block.documentTitle {
                HStack(spacing: 6) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.red.opacity(0.8))
                    Text(title)
                        .font(FontManager.font(size: 13))
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Theme.textMuted.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if !block.text.isEmpty {
                Text(block.text)
                    .font(FontManager.font(size: 13.5))
                    .foregroundColor(Theme.textPrimary)
                    .textSelection(.enabled)
                    .lineSpacing(4 * (fontScale > 0 ? fontScale : 1.0) * lineSpacingScale)
            }
        }
    }
}

// MARK: - Branch Info (value type passed to BubbleView)

struct BranchInfo {
    let displayedNodeId: String
    let branchNodeId: String
    let branchCount: Int
    let branchChildren: [(index: Int, node: MessageNode, isMainPath: Bool)]
}

// MARK: - Chat Bubble

struct BubbleView: View {
    let node: MessageNode
    let hasBranches: Bool
    let branchInfo: BranchInfo?
    var isStreaming: Bool = false
    /// True while the model is still generating reasoning_content (thinking phase)
    var isThinking: Bool = false
    /// Live reasoning tokens from ViewModel — only populated for the currently streaming node
    var streamingThinkingText: String = ""
    /// One-sentence summary generated after thinking phase ends; empty until summary arrives
    var thinkingSummary: String = ""
    var isHighlighted: Bool = false
    var isSearchMatch: Bool = false
    /// 当前对话路径的最后一条 assistant 消息。CC 思考链（latestThinking）只挂在这条气泡上。
    var isLastAssistant: Bool = false
    /// 当前选中的 provider 是否为 CC Bridge——只有此条件为 true 时才展示 CCThinkingView。
    var isCCBridgeProvider: Bool = false
    let onToggleFavorite: () -> Void
    let onTogglePin: () -> Void
    let onSoftDelete: () -> Void
    let onSwitchBranch: (String, Int) -> Void
    var onRegenerate: (() -> Void)? = nil
    var onEdit: ((String) -> Void)? = nil
    var regexScripts: [RegexScript] = []

    @Environment(\.modelContext) private var modelContext
    @AppStorage("userName") private var userName = "你"
    @AppStorage("assistantName") private var assistantName = "助手"
    @AppStorage("selectedFont") private var selectedFont = ""
    @AppStorage("fontScale") private var fontScale = 1.2
    @AppStorage("expandAllMessages") private var expandAllMessages = false
    // 气泡外观自定义（DisclosureGroup "气泡外观（高级）"）
    @AppStorage("bubbleCornerRadius") private var bubbleCornerRadius: Double = 16
    @AppStorage("bubblePaddingH") private var bubblePaddingH: Double = 18
    @AppStorage("bubblePaddingV") private var bubblePaddingV: Double = 15
    @AppStorage("lineSpacingScale") private var lineSpacingScale: Double = 1.45
    @AppStorage("paragraphSpacingScale") private var paragraphSpacingScale: Double = 1.65
    @AppStorage("hideTimestamp") private var hideTimestamp: Bool = false
    @AppStorage("hideRoleName") private var hideRoleName: Bool = false
    @AppStorage("hideActionBar") private var hideActionBar: Bool = true
    @AppStorage("hideAssistantBubble") private var hideAssistantBubble: Bool = false
    @AppStorage("thinkingPreviewMode") private var thinkingPreviewMode: String = "summary"
    @State private var isExpanded = false
    @State private var showBranchPicker = false
    @State private var showFolderPicker = false
    @State private var thinkingExpanded = false
    @State private var thinkingShowFull = false  // "Show more" 控制
    @State private var showArtifactCanvas = false
    @State private var detectedArtifact: ArtifactContent? = nil
    @State private var messageWebViewHeight: CGFloat = 44
    @State private var isSelectingText = false
    @State private var isEditing = false
    @State private var editText = ""
    @State private var highlightOpacity: Double = 0
    private let truncateLength = 300

    var isUser: Bool { node.role == "user" }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 3) {
            // Role label + time（两个都隐藏时整行不 render，避免空 HStack 占位）
            if !hideRoleName || !hideTimestamp {
                HStack(spacing: 4) {
                    if !hideRoleName {
                        Text(isUser ? userName : assistantName)
                            .font(.caption2.weight(.medium))
                            .foregroundColor(Theme.textMuted)
                    }
                    if !hideTimestamp, let time = node.createTime {
                        Text(time.formatted(.dateTime.month().day().hour().minute()))
                            .font(.caption2)
                            .foregroundColor(Theme.textMuted.opacity(0.6))
                    }
                }
                .padding(.horizontal, 4)
            }

            // Bubble
            VStack(alignment: .leading, spacing: 6) {
                let rawCleaned = ContentCleaner.clean(node.content, cacheKey: "\(node.id)_\(node.content.count)")
                let thinkingResult = isUser ? nil : ContentCleaner.extractThinking(from: rawCleaned)
                let cleaned = thinkingResult?.content ?? rawCleaned
                // CC 思考链：content 已嵌入 [thinking]…[/thinking] 时由下方 ThinkingBlockView 渲染；
                // 只有 streaming 中 content 尚未嵌入时才用 CCThinkingView（isLastAssistant 限定）。
                // isCCBridgeProvider 防止切换 provider 后 latestThinking 残留导致重复显示。
                if !isUser, isLastAssistant, isCCBridgeProvider,
                   CCBridgeWebSocketClient.shared.isConnected,
                   let ccThinking = CCBridgeWebSocketClient.shared.latestThinking,
                   (thinkingResult?.thinking ?? "").isEmpty {
                    CCThinkingView(block: ccThinking)
                }
                let shouldTruncate = !expandAllMessages && !isExpanded && cleaned.count > truncateLength

                if isUser {
                    if isEditing {
                        VStack(alignment: .trailing, spacing: 6) {
                            TextField("编辑消息...", text: $editText, axis: .vertical)
                                .textFieldStyle(.plain)
                                .font(FontManager.font(size: 13.5))
                                .lineLimit(1...10)
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Theme.mainBg)
                                )
                            HStack(spacing: 8) {
                                Button("取消") {
                                    isEditing = false
                                }
                                .font(.caption)
                                .foregroundColor(Theme.textMuted)
                                .buttonStyle(.plain)

                                Button("提交") {
                                    let text = editText.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !text.isEmpty {
                                        onEdit?(text)
                                    }
                                    isEditing = false
                                }
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Theme.branchIndicator))
                                .buttonStyle(.plain)
                            }
                        }
                    } else if let segs = node.segments, !segs.isEmpty {
                        // Claude v2 导入的 user 消息（通常只有 text + 末尾 attachment/file 段）
                        MessageSegmentsView(
                            segments: segs,
                            selectedFont: selectedFont,
                            fontScale: fontScale,
                            lineSpacingScale: lineSpacingScale,
                            paragraphSpacingScale: paragraphSpacingScale,
                            regexScripts: regexScripts,
                            isUser: true
                        )
                    } else if node.contentType == "multimodal_text" {
                        MultimodalUserBubble(
                            content: node.content,
                            fontScale: fontScale,
                            lineSpacingScale: lineSpacingScale
                        )
                    } else {
                        Text(shouldTruncate ? String(cleaned.prefix(truncateLength)) + "..." : cleaned)
                            .font(FontManager.font(size: 13.5))
                            .foregroundColor(Theme.textPrimary)
                            .textSelection(.enabled)
                            .lineSpacing(4 * (fontScale > 0 ? fontScale : 1.0) * lineSpacingScale)
                    }
                } else if let segs = node.segments, !segs.isEmpty {
                    // Claude v2 导入：按段渲染（每段独立折叠，顺序严格）
                    MessageSegmentsView(
                        segments: segs,
                        selectedFont: selectedFont,
                        fontScale: fontScale,
                        lineSpacingScale: lineSpacingScale,
                        paragraphSpacingScale: paragraphSpacingScale,
                        regexScripts: regexScripts
                    )
                } else {
                    // Thinking block — Claude App 风格小字预览 + 点击弹底部 sheet
                    let liveThinking = isStreaming && !streamingThinkingText.isEmpty
                    let staticThinking = thinkingResult?.thinking ?? ""
                    let hasThinkingContent = liveThinking || !staticThinking.isEmpty
                    if hasThinkingContent && thinkingPreviewMode != "hidden" {
                        let displayThinking = liveThinking ? streamingThinkingText : staticThinking
                        let rawPreview = String(displayThinking.prefix(40)) + (displayThinking.count > 40 ? "…" : "")
                        let previewStr = thinkingPreviewMode == "prefix" ? rawPreview : (thinkingSummary.isEmpty ? rawPreview : thinkingSummary)
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                thinkingExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "clock")
                                    .font(.system(size: 11))
                                if liveThinking && isThinking {
                                    ThinkingBreathLabel()
                                } else {
                                    Text(previewStr)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                                Spacer()
                                Image(systemName: thinkingExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 9))
                            }
                            .font(.system(size: 13))
                            .foregroundColor(Color(red: 155/255.0, green: 142/255.0, blue: 126/255.0))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        // 内联展开区域（替代原 ThinkingPanelView sheet）
                        // 空白框 bug 修复：thinking 为空（trim 后）不渲染任何内容
                        if thinkingExpanded {
                            let thinkingText = liveThinking ? streamingThinkingText : staticThinking
                            if !thinkingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                HStack(alignment: .top, spacing: 8) {
                                    Rectangle()
                                        .fill(Theme.textMuted.opacity(0.2))
                                        .frame(width: 2)

                                    VStack(alignment: .leading, spacing: 4) {
                                        let display = thinkingShowFull ? thinkingText : String(thinkingText.prefix(300))
                                        Text(display)
                                            .font(.system(size: 12))
                                            .foregroundColor(Theme.textMuted)
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        // 超过 300 字 → 渐变淡出 + Show more / Show less
                                        if thinkingText.count > 300 {
                                            Button(thinkingShowFull ? "Show less" : "Show more") {
                                                withAnimation(.easeInOut(duration: 0.15)) {
                                                    thinkingShowFull.toggle()
                                                }
                                            }
                                            .font(.system(size: 11))
                                            .foregroundColor(Theme.branchIndicator)
                                            .buttonStyle(.plain)
                                        }

                                        // Done 标记（非流式时）
                                        if !isThinking {
                                            HStack(spacing: 4) {
                                                Image(systemName: "checkmark.circle")
                                                    .font(.system(size: 11))
                                                Text("Done")
                                                    .font(.system(size: 11))
                                            }
                                            .foregroundColor(Theme.textMuted.opacity(0.5))
                                        }
                                    }
                                }
                                .padding(.leading, 4)
                                .padding(.top, 4)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                    }

                    // Assistant content — 正则脚本渲染替换
                    let artifactForCard: ArtifactContent? = (!isUser && !isStreaming) ? ArtifactDetector.find(in: cleaned) : nil
                    let cleanedForDisplay = artifactForCard != nil ? ArtifactDetector.stripFirst(in: cleaned) : cleaned
                    let rawDisplay = shouldTruncate ? String(cleanedForDisplay.prefix(truncateLength)) + "\n\n..." : cleanedForDisplay
                    let displayText = node.role == "assistant" && !regexScripts.isEmpty
                        ? RegexEngine.apply(scripts: regexScripts, text: rawDisplay, messagePlacement: 2, isMarkdown: true)
                        : rawDisplay
                    if displayText.isEmpty && isStreaming {
                        HStack(spacing: 4) {
                            ForEach(0..<3, id: \.self) { i in
                                Circle()
                                    .fill(Theme.textMuted.opacity(0.5))
                                    .frame(width: 5, height: 5)
                            }
                        }
                        .padding(.vertical, 4)
                    } else if !displayText.isEmpty {
                        let needsWebView = displayText.contains("{color:") || displayText.contains("||")
                        if needsWebView {
                            // 富文本消息：WebView 渲染（保留 {color:} 支持）
                            MessageContentWebView(
                                content: displayText,
                                themeColors: [
                                    "text-color": Theme.textPrimary.toHex(),
                                    "text-muted": Theme.textMuted.toHex(),
                                    "code-bg": Theme.mainBg.toHex(),
                                    "link-color": Theme.accent.toHex(),
                                    "spoiler-bg": Theme.textMuted.toHex(),
                                    "font-size": "\(13.5 * (fontScale > 0 ? fontScale : 1.0))px",
                                    "line-height": "\(1.5 * lineSpacingScale)"
                                ],
                                dynamicHeight: $messageWebViewHeight
                            )
                            .frame(height: max(44, min(messageWebViewHeight, UIScreen.main.bounds.height * 1.5)))
                        } else {
                            // 普通消息：MarkdownUI 渲染（纯 SwiftUI，零白屏）
                            Markdown(displayText)
                                .markdownTheme(
                                    .memoryPalace(
                                        fontName: selectedFont,
                                        scale: CGFloat(fontScale > 0 ? fontScale : 1.0),
                                        lineSpacingScale: CGFloat(lineSpacingScale),
                                        paragraphSpacingScale: CGFloat(paragraphSpacingScale)
                                    )
                                )
                                .textSelection(.enabled)
                        }
                    }
                }

                // Artifact canvas card (assistant only, not during streaming)
                if !isUser && !isStreaming, let artifact = ArtifactDetector.find(in: cleaned) {
                    ArtifactCodeFoldView(
                        code: artifact.code,
                        language: artifact.type.label
                    )
                    ArtifactCardView(artifact: artifact) {
                        detectedArtifact = artifact
                        showArtifactCanvas = true
                    }
                }

                if !expandAllMessages && cleaned.count > truncateLength {
                    // 按钮出现时才挂 HStack，避免空 HStack 吃掉 VStack 的
                    // spacing: 6（上下共 12pt）造成气泡底部多一截留白。
                    HStack(spacing: 8) {
                        Button(isExpanded ? "收起" : "展开全文") {
                            isExpanded.toggle()
                        }
                        .font(.caption)
                        .foregroundColor(Theme.branchIndicator)
                        .buttonStyle(.plain)
                    }
                }

                // Branch indicator
                if hasBranches, let info = branchInfo {
                    BranchIndicator(
                        info: info,
                        showPicker: $showBranchPicker,
                        onSwitchBranch: onSwitchBranch
                    )
                }
            }
            .padding(.horizontal, bubblePaddingH)
            .padding(.vertical, bubblePaddingV)
            .background(
                RoundedRectangle(cornerRadius: bubbleCornerRadius)
                    .fill(isUser ? Theme.userBubble : (hideAssistantBubble ? Color.clear : Theme.assistantBubble))
            )
            .overlay(
                RoundedRectangle(cornerRadius: bubbleCornerRadius)
                    .fill(Theme.branchIndicator.opacity(0.2 * highlightOpacity))
                    .allowsHitTesting(false)
            )
            .overlay(
                RoundedRectangle(cornerRadius: bubbleCornerRadius)
                    .stroke(Theme.branchIndicator.opacity(isSearchMatch ? 0.6 : 0), lineWidth: 1.5)
                    .allowsHitTesting(false)
            )
            .overlay {
                if isSelectingText {
                    VStack(spacing: 0) {
                        HStack {
                            Text("选取文本")
                                .font(.caption)
                                .foregroundColor(Theme.textMuted)
                            Spacer()
                            Button("完成") { isSelectingText = false }
                                .font(.caption.bold())
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

                        SelectableTextOverlay(
                            text: ContentCleaner.clean(node.content, cacheKey: node.id),
                            font: .systemFont(ofSize: 13.5 * CGFloat(fontScale > 0 ? fontScale : 1.0)),
                            textColor: UIColor(Theme.textPrimary),
                            isActive: $isSelectingText
                        )
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(UIColor.systemBackground).opacity(0.97))
                            .shadow(radius: 4)
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .animation(.easeOut(duration: 0.2), value: isSelectingText)
                }
            }
            .onChange(of: isHighlighted) { _, highlighted in
                if highlighted {
                    withAnimation(.easeIn(duration: 0.3)) { highlightOpacity = 1 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation(.easeOut(duration: 0.5)) { highlightOpacity = 0 }
                    }
                }
            }
            .if(isUser) { view in
                view.frame(maxWidth: 500, alignment: .trailing)
            }
            .contextMenu {
                if isUser, onEdit != nil {
                    Button(action: {
                        editText = node.content
                        isEditing = true
                    }) {
                        Label("编辑", systemImage: "pencil")
                    }
                    Divider()
                }
                if !isUser, let onRegenerate, !isStreaming {
                    Button(action: onRegenerate) {
                        Label("重新生成", systemImage: "arrow.counterclockwise")
                    }
                    Divider()
                }
                Button(action: onToggleFavorite) {
                    Label(node.isFavorite ? "取消收藏" : "收藏", systemImage: node.isFavorite ? "star.slash" : "star")
                }
                Button(action: { showFolderPicker = true }) {
                    Label("收藏到文件夹...", systemImage: "folder.badge.plus")
                }
                Button(action: onTogglePin) {
                    Label(node.isPinned ? "取消钉住" : "钉住", systemImage: node.isPinned ? "pin.slash" : "pin")
                }
                Divider()
                Button(action: {
                    UIPasteboard.general.string = ContentCleaner.clean(node.content, cacheKey: node.id)
                }) {
                    Label("复制文本", systemImage: "doc.on.doc")
                }
                Button(action: { isSelectingText = true }) {
                    Label("选取文本", systemImage: "text.cursor")
                }
                Divider()
                Button(role: .destructive, action: onSoftDelete) {
                    Label("删除", systemImage: "trash")
                }
            }

            // Hover action buttons — macOS only（iOS 用 context menu 代替）

            // iOS action bar: copy / TTS / regenerate (controlled by hideActionBar setting)
            if !hideActionBar {
                HStack(spacing: 16) {
                    // Copy
                    Button {
                        UIPasteboard.general.string = ContentCleaner.clean(node.content, cacheKey: node.id)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textMuted)
                    }
                    .buttonStyle(.plain)

                    // Regenerate (assistant only, not streaming)
                    if !isUser, let onRegenerate, !isStreaming {
                        Button(action: onRegenerate) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 13))
                                .foregroundColor(Theme.textMuted)
                        }
                        .buttonStyle(.plain)
                    }

                    // Favorite
                    Button(action: onToggleFavorite) {
                        Image(systemName: node.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 13))
                            .foregroundColor(node.isFavorite ? Theme.favorite : Theme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            HapticService.shared.copyText()
        }
        // 注意：删了 .contentShape(Rectangle())。它会把 contextMenu 命中区扩到整 row 宽
        // (maxWidth: .infinity)，导致 row 空白区 (input bar 后渗 / home indicator 上方那带)
        // 点击都触发 contextMenu。删后命中区缩到气泡视觉本身（line 1238 的 RoundedRectangle），
        // 即 .contextMenu 自己附着的那个 view 的 frame。
        .sheet(isPresented: $showFolderPicker) {
            FolderPickerSheet(node: node, profileId: node.profileId)
        }
        .sheet(isPresented: $showArtifactCanvas) {
            if let artifact = detectedArtifact {
                ArtifactCanvasSheet(artifact: artifact)
            }
        }
    }
}

// MARK: - Hover Buttons (isolated state)

/// Separate view for hover buttons so hover state changes don't re-render the entire bubble
struct HoverButtons: View {
    let isFavorite: Bool
    let isPinned: Bool
    let onCopy: () -> Void
    let onToggleFavorite: () -> Void
    let onTogglePin: () -> Void
    let onSoftDelete: () -> Void
    var onEdit: (() -> Void)? = nil
    var onRegenerate: (() -> Void)? = nil
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            if let onEdit {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
            }

            if let onRegenerate {
                Button(action: onRegenerate) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
            }

            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)

            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 13))
                    .foregroundColor(isFavorite ? Theme.favorite : Theme.textMuted)
            }
            .buttonStyle(.plain)

            Button(action: onTogglePin) {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 13))
                    .foregroundColor(isPinned ? Theme.branchIndicator : Theme.textMuted)
            }
            .buttonStyle(.plain)

            Button(action: onSoftDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(Theme.textMuted)
        .padding(.horizontal, 4)
        .padding(.top, 2)
        .contentShape(Rectangle())
    }
}

// MARK: - Tag Picker Sheet

struct FolderPickerSheet: View {
    let node: MessageNode
    let profileId: String
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var tags: [ConversationTag]
    @State private var newTagName = ""

    init(node: MessageNode, profileId: String) {
        self.node = node
        self.profileId = profileId
        _tags = Query(
            filter: #Predicate<ConversationTag> { $0.profileId == profileId },
            sort: \ConversationTag.order
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("收藏到标签")
                .font(.headline)
                .foregroundColor(Theme.textPrimary)

            if tags.isEmpty {
                Text("还没有标签，先创建一个吧")
                    .font(.caption)
                    .foregroundColor(Theme.textMuted)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(tags) { tag in
                            Button(action: {
                                let item = FavoriteItem(nodeId: node.id, conversationId: node.conversationId, tagId: tag.id, contentPreview: String(node.content.prefix(100)), profileId: profileId)
                                modelContext.insert(item)
                                dismiss()
                            }) {
                                HStack {
                                    Text(tag.emoji)
                                    Text(tag.name)
                                        .font(.system(size: 13))
                                        .foregroundColor(Theme.textPrimary)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Theme.accent.opacity(0.3))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                .frame(maxHeight: 200)
            }

            Divider()

            HStack {
                TextField("新建标签名...", text: $newTagName)
                    .textFieldStyle(.plain)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.accent.opacity(0.3)))

                Button("创建") {
                    guard !newTagName.isEmpty else { return }
                    let tag = ConversationTag(name: newTagName, order: tags.count, profileId: profileId)
                    modelContext.insert(tag)
                    newTagName = ""
                }
                .disabled(newTagName.isEmpty)
            }

            Button("取消") { dismiss() }
                .foregroundColor(Theme.textMuted)
        }
        .padding(20)
        .frame(width: 300)
    }
}

// MARK: - Conditional Modifier

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Branch Indicator

struct BranchIndicator: View {
    let info: BranchInfo
    @Binding var showPicker: Bool
    let onSwitchBranch: (String, Int) -> Void
    @AppStorage("userName") private var userName = "你"
    @AppStorage("assistantName") private var assistantName = "助手"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: { showPicker.toggle() }) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10))
                    Text("\(info.branchCount) 条分支")
                        .font(.system(size: 11))
                }
                .foregroundColor(Theme.branchIndicator)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Theme.branchIndicator.opacity(0.12))
                )
            }
            .buttonStyle(.plain)

            if showPicker {
                VStack(spacing: 3) {
                    ForEach(info.branchChildren, id: \.index) { branch in
                        Button(action: {
                            onSwitchBranch(info.branchNodeId, branch.index)
                            showPicker = false
                        }) {
                            HStack(spacing: 6) {
                                if branch.isMainPath {
                                    Image(systemName: "star.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(Theme.favorite)
                                }

                                Text(branch.node.role == "user" ? userName : assistantName)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(Theme.textSecondary)

                                Text(String(ContentCleaner.clean(branch.node.content, cacheKey: branch.node.id).prefix(60)))
                                    .font(.system(size: 10))
                                    .foregroundColor(Theme.textMuted)
                                    .lineLimit(1)

                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Theme.accent.opacity(0.5))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - TagPickerPopover（聊天页 nav ⋯ Menu 的"改标签"sheet）
//
// 学 ModelPickerPopover 的结构：List 展示所有 tag，每项 tap toggle 当前对话的
// tag 归属。底层数据是 ConversationTag + FavoriteItem join（nodeId == nil 代表
// 对话级 tag，区别于 bubble 收藏）。

struct TagPickerPopover: View {
    let conversationId: String
    let profileId: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var tags: [ConversationTag]
    @Query private var favoriteItems: [FavoriteItem]

    init(conversationId: String, profileId: String) {
        self.conversationId = conversationId
        self.profileId = profileId
        _tags = Query(
            filter: #Predicate<ConversationTag> { $0.profileId == profileId },
            sort: \ConversationTag.order
        )
        _favoriteItems = Query(
            filter: #Predicate<FavoriteItem> {
                $0.profileId == profileId && $0.conversationId == conversationId && $0.nodeId == nil
            }
        )
    }

    private var activeTagIds: Set<String> {
        Set(favoriteItems.map(\.tagId))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("改标签")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Button("完成") { dismiss() }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Theme.branchIndicator)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            if tags.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tag.slash")
                        .font(.system(size: 36))
                        .foregroundColor(Theme.textMuted.opacity(0.5))
                    Text("还没有标签")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textMuted)
                    Text("去侧栏新建标签")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textMuted.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(tags) { tag in
                            let isOn = activeTagIds.contains(tag.id)
                            Button {
                                toggleTag(tag, isOn: isOn)
                            } label: {
                                HStack(spacing: 10) {
                                    Text(tag.emoji)
                                        .font(.system(size: 18))
                                    Text(tag.name)
                                        .font(.system(size: 15))
                                        .foregroundColor(Theme.textPrimary)
                                    Spacer()
                                    if isOn {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 18))
                                            .foregroundColor(Theme.branchIndicator)
                                    } else {
                                        Image(systemName: "circle")
                                            .font(.system(size: 18))
                                            .foregroundColor(Theme.textMuted.opacity(0.4))
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 20)
                        }
                    }
                }
            }
        }
    }

    private func toggleTag(_ tag: ConversationTag, isOn: Bool) {
        if isOn {
            // 删除该 tag 的 FavoriteItem
            for item in favoriteItems where item.tagId == tag.id {
                modelContext.delete(item)
            }
        } else {
            // 插入新 FavoriteItem（对话级 tag，nodeId = nil）
            let preview: String = {
                // 尝试从对话标题取 preview；此处只有 conversationId，查一下
                let convDescriptor = FetchDescriptor<Conversation>(
                    predicate: #Predicate<Conversation> { $0.id == conversationId }
                )
                if let conv = try? modelContext.fetch(convDescriptor).first {
                    return conv.title
                }
                return ""
            }()
            let item = FavoriteItem(
                conversationId: conversationId,
                tagId: tag.id,
                contentPreview: preview,
                profileId: profileId
            )
            modelContext.insert(item)
        }
    }
}

// MARK: - Transient Notice Capsule (B20 part 2)

/// 极简临时提示胶囊（已切换到分支等）。挂在 chat page 顶部。
/// 透明度自驱：onAppear fade in，2s 后由 caller 清 viewModel.transientNotice。
private struct TransientNoticeCapsule: View {
    let text: String
    @State private var opacity: Double = 0

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(Theme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Theme.mainBg.opacity(0.95))
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
            )
            .overlay(
                Capsule()
                    .strokeBorder(Theme.textMuted.opacity(0.15), lineWidth: 0.5)
            )
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.18)) { opacity = 1 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    withAnimation(.easeIn(duration: 0.32)) { opacity = 0 }
                }
            }
    }
}

// MARK: - BubbleAttachmentItem

enum BubbleAttachmentItem {
    case image(name: String, data: Data)
    case file(name: String, type: String?, content: String?)
    case fileData(name: String, mime: String, data: Data)
}
