import Foundation
import SwiftData
import SwiftUI

/// 临时提示（fade-out toast）。每条新提示 id 必须新生成，
/// CardFlowView 用 .id() 做 overlay 重置触发。
struct TransientNotice: Equatable {
    let id: UUID
    let text: String
    init(_ text: String) {
        self.id = UUID()
        self.text = text
    }
}

@Observable
final class ConversationViewModel {
    var selectedConversation: Conversation?
    /// CC→记忆 反向提取用：installCCFollowUpHandler 从 loadConversation 注册时拿不到
    /// providerManager（那条路径没有）。存一份最近一次可用的，让 CC proactive 回复也能提取。
    var ccProviderManager: ProviderManager?
    var currentPath: [MessageNode] = []   // The currently displayed path of cards
    var branchChoices: [String: Int] = [:] // nodeId -> chosen child index
    var isLoading: Bool = false

    /// 当前选中对话是否正在加载。isLoading 全局单值，切对话时会泄漏到别的对话。
    /// UI 用这个 computed property 隔离。
    var isCurrentConvLoading: Bool {
        isLoading && selectedConversation != nil
    }
    /// 正在流式生成的节点 id —— 跨对话/分支精确判定打字气泡与思考链归属（防泄漏）
    var streamingNodeId: String? = nil
    var scrollToNodeId: String? = nil
    var pendingScrollNodeId: String? = nil
    var highlightedNodeId: String? = nil
    var sidebarRefreshTrigger: Int = 0
    var globalWorldBookEntries: [WorldBookEntry] = []  // View 层从 GlobalWorldBookManager 注入

    // In-conversation search
    var inConvSearchKeyword: String = ""
    var inConvMatches: [String] = []   // matched node IDs
    var inConvMatchIndex: Int = -1

    /// 临时提示文案（如"已切换到分支"），CardFlowView overlay 监听显示，
    /// id 变化触发自动 fade out。设新文案时 id 必须新生成。
    var transientNotice: TransientNotice? = nil

    /// 搜索点击去抖：300ms 内同 nodeId 重复点击直接吃掉。
    /// 不放 SidebarView 是因为它是 struct view，state 在 reload 间易丢。
    var lastNavigateNodeId: String? = nil
    var lastNavigateAt: Date? = nil

    /// Maps a displayed node id → the actual branching node id (for invisible branch points)
    var bubbledBranches: [String: String] = [:]

    /// Precomputed branch info for each node in currentPath (avoids redundant computation during rendering)
    var branchInfoMap: [String: BranchInfo] = [:]

    var nodeMap: [String: MessageNode] = [:]
    var mainPathIds: Set<String> = []
    var cachedRootId: String?

    // MARK: - Profile Switch Race Defense
    //
    // 切楼层时（ProfileManager.switchTo）会换 modelContainer，旧 Conversation /
    // MessageNode 实例被 SwiftData reset。但路线 C（UIKit PagingContainerView 嵌套
    // UIHostingController）下，旧 SwiftUI view tree 的 dismount 时序不和主 tree
    // 原子对齐，旧 CardFlowView.body 可能在 reset 后还跑一次读 selectedConversation.id
    // → fatal。Master 用 SwiftUI 原生 TabView 无此问题（同 commit phase 原子）。
    //
    // 修法：切楼层前 post .profileWillSwitch，这里 observer 把 VM 持有的所有
    // SwiftData 实例 ref 清空。旧 view body 再跑时读到 nil，不访问已 destroy 实例。
    /// profileWillSwitch observer 的 token。addObserver(forName:...:queue:using:) 返回
    /// 的是 token 不是 self，removeObserver(self) 对 block-based observer 不生效 ——
    /// 必须存 token 显式 remove。
    /// xcdoc: /documentation/foundation/notificationcenter/addobserver(forname:object:queue:using:)
    private var profileSwitchObserver: NSObjectProtocol?

    init() {
        // queue: nil → block 同步在 posting 线程（switchTo 跑在 main）跑，post() 返回时
        // clear 已经执行完，随后 currentProfile / container flip 时旧 VM 已无 SwiftData ref。
        profileSwitchObserver = NotificationCenter.default.addObserver(
            forName: .profileWillSwitch, object: nil, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.selectedConversation = nil
            self.currentPath = []
            self.nodeMap.removeAll()
            self.mainPathIds.removeAll()
            self.cachedRootId = nil
            self.branchChoices.removeAll()
            self.bubbledBranches.removeAll()
            self.branchInfoMap.removeAll()
            self.effectiveChildrenMap.removeAll()
            self.scrollToNodeId = nil
            self.pendingScrollNodeId = nil
            self.highlightedNodeId = nil
            self.inConvMatches = []
            self.inConvMatchIndex = -1
            self.inConvSearchKeyword = ""
            self.pendingRefreshTask?.cancel()
            self.pendingRefreshTask = nil
        }
    }

    deinit {
        if let observer = profileSwitchObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Sidebar 重排 debounce
    /// 内容改动（发消息 / rename / 贴纸加删）后，连续 3 秒无新改动才触发一次 sidebar 重排。
    /// 目的：浏览/快速互动时列表不抖动；点击对话本身不触发（见 loadConversation）。
    /// 下拉刷新 / 切楼层 / 进后台 / 从聊天页切回 sidebar 时立即 flush。
    private var pendingRefreshTask: Task<Void, Never>?
    private let refreshDebounceNanoseconds: UInt64 = 3_000_000_000

    /// 标记有对话内容已改动，触发（或重置）3 秒 debounce。
    func markConversationDirty() {
        pendingRefreshTask?.cancel()
        pendingRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.refreshDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            self.flushPendingRefresh()
        }
    }

    /// 立刻触发 sidebar re-fetch，取消挂起的 debounce。
    func flushPendingRefresh() {
        pendingRefreshTask?.cancel()
        pendingRefreshTask = nil
        sidebarRefreshTrigger += 1
    }

    /// Effective children for each node — rebuilt from actual parent-child relationships
    var effectiveChildrenMap: [String: [String]] = [:]

    // MARK: - Chat (API) stored properties

    var providerRouter = ProviderRouter()
    let memoryStore: MemoryStore = SwiftDataMemoryStore()
    /// Content being streamed for the current assistant response
    var streamingText = ""
    /// Reasoning content being streamed (DeepSeek / models with reasoning_content)
    var streamingThinkingText: String = ""
    /// True while reasoning_content is arriving and before regular content starts
    var isThinking: Bool = false
    /// One-sentence summary generated after thinking completes; cleared on next send
    var thinkingSummary: String = ""
    /// Recent messages to send for memory extraction
    let memoryExtractWindow = 5

    // MARK: - Budget (保险闸)
    /// 被拦截时 UI 层通过这个显示 alert；UI 消掉后置 nil
    var budgetBlockedMessage: String? = nil
    /// Pre-send 的估算额度，发送完没 usage 时兜底扣费
    var pendingEstimatedCost: Double = 0
    /// 上一轮主对话的 token 用量（含 cache 命中数），S1 检查器显示用
    var lastTurnUsage: TokenUsage? = nil
    var turnStartTime: Date? = nil   // PR: Token 统计——记一轮耗时
}
