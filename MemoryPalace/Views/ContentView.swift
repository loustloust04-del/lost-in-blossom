import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
import VariableBlur
#endif

#if DEBUG
@MainActor enum PerfCounters {
    static var contentViewBody = 0
    static var chatInputBarBody = 0
    static var inputFieldBody = 0
    /// 上一次 ContentView.body 的订阅源快照，用于诊断 #N body 是哪个 source 变了
    static var lastContentViewSnapshot: [String: String] = [:]
}
#endif

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var themeManager: ThemeManager?
    @State private var viewModel = ConversationViewModel()
    @Environment(GlobalWorldBookManager.self) private var globalWBManager: GlobalWorldBookManager?
    /// 路线 B 下 ContentView 订阅 ProfileManager 获取 currentProfile.id，用于给 @Query-backed
    /// sub-views (EmptyStateView 等) init(profileId:) 传值。由于 ProfileManager.switchTo
    /// 只改 currentProfile（container 不动），订阅 ProfileManager 触发的 body rebuild 不会
    /// 引发 SwiftData reset race，安全。原 master R1 revert 担心的是订阅 3 个 Manager 放大
    /// body 频次，这里只订阅 ProfileManager（currentProfile 变化频率极低）。
    @Environment(ProfileManager.self) private var profileManager: ProfileManager?
    // ProviderManager / PresetManager 的 @Environment 订阅挪到
    // PagingContainerView（Representable 层），避免 ContentView.body 被这些 @Observable
    // Manager 的属性变化触发整体重算 + 被 updatePages 大锤放大到 ChatInputBar.body
    // （master R1 revert 原罪，见 docs/postmortem-kelivo-keyboard-wallpaper.md）。
    @Environment(RightPanelNavigator.self) private var rightPanelNavigator: RightPanelNavigator?
    @State private var showImporter = false
    @State private var showSettings = false
    @State private var searchText = ""
    @State private var showFavoritesOnly = false
    @State private var showTrash = false
    #if os(iOS)
    // 当前 iOS page：0=list, 1=chat, 2=more。@State 与 PagingContainerView.currentPage binding，
    // UIKit UIScrollView paging 完成后通过 binding 回写。
    @State private var iOSPage: Int = 1
    #endif
    // iOSPageDragOffset removed — ScrollView handles drag natively
    @State private var isSidebarVisible = true
    @State private var isRightPanelVisible = false
    @State private var selectedToolId: String = "memory"
    @State private var stickerVM = StickerViewModel()
    @State private var isFullscreen = false
    @State private var isFullscreenTransitioning = false
    @State private var windowWidth: CGFloat = 1200
    @State private var suppressAutoCollapse = false
    #if os(iOS)
    @State private var isKeyboardVisible = false
    @State private var topSafeAreaInset: CGFloat = 59  // 默认 iPhone 常见值；onAppear 更新成 UIApplication 的真值
    // 聊天页 nav 菜单 / 重命名 / 改标签 状态
    @State private var showRenameAlert = false
    @State private var renameText: String = ""
    @State private var showChangeProjectSheet = false
    // Pin Bar state（从 CardFlowView 挪上来，Phase 3 用）
    @State private var pinCurrentIndex: Int = 0
    @State private var pinBarHidden: Bool = false
    // 分支地图 sheet（B20 part 2 A3 反馈）
    @State private var showBranchMap = false
    #endif
    #if os(macOS)
    // bgMode 在 iOS 上从未被 read（仅 macOS 内 zstackLayer 判断），但 @AppStorage declaration
    // 让 ContentView 订阅 _debugBackgroundModeRaw 这个 wrapper，启动后 UserDefaults 异步同步
    // 触发 ContentView body re-eval（第三轮 log 实证 #2 +2.85s ghost body 的真凶）。
    // 包 #if os(macOS) 后 iOS struct 没这个 property，不再订阅。
    @AppStorage(DebugRenderSettings.themeBackgroundModeKey)
    private var debugBackgroundModeRaw: String = DebugThemeBackgroundMode.original.rawValue

    private var debugBackgroundMode: DebugThemeBackgroundMode {
        DebugThemeBackgroundMode(rawValue: debugBackgroundModeRaw) ?? .original
    }
    #endif
    @AppStorage("blurRadius") private var blurRadius = 1.3
    // pageIndicatorInZStack / debugPageIndicatorMode / @AppStorage debugPageIndicatorModeRaw
    // 全 dead code（pageIndicatorInZStack 无 call site）— 已删除以减少订阅 surface。
    @State private var calendarWidth: CGFloat = 300
    @State private var detailWidth: CGFloat = 600
    private let sidebarMinWidth: CGFloat = 250
    private let sidebarDefaultMaxWidth: CGFloat = 400
    private let contentMinWidth: CGFloat = 350
    private let calendarMinWidth: CGFloat = 250
    private let calendarPanelMaxWidth: CGFloat = 380
    private let dividerWidth: CGFloat = 8
    private let calendarCollapseThreshold: CGFloat = 900

    private var sidebarMaxWidth: CGFloat {
        guard isRightPanelVisible, !suppressAutoCollapse else { return sidebarDefaultMaxWidth }
        return min(
            sidebarDefaultMaxWidth,
            max(sidebarMinWidth, windowWidth - contentMinWidth - dividerWidth - calendarMinWidth)
        )
    }

    private var minimumDetailWidthForCalendar: CGFloat {
        contentMinWidth + dividerWidth + calendarMinWidth
    }

    /// 日历面板在当前可用空间下的最大宽度（确保内容区 >= 350）
    private func calendarMaxWidth(in availableWidth: CGFloat) -> CGFloat {
        min(calendarPanelMaxWidth, max(0, availableWidth - contentMinWidth - dividerWidth))
    }

    /// 日历面板的实际宽度
    private func effectiveCalendarWidth(in availableWidth: CGFloat) -> CGFloat? {
        let maxW = calendarMaxWidth(in: availableWidth)
        guard maxW >= calendarMinWidth else { return nil }
        return min(calendarWidth, maxW)
    }

    var body: some View {
        #if DEBUG
        // SwiftUI 暗器 _logChanges() — 让 SwiftUI runtime 自己 print "因为 X 改变所以重 eval"
        // （走 unified logging os_log，subsystem 大致是 com.apple.SwiftUI）。Hermes Q2 推荐
        // 用 newer variant 替代 _printChanges()。两者都是 underscore-prefixed 非 public API，
        // iOS 26 / macOS 14 deployment target 上 verified 可用，DEBUG only。
        // 若以后 Apple 改签名，build error → fallback Self._printChanges()。
        let _ = Self._printChanges()
        #endif
        let manager = themeManager ?? ThemeManager.shared
        let _ = manager.themeChangeID
        #if os(macOS)
        let bgMode = debugBackgroundMode
        #endif
        #if DEBUG
        // 订阅源 snapshot — 砍掉之前探针 observer effect 引入的字段（ContentView 生产代码
        // 不 read 这些 field，但探针 read 让 ContentView 订阅了它们 → 第三轮 log 看到的
        // sidebarRefresh / stickerCount 触发 body 是"假" hot path，是探针自己挑起的）。
        // 保留字段 = ContentView body 真实 read 的 source（grep 实证）：
        //   selectedConv / currentPath / isStreaming / pinnedNodes (= currentPath 衍生) /
        //   isEditingStickers / themeID / profileId / colorScheme + iOS-only iOSPage / isKeyboardVisible.
        // 删除（探针引入）：scrollToNode / highlightNode / streamingTextLen / sidebarRefresh /
        //   stickerCount / stickerSelected / stickerImporting / wbBooks / navTarget / bgMode(iOS).
        // 头号嫌疑根据 Hermes Q4 不再是 SwiftData @Model（per-keypath 应不 invalidate）。
        PerfCounters.contentViewBody += 1
        var _bodyProbeSnapshot: [String: String] = [
            "selectedConv": viewModel.selectedConversation?.id.prefix(8).description ?? "nil",
            "currentPath": "\(viewModel.currentPath.count)",
            "isStreaming": "\(viewModel.providerRouter.isStreaming)",
            "pinnedNodes": "\(viewModel.pinnedNodes.count)",
            "isEditingStickers": "\(stickerVM.isEditingStickers)",
            "themeID": manager.themeChangeID.uuidString.prefix(8).description,
            "profileId": profileManager?.currentProfile.id.prefix(8).description ?? "nil",
            "colorScheme": "\(colorScheme)",
        ]
        #if os(iOS)
        _bodyProbeSnapshot["iOSPage"] = "\(iOSPage)"
        _bodyProbeSnapshot["isKeyboardVisible"] = "\(isKeyboardVisible)"
        #endif
        #if os(macOS)
        _bodyProbeSnapshot["bgMode"] = bgMode.rawValue
        #endif
        let _bodyProbeDiff = _bodyProbeSnapshot
            .filter { PerfCounters.lastContentViewSnapshot[$0.key] != $0.value }
            .map { "\($0.key): \(PerfCounters.lastContentViewSnapshot[$0.key] ?? "∅")→\($0.value)" }
            .sorted()
        PerfCounters.lastContentViewSnapshot = _bodyProbeSnapshot
        let _bodyProbeDiffStr = _bodyProbeDiff.isEmpty ? "(none — SwiftUI re-eval w/o source change?)" : _bodyProbeDiff.joined(separator: ", ")
        print(String(format: "[PERF] ContentView.body #%d t=%.3f Δ=%@",
                     PerfCounters.contentViewBody,
                     CFAbsoluteTimeGetCurrent(),
                     _bodyProbeDiffStr))
        #endif
        return ZStack {
            #if os(macOS)
            // master 的 Theme.mainBg baseline，仅 macOS 留：路线 C 下 iOS 每页自己 .background +
            // hc.view.clipsToBounds 已兜底，不需要 baseline；macOS 保留作 ZStack 底色防露白。
            Theme.mainBg.ignoresSafeArea()
            #endif

            #if os(macOS)
            // Debug: C 模式把 wallpaper 挪到 ZStack 底层（避开 .background 的 parent-size 约束）
            // iOS 下已改为"只聊天页带 wallpaper"，全局 zstackLayer 不再适用，保留仅 macOS
            if bgMode == .zstackLayer {
                ThemeBackgroundView(
                    fill: Theme.mainBg,
                    imageURL: manager.currentBackgroundImageURL,
                    scheme: manager.activeScheme,
                    backgroundStyle: manager.currentBackgroundStyle
                )
                .ignoresSafeArea()
            }
            if isFullscreen {
                fullscreenLayout
            } else {
                normalLayout
            }

            rightPanelCornerButton
                .padding(.top, isFullscreen ? 8 : 6)
                .padding(.trailing, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .ignoresSafeArea(edges: .top)
                .zIndex(10)

            if isFullscreenTransitioning {
                Rectangle()
                    .fill(Theme.mainBg)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .frame(height: 64, alignment: .top)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
                    .transition(.identity)
            }
            #endif
            #if os(iOS)
            iOSLayout
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .background {
            if bgMode != .zstackLayer {
                ThemeBackgroundView(
                    fill: Theme.mainBg,
                    imageURL: manager.currentBackgroundImageURL,
                    scheme: manager.activeScheme,
                    backgroundStyle: manager.currentBackgroundStyle
                )
                .ignoresSafeArea()
            }
        }
        #else
        // 路线 C：body.background 撤了。每页自己处理背景 + safe area 延伸：
        // - iOSListPage / iOSDashboardPage 各自 .background(color.ignoresSafeArea())
        // - iOSChatPage 内部 .background { ChatWallpaperBackdrop.ignoresSafeArea() } + topBar overlay
        // R1 revert (2026-04-19 perf)：原来这里有 scenePhase / profileManager 两个 onChange flush，
        // chat→sidebar 的 flush 已挪到 onChange(iOSPage) 里 (oldPage==1 && newPage==0 触发)。
        .overlay {
            // pageIndicator 挂 body overlay（Phase 2 v1 时在 iOSLayout 内，Phase 3 挪出来）。
            // 照搬 master：VStack+Spacer 推 HStack 到底，.ignoresSafeArea(.container, .bottom)
            // 漫到 home indicator 区，padding.bottom 15 让 HStack 落在 home indicator 中部。
            // 键盘弹出时隐藏避免贴键盘。
            if !isKeyboardVisible {
                VStack {
                    Spacer()
                    pageIndicatorDots
                        .padding(.bottom, 15)
                }
                .ignoresSafeArea(.container, edges: .bottom)
                .allowsHitTesting(false)
            }
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .showStickerLibrary)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedToolId = "sticker"
                isRightPanelVisible = true
            }
        }
        // 资源搜索点击 → SidebarView 设 navigator.pendingTarget → 这里协调打开右栏
        .onChange(of: rightPanelNavigator?.pendingTarget) { _, target in
            guard let t = target else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedToolId = t.tool
                #if os(macOS)
                isRightPanelVisible = true
                #else
                iOSPage = 2
                #endif
            }
        }
        .transaction { tx in
            tx.animation = nil
        }
        .onAppear {
            // CC Bridge: 启动时自动连接（baseURL 是内置常量 ws://127.0.0.1:7890/cc）
            if let url = URL(string: APIProvider.ccBridge.baseURL) {
                CCBridgeWebSocketClient.shared.connect(url: url)
            }
            manager.syncSystemColorScheme(colorScheme)
            #if os(iOS)
            let top = screenSafeAreaTop
            if top > 0 { topSafeAreaInset = top }

            #if DEBUG
            // [PROBE 贴纸] 自动选中 probe conversation + 进编辑模式（XCUITest 用）
            if ProbeStickerSeed.shouldAutoSelectProbeConv {
                PROBE("[PROBE 贴纸 ContentView.onAppear] auto-select probe conv")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    let descriptor = FetchDescriptor<Conversation>(
                        predicate: #Predicate { $0.id == "probe-sticker-conv-1" }
                    )
                    if let conv = try? modelContext.fetch(descriptor).first {
                        viewModel.selectedConversation = conv
                        PROBE("[PROBE 贴纸 ContentView.onAppear] selected conv id=\(conv.id)")
                        // 等 5s 让 LazyVStack 渲染出 contentHeight，再进编辑模式
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                            stickerVM.isEditingStickers = true
                            PROBE("[PROBE 贴纸 ContentView.onAppear] isEditingStickers=true")
                        }
                    } else {
                        PROBE("[PROBE 贴纸 ContentView.onAppear] probe conv NOT FOUND")
                    }
                }
            }
            #endif
            #endif
        }
        .onChange(of: colorScheme) { _, newScheme in
            manager.syncSystemColorScheme(newScheme)
        }
        #if os(macOS)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .background(
            WindowFullscreenObserver(
                isFullscreen: $isFullscreen,
                isTransitioning: $isFullscreenTransitioning,
                windowWidth: $windowWidth
            )
        )
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .memoryPalaceRequestImport)) { _ in
            showImporter = true
        }
        .sheet(isPresented: $showImporter) {
            ImportView()
                #if os(iOS)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(Theme.sidebarBg)
                #endif
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                #if os(iOS)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(.clear)
                #endif
        }
    }

    // MARK: - iOS Three-Screen Layout (ScrollView horizontal paging)
    #if os(iOS)
    private var iOSLayout: some View {
        let manager = themeManager ?? ThemeManager.shared
        let scheme = manager.activeScheme
        let style = manager.currentBackgroundStyle
        // Wallpaper 走 UIKit 层（PagingViewController.view 底层 UIImageView + CAGradientLayer），
        // 不用 SwiftUI `.background`——A10 实测 SwiftUI .background content frame 响应
        // keyboard safeArea 等比放大 13%，导致"背景跟着键盘动"。
        // 见 docs/research-wallpaper-uikit-layer.md + docs/plan-wallpaper-uikit-layer.md。
        let wallpaperConfig = WallpaperConfig(
            fill: Theme.mainBg,
            imageURL: manager.currentBackgroundImageURL,
            saturation: 0.92,
            opacity: style.resolvedOpacity(for: scheme),
            offsetX: style.resolvedOffsetX,
            offsetY: style.resolvedOffsetY,
            gradientColors: wallpaperGradientColors(for: scheme)
        )
        // 路线 B 下 container 不变，外层 App.body 的 .id(profile.id) 已经保证 profile
        // 切换时整棵 ContentView re-init，PagingContainerView 自动跟着新建。不需要这里
        // 额外 .id() hack。
        return PagingContainerView(
            listPage: AnyView(injectPagingEnv(iOSListPage)),
            chatPage: AnyView(injectPagingEnv(iOSChatPage)),
            dashPage: AnyView(injectPagingEnv(iOSDashboardPage)),
            currentPage: $iOSPage,
            disableScroll: stickerVM.isEditingStickers,
            initialPage: 1,
            wallpaper: wallpaperConfig,
            // B2 窄版：流式期间 skip updatePages。读 isStreaming 会让 ContentView.body
            // 在流式开始/结束各重算一次（边界时刻触发更新 rootView），非流式期间无成本。
            isStreaming: viewModel.providerRouter.isStreaming
        )
        .ignoresSafeArea()
        .sensoryFeedback(.impact(weight: .light), trigger: iOSPage)
        .onChange(of: iOSPage) { oldPage, newPage in
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            // 从聊天页切回 sidebar 时立刻 flush 挂起的重排 → 用户几乎看不到 3s 等待
            if oldPage == 1 && newPage == 0 {
                viewModel.flushPendingRefresh()
            }
        }
        .onChange(of: stickerVM.isEditingStickers) { _, editing in
            setStickerEditScrollLock(editing)
        }
        .onChange(of: globalWBManager?.books.count) { _, _ in
            viewModel.globalWorldBookEntries = (globalWBManager?.enabledBooks ?? []).flatMap { $0.entries }
        }
        .onAppear {
            viewModel.globalWorldBookEntries = (globalWBManager?.enabledBooks ?? []).flatMap { $0.entries }
        }
        .onChange(of: viewModel.selectedConversation?.id) { _, newId in
            if newId != nil && iOSPage == 0 {
                withAnimation { iOSPage = 1 }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .conversationNavigationRequested)) { _ in
            // B20 part 2: 同 conv 内点搜索结果时 selectedConversation?.id 不变，
            // 上面那条 onChange 不触发，靠这条通知补 page 切换。
            if iOSPage != 1 {
                withAnimation { iOSPage = 1 }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .notificationNavigationRequested)) { notification in
            // Phase 3.1: 用户点击本地通知后路由到对应对话
            guard let convId = notification.userInfo?["conversationId"] as? String else { return }
            let descriptor = FetchDescriptor<Conversation>(predicate: #Predicate { $0.id == convId })
            if let conv = try? modelContext.fetch(descriptor).first {
                viewModel.selectedConversation = conv
                withAnimation { iOSPage = 1 }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
    }

    /// UIViewControllerRepresentable 包的 UIHostingController 不自动继承 SwiftUI parent env，
    /// 显式把低频 env（modelContext / themeManager / globalWBManager）注入给每页。
    /// ProviderManager / ProfileManager / PresetManager 的注入**移到 PagingContainerView**
    /// 完成，避免 ContentView 订阅这 3 个 @Observable Manager 引起 body 全量重算。
    @ViewBuilder
    private func injectPagingEnv<V: View>(_ page: V) -> some View {
        let manager = themeManager ?? ThemeManager.shared
        if let wb = globalWBManager {
            page
                .environment(\.modelContext, modelContext)
                .environment(manager)
                .environment(wb)
        } else {
            page
                .environment(\.modelContext, modelContext)
                .environment(manager)
        }
    }

    /// Wallpaper overlay gradient 颜色（复刻 ChatWallpaperBackdrop.overlayColors），
    /// 按 colorScheme 区分明暗主题。SwiftUI ColorScheme → UIColor[]（UIKit 层消费）。
    private func wallpaperGradientColors(for scheme: ColorScheme) -> [UIColor] {
        if scheme == .dark {
            return [
                UIColor.black.withAlphaComponent(0.42),
                UIColor.black.withAlphaComponent(0.18),
                UIColor.black.withAlphaComponent(0.50)
            ]
        }
        return [
            UIColor.white.withAlphaComponent(0.18),
            UIColor.white.withAlphaComponent(0.04),
            UIColor.white.withAlphaComponent(0.24)
        ]
    }

    // MARK: - iOS Page indicator (debug-mode aware)

    private var pageIndicatorDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(iOSPage == i ? Theme.branchIndicator : Theme.textMuted.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
    }

    /// 从 UIApplication 直接拿屏幕 key window 的 safe area bottom，
    /// 绕开「GeometryReader 在 safe area 内时 safeAreaInsets 归零」的坑。
    private var screenSafeAreaBottom: CGFloat {
        guard
            let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first,
            let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
        else { return 0 }
        return window.safeAreaInsets.bottom
    }

    private var screenSafeAreaTop: CGFloat {
        guard
            let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first,
            let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
        else { return 0 }
        return window.safeAreaInsets.top
    }

    // pageIndicatorInZStack(proxy:) 已删除 — dead code（无 call site）。
    // 同 删 @AppStorage debugPageIndicatorModeRaw / private var debugPageIndicatorMode。

    /// 聊天页顶栏：左箭头(page 0) + 中间 PinBar(有 pin 时) + 右侧加长胶囊(⋯ Menu + 右箭头 page 2)。
    /// 当前对话标题挪进 ⋯ Menu 的 header（原顶栏中间不再显示标题）。
    /// blur 层在 CardFlowView 的 overlay（z 顺序：blur < nav HStack < Menu popover）。
    private var iOSChatTopBar: some View {
        return ZStack(alignment: .top) {
            HStack(spacing: 8) {
                // 左箭头 → page 0（对话列表）
                Button {
                    withAnimation { iOSPage = 0 }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 44, height: 44)
                        .glassEffectCompat(tint: Color.white.opacity(0.15), interactive: true, in: Circle())
                }

                // 中间：PinBar（有 pin 时）或 Spacer。Phase 3 P3.9 会在这里挂 PinnedMessageBar。
                if !viewModel.pinnedNodes.isEmpty, !pinBarHidden, viewModel.selectedConversation != nil {
                    PinnedMessageBar(
                        pinnedNodes: viewModel.pinnedNodes,
                        currentIndex: $pinCurrentIndex,
                        isHidden: $pinBarHidden,
                        onTap: handlePinBarTap,
                        onUnpinCurrent: handleUnpinCurrent,
                        onUnpinAll: {
                            viewModel.unpinAll()
                            pinCurrentIndex = 0
                        }
                    )
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)
                    .animation(.easeInOut(duration: 0.25), value: viewModel.pinnedNodes.map(\.id))
                    .animation(.easeInOut(duration: 0.25), value: pinCurrentIndex)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    Spacer(minLength: 0)
                }

                // 右侧加长胶囊：[🌿N(可选)] + ⋯(Menu) + 右箭头(page 2)
                HStack(spacing: 0) {
                    // 分支地图按钮（B20 part 2 A3）：仅当对话有非主线分支时显示
                    if branchOffMainCount > 0 {
                        Button {
                            showBranchMap = true
                        } label: {
                            HStack(spacing: 3) {
                                Text("🌿")
                                    .font(.system(size: 13))
                                Text("\(branchOffMainCount)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(Theme.textSecondary)
                            }
                            .frame(height: 44)
                            .padding(.horizontal, 10)
                            .contentShape(Rectangle())
                        }
                    }

                    Menu {
                        if let conv = viewModel.selectedConversation {
                            Section {
                                Text(conv.title)
                            }
                            Button {
                                showChangeProjectSheet = true
                            } label: {
                                Label("改标签", systemImage: "tag")
                            }
                            Button {
                                conv.isFavorite.toggle()
                            } label: {
                                Label(conv.isFavorite ? "取消收藏" : "收藏",
                                      systemImage: conv.isFavorite ? "star.slash" : "star")
                            }
                            Button {
                                renameText = conv.title
                                showRenameAlert = true
                            } label: {
                                Label("重命名", systemImage: "pencil")
                            }
                            Divider()
                            Button(role: .destructive) {
                                viewModel.softDeleteConversation(conv)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Theme.textSecondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }

                    Button {
                        withAnimation { iOSPage = 2 }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Theme.textSecondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                }
                .glassEffectCompat(tint: Color.white.opacity(0.15), interactive: true, in: Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .animation(.easeInOut(duration: 0.25), value: pinBarHidden)
        }
    }

    // MARK: - Pin Bar handlers（从 CardFlowView 挪上来，Phase 3）

    private func handlePinBarTap() {
        let pins = viewModel.pinnedNodes
        guard !pins.isEmpty else { return }
        let idx = min(pinCurrentIndex, pins.count - 1)
        let target = pins[idx]
        if viewModel.currentPath.contains(where: { $0.id == target.id }) {
            viewModel.scrollToNodeId = target.id
            viewModel.highlightedNodeId = target.id
            let targetId = target.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if viewModel.highlightedNodeId == targetId {
                    viewModel.highlightedNodeId = nil
                }
            }
        }
        pinCurrentIndex = (idx + 1) % pins.count
    }

    private func handleUnpinCurrent() {
        let pins = viewModel.pinnedNodes
        guard !pins.isEmpty else { return }
        let idx = min(pinCurrentIndex, pins.count - 1)
        let target = pins[idx]
        target.isPinned = false
        target.pinnedAt = nil
        if pinCurrentIndex >= pins.count - 1 {
            pinCurrentIndex = 0
        }
    }

    private var iOSListPage: some View {
        SidebarView(
            searchText: $searchText,
            showFavoritesOnly: $showFavoritesOnly,
            showTrash: $showTrash,
            showImporter: $showImporter,
            showSettings: $showSettings,
            viewModel: viewModel,
            profileId: profileManager?.currentProfile.id ?? ""
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var iOSChatPage: some View {
        // wallpaper 已挪到 iOSLayout 外层（chat page child HC 之外）以避开键盘 safeArea 影响，
        // 这里不再挂 .background { ChatWallpaperBackdrop }。chat page ZStack 透明，让外层
        // wallpaper 透过来。
        ZStack(alignment: .top) {
            if viewModel.selectedConversation != nil {
                CardFlowView(viewModel: viewModel, stickerVM: stickerVM)
            } else {
                EmptyStateView(showImporter: $showImporter, profileId: profileManager?.currentProfile.id ?? "")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .top) {
            iOSChatTopBar
        }
        // home indicator 区 hit shield 已挪到 UIKit 层（PagingViewController.homeIndicatorShield）。
        // SwiftUI overlay 在 child HC（clipsToBounds=true）+ chat 页 additionalSafeAreaInsets
        // 动态变化下命中条会漂，时灵时不灵。改 UIKit 顶层 UIView + window.safeAreaInsets.bottom
        // 命中链稳定。
        .alert("重命名", isPresented: $showRenameAlert) {
            TextField("对话名称", text: $renameText)
            Button("取消", role: .cancel) { }
            Button("确认") {
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, let conv = viewModel.selectedConversation {
                    conv.title = trimmed
                    conv.updateTime = Date()
                    viewModel.markConversationDirty()
                }
            }
        }
        .sheet(isPresented: $showChangeProjectSheet) {
            if let conv = viewModel.selectedConversation {
                TagPickerPopover(
                    conversationId: conv.id,
                    profileId: profileManager?.currentProfile.id ?? ""
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.sidebarBg)
            }
        }
        .sheet(isPresented: $showBranchMap) {
            BranchMapSheet(
                viewModel: viewModel,
                onNavigateToNode: { nodeId in
                    if let conv = viewModel.selectedConversation {
                        viewModel.navigateToNode(nodeId: nodeId, conversation: conv, context: modelContext)
                    }
                }
            )
            .presentationBackground(Theme.sidebarBg)
        }
        .onChange(of: viewModel.selectedConversation?.id) { _, _ in
            pinCurrentIndex = 0
            pinBarHidden = false
        }
    }

    /// 当前对话有多少条非主线分支（用于决定是否显示 🌿 按钮 + 角标 N）。
    /// 含嵌套分支（DFS 全树），跟 BranchMapSheet 显示口径一致。空则按钮隐藏。
    /// B20 part 2 A3 反馈 + 第二轮 1+2 修：count 跟 sheet list 自洽。
    private var branchOffMainCount: Int {
        viewModel.collectAllBranches().count
    }

    private var iOSDashboardPage: some View {
        RightPanelView(
            selectedToolId: $selectedToolId,
            viewModel: viewModel,
            stickerVM: stickerVM
        )
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.sidebarBg.ignoresSafeArea())
    }

    /// 编辑贴纸时彻底禁用所有滚动。路线 C 下水平 paging 已由 PagingContainerView.disableScroll
    /// 管（UIScrollView.isScrollEnabled），这里只管 chat page 内 CardFlowView 的竖直 ScrollView。
    /// （旧的 disableBounceInSubviews / findCollectionView 路线 C 下 TabView 没了，已删）
    private func setStickerEditScrollLock(_ editing: Bool) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return }
        setAllScrollViewsEnabled(!editing, in: window)
    }

    private func setAllScrollViewsEnabled(_ enabled: Bool, in view: UIView) {
        if let scrollView = view as? UIScrollView {
            scrollView.isScrollEnabled = enabled
        }
        for subview in view.subviews {
            setAllScrollViewsEnabled(enabled, in: subview)
        }
    }
    #endif

    // MARK: - macOS Layout
    private var normalLayout: some View {
        NavigationSplitView {
            SidebarView(
                searchText: $searchText,
                showFavoritesOnly: $showFavoritesOnly,
                showTrash: $showTrash,
                showImporter: $showImporter,
                showSettings: $showSettings,
                viewModel: viewModel,
                profileId: profileManager?.currentProfile.id ?? ""
            )
            .navigationSplitViewColumnWidth(min: sidebarMinWidth, ideal: 300, max: sidebarMaxWidth)
        } detail: {
            detailContent
        }
        .onChange(of: viewModel.selectedConversation?.id) { _, _ in }
    }

    private var detailContent: some View {
        HStack(alignment: .top, spacing: 0) {
            Group {
                if viewModel.selectedConversation != nil {
                    CardFlowView(viewModel: viewModel, stickerVM: stickerVM)
                        #if os(macOS)
                        .navigationBarBackButtonHidden(true)
                        #endif
                } else {
                    EmptyStateView(showImporter: $showImporter, profileId: profileManager?.currentProfile.id ?? "")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            #if os(macOS)
            if isRightPanelVisible {
                PanelDivider(
                    panelWidth: $calendarWidth,
                    minWidth: 200,
                    maxWidth: max(calendarMaxWidth(in: detailWidth), 200)
                )
                RightPanelView(selectedToolId: $selectedToolId, viewModel: viewModel, stickerVM: stickerVM)
                    .frame(width: min(calendarWidth, max(calendarMaxWidth(in: detailWidth), 200)))
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { detailWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, w in detailWidth = w }
            }
        )
    }

    #if os(macOS)
    private var fullscreenLayout: some View {
        HSplitView {
            if isSidebarVisible {
                SidebarView(
                    searchText: $searchText,
                    showFavoritesOnly: $showFavoritesOnly,
                    showTrash: $showTrash,
                    showImporter: $showImporter,
                    showSettings: $showSettings,
                    viewModel: viewModel,
                    profileId: profileManager?.currentProfile.id ?? ""
                )
                .frame(minWidth: sidebarMinWidth, idealWidth: 300, maxWidth: sidebarMaxWidth)
                .background(Theme.sidebarBg)
            }

            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    DetailTopBar(
                        isSidebarVisible: $isSidebarVisible,
                        showImporter: $showImporter
                    )

                    if viewModel.selectedConversation != nil {
                        CardFlowView(viewModel: viewModel, stickerVM: stickerVM)
                            .navigationBarBackButtonHidden(true)
                    } else {
                        EmptyStateView(showImporter: $showImporter, profileId: profileManager?.currentProfile.id ?? "")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.mainBg)

                if isRightPanelVisible {
                    PanelDivider(
                        panelWidth: $calendarWidth,
                        minWidth: 200,
                        maxWidth: max(calendarMaxWidth(in: detailWidth), 200)
                    )
                    RightPanelView(selectedToolId: $selectedToolId, viewModel: viewModel, stickerVM: stickerVM)
                        .frame(width: min(calendarWidth, max(calendarMaxWidth(in: detailWidth), 200)))
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { detailWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, w in detailWidth = w }
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    #endif

    private var rightPanelCornerButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isRightPanelVisible.toggle()
            }
        } label: {
            Image(systemName: "sidebar.right")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(isRightPanelVisible ? Theme.branchIndicator : Theme.textSecondary)
                .frame(width: 38, height: 38)
                .background(
                    Circle()
                        .fill(Theme.mainBg.opacity(0.94))
                )
                .overlay(
                    Circle()
                        .stroke(Theme.accent.opacity(0.45), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Detail Top Bar (fullscreen only)

struct DetailTopBar: View {
    @Binding var isSidebarVisible: Bool
    @Binding var showImporter: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isSidebarVisible.toggle()
                }
            } label: {
                Image(systemName: isSidebarVisible ? "sidebar.left" : "sidebar.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textSecondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Button("导入") {
                showImporter = true
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(Theme.branchIndicator)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.mainBg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.accent.opacity(0.45))
                .frame(height: 1)
        }
    }
}

#if os(macOS)
// MARK: - Fullscreen Observer

struct WindowFullscreenObserver: NSViewRepresentable {
    @Binding var isFullscreen: Bool
    @Binding var isTransitioning: Bool
    @Binding var windowWidth: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            context.coordinator.attach(
                to: view.window,
                onStateChange: { full, transitioning in
                    isFullscreen = full
                    isTransitioning = transitioning
                },
                onWidthChange: { width in
                    windowWidth = width
                }
            )
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(
            to: nsView.window,
            onStateChange: { full, transitioning in
                isFullscreen = full
                isTransitioning = transitioning
            },
            onWidthChange: { width in
                windowWidth = width
            }
        )
    }

    final class Coordinator {
        private weak var window: NSWindow?
        private var observers: [NSObjectProtocol] = []
        private var onStateChange: ((Bool, Bool) -> Void)?
        private var onWidthChange: ((CGFloat) -> Void)?

        deinit {
            removeObservers()
        }

        func attach(to window: NSWindow?, onStateChange: @escaping (Bool, Bool) -> Void, onWidthChange: @escaping (CGFloat) -> Void) {
            self.onStateChange = onStateChange
            self.onWidthChange = onWidthChange
            guard let window else { return }
            if self.window !== window {
                removeObservers()
                self.window = window
                installObservers(for: window)
                // 保持 900 的最小宽度，避免日历面板在边界尺寸下反复折叠
                window.minSize.width = 900
            }
            onStateChange(window.styleMask.contains(.fullScreen), false)
            onWidthChange(window.frame.width)
        }

        private func installObservers(for window: NSWindow) {
            let center = NotificationCenter.default
            observers = [
                center.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main) { [weak self, weak window] _ in
                    guard let self, let window else { return }
                    self.onStateChange?(window.styleMask.contains(.fullScreen), true)
                },
                center.addObserver(forName: NSWindow.willExitFullScreenNotification, object: window, queue: .main) { [weak self, weak window] _ in
                    guard let self, let window else { return }
                    self.onStateChange?(window.styleMask.contains(.fullScreen), true)
                },
                center.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main) { [weak self, weak window] _ in
                    guard let self, let window else { return }
                    self.onStateChange?(window.styleMask.contains(.fullScreen), true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                        self.onStateChange?(window.styleMask.contains(.fullScreen), false)
                    }
                },
                center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { [weak self, weak window] _ in
                    guard let self, let window else { return }
                    self.onStateChange?(window.styleMask.contains(.fullScreen), true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                        self.onStateChange?(window.styleMask.contains(.fullScreen), false)
                    }
                },
                center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self, weak window] _ in
                    guard let self, let window else { return }
                    self.onWidthChange?(window.frame.width)
                }
            ]
        }

        private func removeObservers() {
            let center = NotificationCenter.default
            observers.forEach(center.removeObserver)
            observers.removeAll()
        }
    }
}
#endif

// MARK: - Panel Divider

struct PanelDivider: View {
    @Binding var panelWidth: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    @State private var startWidth: CGFloat = 0
    @State private var isDragging = false
    @State private var hasResizeCursor = false

    var body: some View {
        Color.clear
            .frame(width: 8)
            .contentShape(Rectangle())
            .overlay(
                Rectangle()
                    .fill(Theme.accent.opacity(0.45))
                    .frame(width: 1)
            )
            #if os(macOS)
            .onHover { hovering in
                updateResizeCursor(isHovering: hovering)
            }
            .onDisappear(perform: releaseResizeCursor)
            #endif
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            startWidth = panelWidth
                        }
                        panelWidth = min(maxWidth, max(minWidth, startWidth - value.translation.width))
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
    }

    #if os(macOS)
    private func updateResizeCursor(isHovering: Bool) {
        if isHovering {
            guard !hasResizeCursor else { return }
            hasResizeCursor = true
            NSCursor.resizeLeftRight.push()
        } else {
            releaseResizeCursor()
        }
    }

    private func releaseResizeCursor() {
        guard hasResizeCursor else { return }
        hasResizeCursor = false
        NSCursor.pop()
    }
    #endif
}

// MARK: - Empty State

struct EmptyStateView: View {
    @Binding var showImporter: Bool
    let profileId: String
    @Query private var conversations: [Conversation]

    init(showImporter: Binding<Bool>, profileId: String) {
        self._showImporter = showImporter
        self.profileId = profileId
        _conversations = Query(filter: #Predicate<Conversation> { $0.profileId == profileId })
    }

    var body: some View {
        VStack(spacing: 20) {
            if conversations.isEmpty {
                Image(systemName: "tray")
                    .font(.system(size: 48))
                    .foregroundColor(Theme.textMuted)
                Text("还没有对话")
                    .font(.title2)
                    .foregroundColor(Theme.textSecondary)
                Text("导入你的 ChatGPT 对话，开始构建记忆宫殿")
                    .foregroundColor(Theme.textMuted)
                Button("导入 conversations.json") {
                    showImporter = true
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.branchIndicator)
            } else {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 48))
                    .foregroundColor(Theme.textMuted)
                Text("选择一条对话")
                    .font(.title2)
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

