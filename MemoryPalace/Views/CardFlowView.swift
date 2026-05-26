import SwiftUI
import SwiftData
import MarkdownUI
import UniformTypeIdentifiers
import VariableBlur

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
    // iOS 下 PinBar 已挪到 ContentView.iOSChatTopBar，state 同步搬走。
    // macOS 下 PinBar 仍作为 VStack 子项留在 CardFlowView，保留这两个 state。
    @State private var isAtBottom: Bool = true

    @ViewBuilder
    private func makeBubbleView(for node: MessageNode) -> some View {
        let info = viewModel.branchInfoMap[node.id]
        let isNodeStreaming = viewModel.providerRouter.isStreaming && node.id == viewModel.currentPath.last?.id && node.role == "assistant"
        let isNodeHighlighted = viewModel.highlightedNodeId == node.id
        let isNodeSearchMatch = viewModel.inConvMatches.contains(node.id)
        BubbleView(
            node: node,
            hasBranches: info != nil,
            branchInfo: info,
            isStreaming: isNodeStreaming,
            isHighlighted: isNodeHighlighted,
            isSearchMatch: isNodeSearchMatch,
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
    private func scrollToLastMessage(proxy: ScrollViewProxy) {
        guard let lastId = viewModel.currentPath.last?.id else { return }
        // step1: 先滚 lastId（触发 LazyVStack 加载长 bubble）
        proxy.scrollTo(lastId, anchor: .bottom)
        // step2: 动画滚到哨兵 = content 真正的底
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo("__bottom_sentinel__", anchor: .bottom)
            }
        }
        // step3: 等 MarkdownUI 渲染稳定后再滚一次
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
                                scrollToLastMessage(proxy: proxy)
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
                    .onChange(of: viewModel.streamingText) { _, _ in
                        if let lastId = viewModel.currentPath.last?.id {
                            proxy.scrollTo(lastId, anchor: .bottom)
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
                                            action: { scrollToLastMessage(proxy: proxy) }
                                        )
                                        .padding(.trailing, 16)
                                    }
                                    .padding(.bottom, 4)
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                                }

                                ChatInputBar(
                                    viewModel: viewModel, modelContext: modelContext,
                                    profileManager: profileManager, providerManager: pm, presetManager: presetManager,
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
            .sheet(isPresented: $showAddToChat) {
                AddToChatSheet(onOpenSticker: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showStickerPanel = true
                        stickerVM.isEditingStickers = true
                    }
                })
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
        ""
    }

    private var inputBarSpacing: CGFloat {
        // 10 = 回底按钮 .padding(.bottom, 4) + ChatInputBar .padding(.top, 6)
        // 让 input field ↔ 胶囊 的间距 = 回底 ↔ input field 的间距，视觉对称
        isFocused ? 0 : 10
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
        return VStack(spacing: inputBarSpacing) {
            // Input container — inputText 持在子 view 里，打字只重建子 view 不重建整个 ChatInputBar
            InputFieldContainer(
                isFocused: $isFocused,
                isStreaming: viewModel.providerRouter.isStreaming,
                placeholder: inputPlaceholder,
                onSend: { text in send(text) },
                onCancelStream: { viewModel.providerRouter.cancel() },
                onStickerTap: onStickerTap
            )

            // Model selector — glass floating button, hide when keyboard is up.
            // 贴纸按钮已内嵌到 InputFieldContainer 左侧，底部工具行只剩模型选择器。
            HStack {
                Spacer()
                Button {
                    showModelPicker.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Theme.branchIndicator.opacity(0.6))
                            .frame(width: 5, height: 5)
                        Text(currentModel.name)
                            .font(.system(size: 10))
                            .foregroundColor(Theme.textMuted)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 7))
                            .foregroundColor(Theme.textMuted.opacity(0.5))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .glassEffectCompat(tint: Theme.accent, interactive: true)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            .frame(height: isFocused ? 0 : nil, alignment: .top)
            .opacity(isFocused ? 0 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, isFocused ? 5 : 4) // 8 → 4 压缩 input bar 下方空白；focused 时键盘上方留 5px 呼吸
        .padding(.top, 6)
        .frame(maxWidth: .infinity)
        // 关键 fix：让 ChatInputBar VStack 自己吞掉空白区 hit。
        // 没这一句的话 VStack 空白（input field 跟 capsule 之间、capsule 左边 Spacer、
        // 上下 padding 区）会让 hit 穿透到底下 ScrollView 的气泡 → 触发 contextMenu。
        // 子 view（InputField / 模型胶囊 Button）有自己 hit area，不受影响。
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
            .frame(height: isFocused ? 60 : 160)
            // offset(y: 40) 让 blur+gradient 漫到 home indicator 区，wallpaper 场景下
            // gradient 末端不再 solid（改 opacity 0），避免刷白盖住 wallpaper。
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
        guard !trimmed.isEmpty else { return false }

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
        viewModel.sendMessage(trimmed, model: currentModel, profile: prof, preset: preset, providerManager: providerManager, context: modelContext)
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
    }
}

