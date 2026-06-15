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
    var currentPath: [MessageNode] = []   // The currently displayed path of cards
    var branchChoices: [String: Int] = [:] // nodeId -> chosen child index
    var isLoading: Bool = false
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

    // MARK: - Load Conversation

    /// Background-computed tree data (pure value types, safe to cross threads)
    private struct TreeData {
        let effectiveChildrenMap: [String: [String]]
        let rootId: String?
        let mainPathIds: Set<String>
        let pathNodeIds: [String]
        let bubbledBranches: [String: String]
        let displayableCount: Int
        let allNodeIds: Set<String>
    }

    /// BranchMap v6 用：单击节点 = 快切 currentPath。

    /// 旧入口保留：搜索结果 / 外部跳转 用全量 reload（含 fetch）。
    /// 搜索结果点击的统一入口（B20 part 2）。
    /// - 300ms 同 nodeId 去抖，吃掉用户连点
    /// - 主线 node：path 不切（保持 conversation.currentNodeId 主线）+ 仅 scroll
    /// - 分支 node：切 branch（loadConversation scrollTargetNodeId）+ 弹"已切换到分支"
    /// - 不论主/分支：都发 conversationNavigationRequested 通知让 ContentView 切 page 0→1
    /// Build path for selected conversation (fetch + tree computation on background thread)
    /// - scrollTargetNodeId: if set, build path through this node instead of conversation.currentNodeId
    /// Compute the main-path nodeId set for a given conversation snapshot.
    /// 给定 nodes 和 currentNodeId，按 buildTreeInBackground 同套算法
    /// （反向 trace mainPath + 正向走选 child）算出主线 nodeId Set。
    /// 用于搜索过滤、UI 高亮等不需要全套 TreeData 的场景。
    /// 算法跟 buildTreeInBackground 必须一致（搜索结果不能跟 chat 显示打架）。
    /// Heavy lifting on background thread: fetch nodes, build tree, compute path (all with pure IDs)
    private static func buildTreeInBackground(convId: String, profileId: String, currentNodeId: String, container: ModelContainer) -> TreeData {
        let bgContext = ModelContext(container)

        // Fetch all nodes for this conversation
        let descriptor = FetchDescriptor<MessageNode>(
            predicate: #Predicate<MessageNode> { node in node.conversationId == convId && node.profileId == profileId }
        )
        let nodes = (try? bgContext.fetch(descriptor)) ?? []

        // Lightweight node data for pure computation
        var infoMap: [String: NodeInfo] = [:]
        infoMap.reserveCapacity(nodes.count)
        for node in nodes {
            infoMap[node.id] = NodeInfo(id: node.id, role: node.role, hasContent: node.hasDisplayableContent, isDeleted: node.isDeleted, parentId: node.parentId, childrenIds: node.childrenIds)
        }

        // Chase missing ancestors on background context
        var missingIds = Set<String>()
        for info in infoMap.values {
            if let pid = info.parentId, !pid.isEmpty, infoMap[pid] == nil {
                missingIds.insert(pid)
            }
        }
        var toChase = missingIds
        while !toChase.isEmpty {
            var nextChase = Set<String>()
            for mid in toChase {
                let targetId = mid
                let targetProfileId = profileId
                let desc = FetchDescriptor<MessageNode>(
                    predicate: #Predicate<MessageNode> { node in node.id == targetId && node.profileId == targetProfileId }
                )
                if let found = try? bgContext.fetch(desc).first {
                    infoMap[found.id] = NodeInfo(id: found.id, role: found.role, hasContent: found.hasDisplayableContent, isDeleted: found.isDeleted, parentId: found.parentId, childrenIds: found.childrenIds)
                    if let pid = found.parentId, !pid.isEmpty, infoMap[pid] == nil {
                        nextChase.insert(pid)
                    }
                }
            }
            toChase = nextChase
        }

        // Build effective children map
        var effectiveChildren: [String: [String]] = [:]
        effectiveChildren.reserveCapacity(infoMap.count)
        for (nodeId, info) in infoMap {
            effectiveChildren[nodeId] = info.childrenIds.filter { infoMap[$0] != nil }
        }
        for (nodeId, info) in infoMap {
            if let pid = info.parentId, infoMap[pid] != nil {
                if !(effectiveChildren[pid]?.contains(nodeId) ?? false) {
                    effectiveChildren[pid, default: []].append(nodeId)
                }
            }
        }

        // Trace main path from currentNodeId to root — 一次循环既建 mainPathIds 又确定 rootId
        //
        // 之前用 `infoMap.values.first(where:)` 选 root 是 bug：Swift dict 迭代顺序
        // 非确定性，多个 parentId==nil 候选（真 root + 孤立 system/tool 节点等）时每次
        // 可能选到不同节点，导致同一对话 pathNodeIds 随机返回 0 或 N（"抽盲盒"式空白）。
        // 详见 docs/research-conversation-blank-bug.md。
        var mainPathIds = Set<String>()
        var rootId: String? = nil
        var traceId: String? = currentNodeId
        while let nid = traceId, let info = infoMap[nid] {
            mainPathIds.insert(nid)
            if info.parentId == nil || infoMap[info.parentId ?? ""] == nil {
                rootId = nid   // 最顶层的可达祖先
            }
            traceId = info.parentId
        }

        // Fallback：currentNodeId 不在 infoMap（脏数据/stale currentNodeId）时，
        // 按 id 字典序选 parentId==nil 的最小者 — 至少保证确定性
        if rootId == nil {
            let candidates = infoMap.values.filter { $0.parentId == nil || infoMap[$0.parentId ?? ""] == nil }
            rootId = candidates.map(\.id).min()
        }

        // Build display path (collect node IDs + bubbled branches)
        var pathNodeIds: [String] = []
        var bubbledBranches: [String: String] = [:]

        if let rootId = rootId {
            var visited = Set<String>()
            var currentId: String? = rootId
            var lastDisplayedId: String? = nil

            while let nid = currentId, let info = infoMap[nid], !visited.contains(nid) {
                visited.insert(nid)
                let isDisplayable = (info.role == "user" || info.role == "assistant") && info.hasContent && !info.isDeleted
                let children = effectiveChildren[nid] ?? []

                if isDisplayable {
                    pathNodeIds.append(nid)
                    lastDisplayedId = nid
                }
                if children.count > 1 && !isDisplayable {
                    if let lastId = lastDisplayedId {
                        bubbledBranches[lastId] = nid
                    }
                }
                if children.isEmpty {
                    break
                } else if children.count == 1 {
                    currentId = children[0]
                } else {
                    let mainChild = children.first(where: { mainPathIds.contains($0) })
                    currentId = mainChild ?? children[0]
                }
            }
        }

        let displayableCount = infoMap.values.filter {
            ($0.role == "user" || $0.role == "assistant") && $0.hasContent && !$0.isDeleted
        }.count

        return TreeData(
            effectiveChildrenMap: effectiveChildren,
            rootId: rootId,
            mainPathIds: mainPathIds,
            pathNodeIds: pathNodeIds,
            bubbledBranches: bubbledBranches,
            displayableCount: displayableCount,
            allNodeIds: Set(infoMap.keys)
        )
    }

    /// Apply background results on main thread (re-fetch managed objects for UI)
    /// Fetch ancestor nodes missing from nodeMap — query only the missing IDs
    /// Build effective children map from actual parent→child relationships
    /// Get children IDs for a node
    // MARK: - Path Building

    // MARK: - Branch Navigation

    /// "你在哪"位置 hint — 给 BranchMapSheet v2 mini-map 标当前位置用。
    /// 直接读 highlightedNodeId（最近交互过的 node：搜索点击 / pin 跳转 / branch 切换都会设）。
    /// 3s 后会被清空，sheet 打开时如果是 nil 就不画位置 marker（视觉降级，不出 false 信息）。
    /// 详见 docs/plan-branch-map-v2-minimap.md Q1。
    var currentPositionHint: String? { highlightedNodeId }

    /// 给定 child nodeId（某条 branch 的入口），顺向走到 leaf 数 displayable node 数。
    /// 分叉时优先选 mainPathIds 里的 child，跟 buildTreeInBackground 一致。
    /// 用于分支地图显示"分支 N 共 X 条"。B20 part 2 A3 反馈。
    /// 一条分支的完整描述（含嵌套）。给 BranchMapSheet v2 用。
    /// branchInfoMap 只覆盖当前 currentPath 上的 anchor，看不到嵌套二级分支；
    /// 这个函数 DFS 整棵 effectiveChildrenMap 树，收集所有有 ≥2 displayable
    /// children 的 anchor 的所有非"主选 child"，包括分支之中的子分支。
    /// depth=0 表示 anchor 在主线上；depth>0 表示 anchor 自己也是别人的分支。
    /// 给 collectAllBranches 用：找 anchor 在主线上能定位的"显示位置"。
    /// anchor 可能是 invisible system/tool 节点（在 mainPathIds 但不在 currentPath），
    /// 此时 currentPath.firstIndex 返回 nil。改沿 parent 链回溯，找最近的
    /// displayable + 在 currentPath 的 ancestor，取它的 index。
    // MARK: - In-Conversation Search

    // MARK: - Actions

    // MARK: - Chat (API) stored properties

    var providerRouter = ProviderRouter()
    let memoryStore: MemoryStore = SwiftDataMemoryStore()
    var streamingText = ""
    var streamingThinkingText: String = ""
    var isThinking: Bool = false
    var thinkingSummary: String = ""
    let memoryExtractWindow = 5

    // MARK: - Budget
    var budgetBlockedMessage: String? = nil
    /// Pre-send 的估算额度，发送完没 usage 时兜底扣费
    var pendingEstimatedCost: Double = 0
    /// 上一轮主对话的 token 用量（含 cache 命中数），S1 检查器显示用
    var lastTurnUsage: TokenUsage? = nil
}
