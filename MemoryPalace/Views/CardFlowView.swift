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
    @Environment(\.scenePhase) private var scenePhase
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
    /// 键盘弹出瞬间视口缩小会把 isAtBottom 打成 false——willShow 时抓快照，didShow 后按它回底。
    @State private var wasAtBottomBeforeKeyboard: Bool = true
    @State private var textSelectItem: TextSelectItem?

    @ViewBuilder
    private func makeBubbleView(for node: MessageNode) -> some View {
        let info = viewModel.branchInfoMap[node.id]
        // API 车道用 streamingNodeId，CC 车道用 ccTurnNodeId（CC 豁免后不再占 API 车道状态）
        let isNodeCCWaiting = viewModel.ccTurnNodeId == node.id
        // turn 级判定（不是 provider 级 isStreaming）：工具执行的空窗期 provider
        // isStreaming 短暂为 false，若在此判定，流式文本/思考链会闪没
        //（真机 bug："回复消失，搜索完又出现"）。assistantTurnInFlight 盖住整个
        // 工具循环；OR provider 级作为群聊发言等非 turn 路径的兜底。
        let isNodeAPIStreaming = (viewModel.assistantTurnInFlight || viewModel.providerRouter.isStreaming)
            && viewModel.streamingNodeId == node.id
        let isNodeStreaming = isNodeAPIStreaming || isNodeCCWaiting
        let isNodeHighlighted = viewModel.highlightedNodeId == node.id
        let isNodeSearchMatch = viewModel.inConvMatches.contains(node.id)
        // 思考链/流式文本只传给 API 车道的流式节点——CC 等待期间这些全局值
        // 可能属于并行的 API 对话，传给 CC 气泡会显示别人的文本
        let isThinkingNow = isNodeAPIStreaming && viewModel.isThinking
        let streamingThinkingForNode = isNodeAPIStreaming ? viewModel.streamingThinkingText : ""
        let thinkingSummaryForNode = isNodeAPIStreaming ? viewModel.thinkingSummary : ""
        BubbleView(
            node: node,
            hasBranches: info != nil,
            branchInfo: info,
            isStreaming: isNodeStreaming,
            streamingContentText: isNodeAPIStreaming ? viewModel.streamingText : "",
            isThinking: isThinkingNow,
            streamingThinkingText: streamingThinkingForNode,
            thinkingSummary: thinkingSummaryForNode,
            isHighlighted: isNodeHighlighted,
            isSearchMatch: isNodeSearchMatch,
            isLastAssistant: node.role == "assistant" && node.id == viewModel.currentPath.last?.id,
            onToggleFavorite: { viewModel.toggleFavorite(node) },
            onTogglePin: { viewModel.togglePin(node) },
            onSoftDelete: { viewModel.softDelete(node) },
            onSwitchBranch: { nodeId, idx in viewModel.switchBranch(at: nodeId, to: idx) },
            onRegenerate: makeRegenerateAction(for: node),
            onEdit: makeEditAction(for: node),
            groupMembers: {
                guard let conv = viewModel.selectedConversation, conv.kind == "group" else { return [] }
                return conv.participants.map { (id: $0.id, name: $0.name) }
            }(),
            onGroupReply: { [weak viewModel] pid in
                guard let viewModel, let pm = providerManager else { return }
                viewModel.groupRequestReply(participantId: pid, providerManager: pm, context: modelContext)
            },
            regexScripts: {
                let profileScripts = profileManager?.currentProfile.regexScripts ?? []
                let presetId = profileManager?.currentProfile.presetId ?? ""
                let presetScripts = presetManager?.preset(byId: presetId)?.regexScripts ?? []
                return presetScripts + profileScripts
            }()
        )
        // B3 性能：流式期间 CardFlowView.body 每 token 重算 → makeBubbleView 对**所有**节点
        // 重建 BubbleView（含闭包，SwiftUI 视为输入变化）→ 每条气泡 body 重跑 ContentCleaner /
        // extractThinking / ArtifactDetector / Markdown 解析。对话越长越卡。.equatable() 拦下
        // "父重建但语义未变"的非流式气泡，只有真正变化的节点（流式那条 / 内容改动）才重渲染。
        .equatable()
    }

    private func makeRegenerateAction(for node: MessageNode) -> (() -> Void)? {
        guard node.role == "assistant", let pm = providerManager else { return nil }
        return {
            guard let prof = self.profileManager?.currentProfile else { return }
            let preset = self.presetManager?.preset(byId: prof.presetId) ?? Preset.balanced
            let modelId = UserDefaults.standard.string(forKey: "selectedChatModel") ?? ""
            let model = pm.model(byId: modelId) ?? pm.availableModels.first ?? ProviderModel(providerId: "openrouter", modelId: "anthropic/claude-sonnet-4", name: "Claude Sonnet 4")
            self.viewModel.regenerate(assistantNodeId: node.id, model: model, profile: prof, preset: preset, providerManager: pm, context: self.modelContext)
        }
    }

    private func makeEditAction(for node: MessageNode) -> ((String) -> Void)? {
        guard node.role == "user", let pm = providerManager else { return nil }
        return { newText in
            guard let prof = self.profileManager?.currentProfile else { return }
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
        if viewModel.isCurrentConvLoading {
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
                                // 只渲染尾部窗口，滑到顶自动往前扩一段。
                                // 整条 path 直接喂 ForEach 时，上千条消息全都要参与布局与几何测量，
                                // LazyVStack 只省绘制不省布局 —— 白屏/滑动卡死/打字卡都是这么来的。
                                if viewModel.hasMoreAbove {
                                    Button {
                                        withAnimation(.none) { viewModel.expandRenderWindow() }
                                    } label: {
                                        Text("看更早的消息")
                                            .font(.system(size: Theme.F.caption))
                                            .foregroundColor(Theme.textMuted)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                    }
                                    .buttonStyle(.plain)
                                    .onAppear {
                                        // 滑到顶就自动扩，不用真去点
                                        viewModel.expandRenderWindow()
                                    }
                                }
                                ForEach(viewModel.visiblePath, id: \.id) { node in
                                    makeBubbleView(for: node)
                                        .id(node.id)
                                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                                        // 贴纸定位追踪：每条气泡记录 midY。旧版用 .task(id: midY)——
                                        // 滚动时每帧每条可见气泡 cancel+新建一个 async Task，是滚动卡顿
                                        // 大户。改 iOS 18 原生 onGeometryChange：同步闭包、值变才回调、
                                        // 零 Task 分配。bubblePositions 是 @ObservationIgnored，写它不触发重绘。
                                        .background(
                                            Color.clear.onGeometryChange(for: CGFloat.self) { proxy in
                                                proxy.frame(in: .named("scrollContent")).midY
                                            } action: { midY in
                                                stickerVM.bubblePositions[node.id] = midY
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
                    // [scroll-anchor] 滚动优化 Round 2（反转列表已回滚，见
                    // docs/BUGREPORT-INVERTED-LIST-ROLLBACK.md）：iOS 17/18 原生锚定，
                    // 零 transform 零兼容雷。语义：初始显示在底部；用户在底部时内容
                    // 增长（流式 token / WebView 撑高 / 新消息）自动钉底；用户上滑
                    // 读历史时保持位置不打扰。
                    // 注意必须用 iOS 18 分角色版本、且**不设 .alignment**：
                    // 无参版 .defaultScrollAnchor(.bottom) 连带把不满一屏的短对话
                    // 也底部对齐（消息沉底、上方大片空白），真机回归确认过。
                    .defaultScrollAnchor(.bottom, for: .initialOffset)
                    .defaultScrollAnchor(.bottom, for: .sizeChanges)
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
                    .onAppear {
                        // [white-screen-fix] 首次/视图重建进入：defaultScrollAnchor 对含 WebView 的
                        // 动态高度气泡锚不准 → 白屏（需手动下滑才显示）。显式滚底兜底，延迟等 layout 落定。
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            scrollToLastMessage(proxy: proxy, force: true)
                        }
                    }
                    .onChange(of: scenePhase) { _, phase in
                        // [white-screen-fix] App 回前台会重布局、易白屏，而 isCurrentConvLoading 不变化
                        // 触发不到下面那条兜底 → 这里补一刀。
                        if phase == .active {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                scrollToLastMessage(proxy: proxy, force: true)
                            }
                        }
                    }
                    // [white-screen-fix] 键盘：弹出/收起改的是 safe-area inset（视口），
                    // defaultScrollAnchor(.sizeChanges) 只认 content size 不认视口变化 →
                    // 打字时原本贴底的内容被键盘顶乱（真机 bug："打着字白屏，要手动下滑找"）。
                    // 在底才滚，不打扰上滑读历史。
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                        wasAtBottomBeforeKeyboard = isAtBottom
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                        if wasAtBottomBeforeKeyboard {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                scrollToLastMessage(proxy: proxy, force: true)
                            }
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
                        if isAtBottom || wasAtBottomBeforeKeyboard {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                scrollToLastMessage(proxy: proxy, force: true)
                            }
                        }
                    }
                    .onChange(of: viewModel.isCurrentConvLoading) { _, loading in
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
                        // 流式结束 → 强制回底（行为与改造前一致：补齐 MarkdownUI
                        // async 渲染撑高后的最后一段）
                        if newText.isEmpty && !oldText.isEmpty {
                            scrollToLastMessage(proxy: proxy, force: true)
                        }
                        // [scroll-anchor] 流式期间不再逐 token scrollTo——
                        // defaultScrollAnchor(.bottom) 在用户位于底部时自动钉底，
                        // 上滑读历史时自动不打扰。旧的 0.3s 节流 scrollTo 风暴
                        //（长对话卡顿源之一 + 与 WebView 高度变化竞争白屏源）整体移除。
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
                // 清除上一对话残留的附件
                pendingFileData = nil
                pendingFileName = nil
                pendingImageData = nil
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
    @State private var showCCDisconnectedAlert = false
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
            // turn 级状态（不是 provider 级 isStreaming）：工具循环空窗期按钮不闪回 send，
            // 堵住本对话在空窗期插队发送（user+user 连排）。别的对话照常显示 send → 排队。
            // 群聊例外：插话直接入树被轮次吸收（sendMessage 群分支），按钮保持发送态。
            isStreaming: viewModel.selectedConversation?.kind == "group" ? false : viewModel.isCurrentConvResponding,
            modelName: currentModel.name,
            pendingImageData: pendingImageData,
            pendingFileData: pendingFileData,
            pendingFileName: pendingFileName,
            onSend: { text in send(text) },
            onCancelStream: { viewModel.cancelAssistantTurn(context: modelContext) },
            onStickerTap: onStickerTap,
            onModelTap: { showModelPicker.toggle() },
            currentStyleId: viewModel.selectedConversation?.currentStyleId,
            onStyleChange: { styleId in
                viewModel.selectedConversation?.currentStyleId = styleId
            },
            groupMembers: {
                guard let conv = viewModel.selectedConversation, conv.kind == "group" else { return [] }
                return conv.participants.map { (name: $0.name, colorHex: $0.colorHex) }
            }(),
            draftConversationId: viewModel.selectedConversation?.id,
            initialDraft: viewModel.selectedConversation?.draftText ?? "",
            onDraftChange: { [weak viewModel] newText in
                guard let conv = viewModel?.selectedConversation, conv.draftText != newText else { return }
                conv.draftText = newText
                // 显式 save：autosave 时机不保证，被杀进程就丢（单行 update 每键无感）
                try? modelContext.save()
            }
        )
        // 定位对齐粟粟（她走 UIKit：container 的 leading/trailing 直接贴 chatHC.view，
        // bottom 钉 keyboardLayoutGuide.topAnchor，全程没有手写间距）。
        // 我们没有她那套 UIKit 定位层，用 SwiftUI 等价物：
        //   左右 16 → 8（她是 0 贴边，但我们输入框本体没有她那层 container 内边距，
        //   完全贴边会让玻璃描边压在屏幕边缘上，取 8 折中）
        //   底部 8 → 0（她无手写底距，安全区已经给了 home indicator 的位置）
        .padding(.horizontal, 8)
        .padding(.bottom, 0)
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
        .alert("CC 未连接", isPresented: $showCCDisconnectedAlert) {
            Button("好") { }
        } message: {
            Text("CC 未连接，请检查 CC Bridge 设置")
        }
    }

    /// 返回 true 表示发送成功（子 view 应清空 text），false = 预算被拦（text 保留）
    private func send(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageData = pendingImageData.wrappedValue
        let fileData = pendingFileData.wrappedValue
        let fileName = pendingFileName.wrappedValue
        guard !trimmed.isEmpty || imageData != nil || fileData != nil else { return false }

        // Task 3: 选了 CC 模型但 CC 未连接 → 弹提示，不发送（保留 text）
        if providerManager.provider(for: currentModel)?.type == .ccBridge,
           !CCBridgeWebSocketClient.shared.isConnected {
            showCCDisconnectedAlert = true
            return false
        }

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
/// 上层 TextField(axis:.vertical，自适应高度) + 下层工具栏（+ 号 | Spacer | 语音/发送）
private struct InputFieldContainer: View {
    /// 键盘是否已开始升起。驱动源用 keyboardWillShow 而非 isFocused——
    /// 粟粟 2026-08-16 真机终验记过这个坑：isFocused 驱动会让「输入框先闪下 10pt、
    /// 模型选择器异位、再上滑」的起步预抖。willShow 与键盘同一时刻，混不进可感范围。
    @State private var kbUp = false
    @State private var text: String = ""
    @FocusState.Binding var isFocused: Bool
    let isStreaming: Bool
    let modelName: String
    @Binding var pendingImageData: Data?
    @Binding var pendingFileData: Data?
    @Binding var pendingFileName: String?
    let onSend: (String) -> Bool
    let onCancelStream: () -> Void
    let onStickerTap: (() -> Void)?
    let onModelTap: () -> Void
    var currentStyleId: String? = nil
    var onStyleChange: ((String) -> Void)? = nil
    /// 群聊成员（名字+气泡色）。单聊传空数组，@ 补全整体不启用。
    var groupMembers: [(name: String, colorHex: String)] = []
    /// B41 草稿三件套：对话 id（切换信号）+ 初始草稿（恢复源）+ 每键回调（外层直写模型+save）。
    /// 粟粟教训：只靠"切换时 flush"必漏——翻页常驻不走 onDisappear、同 id 不走 onChange、
    /// rootView 重建 @State 直接蒸发。所以每键直写，切换恢复只是读取。
    var draftConversationId: String? = nil
    var initialDraft: String = ""
    var onDraftChange: ((String) -> Void)? = nil

    // ── @ 补全（G2）：纯 SwiftUI 层检测 text 末尾的 @片段，不碰 UITextView 内部 ──

    /// text 末尾正处于 "@xxx" 输入状态时返回 xxx（可为空串=刚打出 @）；否则 nil。
    private var mentionFragment: String? {
        guard !groupMembers.isEmpty else { return nil }
        guard let atIdx = text.lastIndex(of: "@") else { return nil }
        let frag = String(text[text.index(after: atIdx)...])
        // @ 后已出现空白 → 这个提及已完成，不再弹
        guard !frag.contains(where: { $0.isWhitespace }) else { return nil }
        guard frag.count <= 20 else { return nil }
        return frag
    }

    private var mentionCandidates: [(name: String, colorHex: String)] {
        guard let frag = mentionFragment else { return [] }
        if frag.isEmpty { return groupMembers }
        return groupMembers.filter { $0.name.range(of: frag, options: .caseInsensitive) != nil }
    }

    /// 把末尾的 @片段 替换成 @名字 + 空格（空格同时是后端 mentioned() 认的边界）。
    private func completeMention(_ name: String) {
        guard let atIdx = text.lastIndex(of: "@") else { return }
        text = String(text[..<atIdx]) + "@" + name + " "
    }

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
        return AnyView(VStack(spacing: 0) {
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
            // ── @ 补全候选条（G2，群聊输入 @ 时出现）───────────────────
            if !mentionCandidates.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(mentionCandidates, id: \.name) { member in
                            Button {
                                completeMention(member.name)
                            } label: {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(Color(hexString: member.colorHex))
                                        .frame(width: 8, height: 8)
                                    Text(member.name)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(Theme.textPrimary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Theme.mainBg.opacity(0.7)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.top, 8)
                .padding(.bottom, 2)
                Divider().padding(.horizontal, 12).padding(.top, 6)
            }
            // ── 单行：+ | 文本 | 发送 ─────────────────────────────────
            // 2026-08-24 兔兔第二轮真机验收：上一刀只把模型/✨ 挪到框外，
            // + 与发送键仍独占下面一行，所以还是两层、没瘦下来。
            // 粟粟那个是真单层——三者同处一个 HStack，文本多行时两侧按钮垂直居中。
            // 这里按她的排法并成一行；alignment 显式 .center，否则多行时按钮会被顶到顶部。
            HStack(alignment: .center, spacing: 4) {
                // + 号按钮
                if let onStickerTap {
                    Button(action: onStickerTap) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(Theme.textMuted.opacity(0.5))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 6)
                }

                // 文本输入（TextField(axis:.vertical) 自适应高度，5 行封顶后内部滚）
                TextField("", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...6)
                    .focused($isFocused)
                    .padding(.leading, 6)
                    .padding(.vertical, 10)

                // 发送 / 停止 / 语音占位 —— 同一个按钮换图标，不做 if/else 两个按钮
                // 2026-08-24 兔兔第三轮：上一刀把黑换成 Theme.accent，太淡、糊进背景。
                // 粟粟用的是 Theme.branchIndicator（她注释叫「薄荷发送」），饱和度够。
                // 她也不拆两个按钮：canSend ? arrow.up : waveform，底色 canSend 才填，
                // 否则 Color.clear——这样空↔有字切换不会闪。
                Button(action: triggerSend) {
                    Image(systemName: isStreaming ? "stop.fill" : (canSend ? "arrow.up" : "waveform"))
                        .contentTransition(.symbolEffect(.replace))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(canSend || isStreaming ? .white : Theme.textMuted.opacity(0.55))
                        .frame(width: 32, height: 32)
                        .background(
                            Circle().fill(
                                isStreaming ? Theme.danger
                                            : canSend ? Theme.branchIndicator : Color.clear
                            )
                            .animation(.easeInOut(duration: 0.15), value: isStreaming)
                            .animation(.easeInOut(duration: 0.15), value: canSend)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSend && !isStreaming)
                // 44×44 是 iOS 标准最小点击区，也是整行高度的下限——
                // 兔兔报「输入框太细」的根因：我上一刀只搬了粟粟里层那个 32 的圆，
                // 没搬她外面这层 44（CardFlowView:2035），行高就少了 8pt。
                .frame(width: 44, height: 44)
                .padding(.trailing, 4)
            }
            // 不设任何行高——粟粟那边整行也没有 frame(height:)，
            // 高度全靠 TextField 自己的 .padding(.vertical, 10) 撑出来。
            // 之前写死 44 正是「不随文字长高」第三次复发的根因。
            .padding(.horizontal, 6)
        }
        // 玻璃卡片只包「输入框本体」——模型/风格已挪到框外下方那条
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Theme.mainBg.opacity(0.35))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Theme.textMuted.opacity(0.14), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        )
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .onTapGesture { isFocused = true }
        )
        // ── 框外下方：模型 + 风格 ────────────────────────────────────
        // 兔兔 2026-08-24 定的方案（照粟粟思路）：这俩都是「这次对话用什么」的设置，
        // 不是「发这条消息」的动作，摘出框外输入框就回归单层 = 细。
        // 键盘升起时收起这条：兔兔发现原来 safeAreaInset 挂在输入框上，
        // 它就永远跟着输入框走，键盘顶不掉。粟粟那边也不是物理顶掉的——
        // 她显式写 `if !kbUp { bottomControlRow.transition(.opacity) }`。
        // 过渡只用淡入淡出不带位移：滑动成分会被看成「灰块被推下去」（她的原话）。
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !kbUp {
            HStack(spacing: 6) {
                Spacer()
            // 风格快捷切换
            Menu {
                Button("无风格") {
                    onStyleChange?("")
                }
                ForEach(StyleManager.shared.styles) { style in
                    Button(style.name) {
                        onStyleChange?(style.id)
                    }
                }
            } label: {
                let hasStyle = !(currentStyleId?.isEmpty ?? true)
                HStack(spacing: 3) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                    if hasStyle, let name = StyleManager.shared.find(currentStyleId ?? "")?.name {
                        Text(name)
                            .font(.system(size: 10))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                // 与旁边模型胶囊同款：同样 ultraThinMaterial 玻璃 + 同内距，
                // 两个并排才像一组。原来 5% 不透明度的底看着像个幽灵圆。
                .foregroundColor(hasStyle ? Theme.branchIndicator : Theme.textMuted)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
            }
                // 模型胶囊（吸粟粟实调：10pt 字 + 5×5 状态点 + 中间截断，超长名不撑爆）
                Button(action: onModelTap) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Theme.accent.opacity(0.6))
                            .frame(width: 5, height: 5)
                        Text(modelName)
                            .font(.system(size: 10))
                            .foregroundColor(Theme.textMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 7))
                            .foregroundColor(Theme.textMuted.opacity(0.5))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 6)
            .padding(.trailing, 8)   // 粟粟实调：胶囊左移 8px
            .transition(.opacity)
            }
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { kbUp = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { kbUp = false }
        }
        #endif
        // B41 草稿：每键上报（外层写 conversation.draftText + 显式 save）
        .onChange(of: text) { _, newText in
            onDraftChange?(newText)
        }
        // 切对话：换成新对话的草稿（旧对话的已实时落盘，无需 flush）
        .onChange(of: draftConversationId) { _, _ in
            text = initialDraft
        }
        // 冷启动 / view 重建：恢复当前对话的草稿
        .onAppear {
            if text.isEmpty, !initialDraft.isEmpty { text = initialDraft }
        }
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
    /// 流式时的实时文本——直接读 viewModel.streamingText，不经过 SwiftData
    var streamingContentText: String = ""
    /// True while the model is still generating reasoning_content (thinking phase)
    var isThinking: Bool = false
    /// Live reasoning tokens from ViewModel — only populated for the currently streaming node
    var streamingThinkingText: String = ""
    /// One-sentence summary generated after thinking phase ends; empty until summary arrives
    var thinkingSummary: String = ""
    var isHighlighted: Bool = false
    var isSearchMatch: Bool = false
    /// 当前对话路径的最后一条 assistant 消息。
    var isLastAssistant: Bool = false
    /// [search-ui] segments 分支的流式尾巴：streamingContentText 里减去 segments
    /// 已经包含的 .text 长度，只显示还没进 segments 的增量，防止双份显示。
    private func streamingTailAfterSegments(_ segs: [MessageSegment]) -> String {
        guard isStreaming, !streamingContentText.isEmpty else { return "" }
        var segTextCount = 0
        for seg in segs {
            if case .text(let t) = seg { segTextCount += t.count }
        }
        guard segTextCount < streamingContentText.count else { return "" }
        return String(streamingContentText.dropFirst(segTextCount))
    }

    /// 思考链预览（时钟 + 可展开）。segments / 纯文本两条渲染分支共用。
    /// 修复：带 segments 的消息（CC 标记式 / API 流式）此前完全不渲染 thinking。
    @ViewBuilder
    private func thinkingPreview(staticThinking: String) -> some View {
                    let liveThinking = isStreaming && !streamingThinkingText.isEmpty
                    let hasThinkingContent = liveThinking || !staticThinking.isEmpty
                    if hasThinkingContent && thinkingPreviewMode != "hidden" {
                        let displayThinking = liveThinking ? streamingThinkingText : staticThinking
                        let rawPreview = String(displayThinking.prefix(40)) + (displayThinking.count > 40 ? "…" : "")
                        let previewStr = thinkingPreviewMode == "prefix" ? rawPreview : (thinkingSummary.isEmpty ? rawPreview : thinkingSummary)
                        Button {
                            if thinkingSheetMode {
                                showThinkingSheet = true
                            } else {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    thinkingExpanded.toggle()
                                }
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
                        // 弹窗模式（thinkingSheetMode 开）：点标题弹全屏 sheet，复用 ThinkingPanelView
                        .sheet(isPresented: $showThinkingSheet) {
                            ThinkingPanelView(thinkingText: displayThinking, isThinking: liveThinking && isThinking)
                        }

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
    }

    let onToggleFavorite: () -> Void
    let onTogglePin: () -> Void
    let onSoftDelete: () -> Void
    let onSwitchBranch: (String, Int) -> Void
    var onRegenerate: (() -> Void)? = nil
    var onEdit: ((String) -> Void)? = nil
    /// G3：群成员（长按「让 TA 接话」用）。单聊为空 → 菜单项不出现。
    var groupMembers: [(id: String, name: String)] = []
    var onGroupReply: ((String) -> Void)? = nil
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
    @AppStorage("thinkingSheetMode") private var thinkingSheetMode = false  // 开=弹全屏 sheet，关=原地折叠
    @State private var showThinkingSheet = false
    @State private var showArtifactCanvas = false
    @State private var detectedArtifact: ArtifactContent? = nil
    @State private var messageWebViewHeight: CGFloat = 44
    @State private var isSelectingText = false
    @State private var isEditing = false
    @State private var editText = ""
    @State private var highlightOpacity: Double = 0
    private let truncateLength = 300

    var isUser: Bool { node.role == "user" }

    /// 群聊 V2：按发言者 id 稳定取色（确定性哈希，跨启动不变）。
    static func speakerColor(_ id: String?) -> Color {
        let palette: [Color] = [.blue, .orange, .green, .purple]
        guard let id, !id.isEmpty else { return Theme.textMuted }
        let h = id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[h % palette.count]
    }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 3) {
            // Role label + time（两个都隐藏时整行不 render，避免空 HStack 占位）
            if !hideRoleName || !hideTimestamp {
                HStack(spacing: 4) {
                    if !hideRoleName {
                        // 群聊 V2：名字标签优先用发言者名；颜色按发言者区分（单聊 senderName=nil 不变）
                        Text(isUser ? userName : (node.senderName ?? assistantName))
                            .font(.caption2.weight(.medium))
                            .foregroundColor(node.senderName != nil ? Self.speakerColor(node.senderId) : Theme.textMuted)
                    }
                    if !hideTimestamp, let time = node.createTime {
                        Text(time.formatted(.dateTime.month().day().hour().minute()))
                            .font(.caption2)
                            .foregroundColor(Theme.textMuted.opacity(0.6))
                    }
                    if isUser { StyleChip(styleId: node.styleIdSnapshot) }
                }
                .padding(.horizontal, 4)
            }

            // Bubble
            VStack(alignment: .leading, spacing: 6) {
                // 流式优化：streaming 时直接读 streamingContentText（绕过 SwiftData），完成后读 node.content
                let sourceText = isStreaming && !streamingContentText.isEmpty ? streamingContentText : node.content
                let rawCleaned = ContentCleaner.clean(sourceText, cacheKey: "\(node.id)_\(sourceText.count)")
                let thinkingResult = isUser ? nil : ContentCleaner.extractThinking(from: rawCleaned)
                let cleaned = VoiceMessageWriter.strippedForDisplay(thinkingResult?.content ?? rawCleaned)
                // CC 思考链一律走 pendingThinking 正路：由 CCBridgeProvider / ConversationViewModel+Chat
                // 在 reply 到达时 consume 并嵌入该条自己的 content，再由下方 ThinkingBlockView 渲染。
                // 2026-08-24 拆除：这里原本挂 CCBridgeWebSocketClient.shared.latestThinking，
                // 那是 pendingThinking 之前的旧实现残骸（注释自称「向后兼容」），三重缺陷叠加——
                //   1. 背后的 thinkingBlocks 字典全项目只写不清
                //   2. latestThinking 取全局时间戳最大者，不区分对话 → 跨窗口串台
                //   3. isCCBridgeProvider 由非响应式 UserDefaults 裸读算出，切 provider 后滞后一轮
                // 症状：新回复等待期间，气泡里挂出「CC 思考过程」，点开是上一轮的内容。
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
                    } else if let segs = node.segments, segs.hasRenderableSegments {
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
                } else if let segs = node.segments, segs.hasRenderableSegments {
                    // 思考链兜底：segments 里没有 .thinking 段时（CC 标记式 / deepseek 流式），
                    // 用共用预览补渲染，否则思考链整体丢失。
                    let segsHaveThinking = segs.contains { seg in
                        if case .thinking = seg { return true } else { return false }
                    }
                    if !segsHaveThinking {
                        thinkingPreview(staticThinking: thinkingResult?.thinking ?? "")
                    }
                    // Claude v2 导入：按段渲染（每段独立折叠，顺序严格）
                    MessageSegmentsView(
                        segments: segs,
                        selectedFont: selectedFont,
                        fontScale: fontScale,
                        lineSpacingScale: lineSpacingScale,
                        paragraphSpacingScale: paragraphSpacingScale,
                        regexScripts: regexScripts
                    )
                    // [search-ui] 工具轮实时推送后本分支提前接管气泡；流式文本在
                    // 卡片下方继续显示。减去 segments 已含文本长度防双份
                    //（Anthropic 轮文本会进 segments，OpenAI 不会）。
                    let streamingTail = streamingTailAfterSegments(segs)
                    if !streamingTail.isEmpty {
                        Markdown(BubbleMarkdownSimplifier.simplify(streamingTail))
                            .markdownTheme(.memoryPalace(
                                fontName: selectedFont,
                                scale: fontScale > 0 ? fontScale : 1.0,
                                lineSpacingScale: lineSpacingScale,
                                paragraphSpacingScale: paragraphSpacingScale
                            ))
                            .textSelection(.enabled)
                    }
                } else {
                    thinkingPreview(staticThinking: thinkingResult?.thinking ?? "")

                    // Assistant content — 正则脚本渲染替换
                    let artifactForCard: ArtifactContent? = (!isUser && !isStreaming) ? ArtifactDetector.find(in: cleaned) : nil
                    let cleanedForDisplay = artifactForCard != nil ? ArtifactDetector.stripFirst(in: cleaned) : cleaned
                    let rawDisplay = shouldTruncate ? String(cleanedForDisplay.prefix(truncateLength)) + "\n\n..." : cleanedForDisplay
                    let displayText = node.role == "assistant" && !regexScripts.isEmpty
                        ? RegexEngine.apply(scripts: regexScripts, text: rawDisplay, messagePlacement: 2, isMarkdown: true)
                        : rawDisplay
                    if displayText.isEmpty && isStreaming {
                        TypingDotsView()
                    } else if !displayText.isEmpty {
                        let needsWebView = displayText.contains("{color:")
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
                            .frame(height: messageWebViewHeight)
                        } else {
                            // 普通消息：MarkdownUI 渲染（纯 SwiftUI，零白屏）
                            // 抹平文档感（## 标题/嵌套列表/---）；只影响渲染，复制仍是 node.content 原文
                            Markdown(isUser ? displayText : BubbleMarkdownSimplifier.simplify(displayText))
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
                // 语音条胶囊（audioRef 不进 segments 渲染，这里单独画）
                if let segs = node.segments {
                    let voiceSegs: [(path: String, duration: Double?)] = segs.compactMap { seg in
                        if case .audioRef(_, _, let p, let d, _) = seg { return (p, d) }
                        return nil
                    }
                    ForEach(voiceSegs, id: \.path) { v in
                        VoiceCapsuleView(path: v.path, duration: v.duration,
                                         nodeId: node.id, profileId: node.profileId, isUser: isUser)
                            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
                    }
                }
                // 生成中：画同形胶囊的「成型态」，而不是让占位行以纯文字露脸
                if !isUser, VoiceMessageWriter.isPending(node: node) {
                    VoicePendingCapsuleView()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
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

// PR(usage): 气泡底部 token 数字已移除（统计走 Token 统计页）
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
                if !isUser, !isStreaming {
                    Button {
                        SpeechService.shared.speak(nodeId: node.id, text: SpeechService.speakableText(from: node))
                    } label: {
                        Label("朗读", systemImage: "speaker.wave.2")
                    }
                    Button {
                        SpeechService.shared.stop()
                    } label: {
                        Label("停止朗读", systemImage: "speaker.slash")
                    }
                    Divider()
                }
                if !groupMembers.isEmpty, let onGroupReply, !isStreaming {
                    Menu {
                        ForEach(groupMembers, id: \.id) { member in
                            Button(member.name) { onGroupReply(member.id) }
                        }
                    } label: {
                        Label("让 TA 接话", systemImage: "bubble.left.and.bubble.right")
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

// MARK: - BubbleView Equatable (B3 性能优化)
//
// 只比较影响渲染的**值输入**，排除每次 makeBubbleView 都新建的闭包
//（onToggleFavorite / onRegenerate…）。闭包行为稳定（同 node 同语义），不进 == 判据。
// node 的内容变化：流式走 streamingContentText / streamingThinkingText（每 token 变 → 该条
// 重渲染），finalize / 切分支 flip isStreaming / streamingNodeId（父 prop 变 → 重渲染），
// 编辑/重生成建新 node（ForEach id 变 → 新视图）。node.content 兜底真机可能的原地写。
// @AppStorage / @State（字体、展开态…）走独立 invalidation，不受 == 影响，照常更新。
extension BubbleView: Equatable {
    static func == (lhs: BubbleView, rhs: BubbleView) -> Bool {
        lhs.node.id == rhs.node.id
            && lhs.node.content == rhs.node.content
            && lhs.node.isPinned == rhs.node.isPinned
            && lhs.node.isFavorite == rhs.node.isFavorite
            && lhs.node.isDeleted == rhs.node.isDeleted
            && lhs.hasBranches == rhs.hasBranches
            && lhs.branchInfo?.branchNodeId == rhs.branchInfo?.branchNodeId
            && lhs.branchInfo?.branchCount == rhs.branchInfo?.branchCount
            && lhs.branchInfo?.displayedNodeId == rhs.branchInfo?.displayedNodeId
            && lhs.isStreaming == rhs.isStreaming
            && lhs.streamingContentText == rhs.streamingContentText
            && lhs.isThinking == rhs.isThinking
            && lhs.streamingThinkingText == rhs.streamingThinkingText
            && lhs.thinkingSummary == rhs.thinkingSummary
            && lhs.isHighlighted == rhs.isHighlighted
            && lhs.isSearchMatch == rhs.isSearchMatch
            && lhs.isLastAssistant == rhs.isLastAssistant
            && lhs.regexScripts.count == rhs.regexScripts.count
            && lhs.groupMembers.count == rhs.groupMembers.count
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
                                ConversationListStore.insertFavorite(item, context: modelContext)
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
                    ConversationListStore.insertTag(tag, context: modelContext)
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
                ConversationListStore.deleteFavorite(item, context: modelContext)
            }
        } else {
            // 插入新 FavoriteItem（对话级 tag，nodeId = nil）
            // preview 取对话标题；此处只有 conversationId，查一下
            let preview = ConversationListStore.conversation(id: conversationId, profileId: profileId, context: modelContext)?.title ?? ""
            let item = FavoriteItem(
                conversationId: conversationId,
                tagId: tag.id,
                contentPreview: preview,
                profileId: profileId
            )
            ConversationListStore.insertFavorite(item, context: modelContext)
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