// MARK: - InputFieldContainer — 独立子 view 持有 inputText
//
// 把 inputText + TextField + Send Button + glassEffect 封装成 fileprivate 子 view，
// 打字时只重建这个子 view（~80ms），外层 ChatInputBar（底部按钮行 / VariableBlurView /
// sheet / alert）不受影响。粟粟 2026-04-19 log 实测 150-170ms/字 → 预期 ≤80ms/字。

private struct InputFieldContainer: View {
    @State private var text: String = ""
    @FocusState.Binding var isFocused: Bool
    let isStreaming: Bool
    let placeholder: String
    let onSend: (String) -> Bool
    let onCancelStream: () -> Void
    // iOS 贴纸按钮内嵌到输入框左侧；macOS 无（nil）
    let onStickerTap: (() -> Void)?

    private var canSend: Bool {
        isStreaming || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        return HStack(alignment: .center, spacing: 0) {
            if let onStickerTap {
                Button(action: onStickerTap) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(Theme.textMuted.opacity(0.7))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 6)
            }

            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...6)
                .focused($isFocused)
                .padding(.leading, onStickerTap == nil ? 14 : 8)
                .padding(.vertical, 10)
                #if DEBUG
                .onChange(of: text) { _, newVal in
                    print(String(format: "[PERF] TextField onChange len=%d t=%.3f", newVal.count, CFAbsoluteTimeGetCurrent()))
                }
                #endif

            Button(action: triggerSend) {
                Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                    // 图标切换用 SF Symbol replace 动画
                    .contentTransition(.symbolEffect(.replace))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(
                                isStreaming
                                    ? Theme.danger
                                    : canSend ? Theme.branchIndicator : Theme.textMuted.opacity(0.3)
                            )
                            // 圆圈颜色随状态切换
                            .animation(.easeInOut(duration: 0.15), value: isStreaming)
                            .animation(.easeInOut(duration: 0.15), value: canSend)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            // 整体 spring 弹性缩放：流式开始/停止时弹一下
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isStreaming)
            .frame(width: 44, height: 44)
            .padding(.trailing, 4)
        }
        .glassEffectCompat(tint: Color.white.opacity(0.15), interactive: true, in: RoundedRectangle(cornerRadius: 20))
        // S1 fix: glassEffect .interactive() 在真机上 tap-through 有时序延迟
        // （经粟粟 iPhone 17 Air A/B 测确认）。在外层抢焦点绕过去，保留玻璃发光视觉。
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
    }

    private func triggerSend() {
        if isStreaming {
            onCancelStream()
            return
        }
        if onSend(text) {
            text = ""
        }
        // 预算被拦 → 保留 text
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
    var isHighlighted: Bool = false
    var isSearchMatch: Bool = false
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
    @AppStorage("hideActionBar") private var hideActionBar: Bool = false
    @State private var isExpanded = false
    @State private var showBranchPicker = false
    @State private var showFolderPicker = false
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
                    // Thinking block (collapsible)
                    if let thinking = thinkingResult?.thinking, !thinking.isEmpty {
                        DisclosureGroup("思考过程") {
                            Text(thinking)
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textMuted)
                                .textSelection(.enabled)
                                .padding(.top, 2)
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.textMuted.opacity(0.7))
                    }

                    // Assistant content — 正则脚本渲染替换
                    let rawDisplay = shouldTruncate ? String(cleaned.prefix(truncateLength)) + "\n\n..." : cleaned
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
                        Markdown(displayText)
                            .markdownTheme(.memoryPalace(
                                fontName: selectedFont,
                                scale: fontScale > 0 ? fontScale : 1.0,
                                lineSpacingScale: lineSpacingScale,
                                paragraphSpacingScale: paragraphSpacingScale
                            ))
                            .textSelection(.enabled)
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
                    .fill(isUser ? Theme.userBubble : Theme.assistantBubble)
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
                Divider()
                Button(role: .destructive, action: onSoftDelete) {
                    Label("删除", systemImage: "trash")
                }
            }

            // Hover action buttons — macOS only（iOS 用 context menu 代替）
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        // 注意：删了 .contentShape(Rectangle())。它会把 contextMenu 命中区扩到整 row 宽
        // (maxWidth: .infinity)，导致 row 空白区 (input bar 后渗 / home indicator 上方那带)
        // 点击都触发 contextMenu。删后命中区缩到气泡视觉本身（line 1238 的 RoundedRectangle），
        // 即 .contextMenu 自己附着的那个 view 的 frame。
        .sheet(isPresented: $showFolderPicker) {
            FolderPickerSheet(node: node, profileId: node.profileId)
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
