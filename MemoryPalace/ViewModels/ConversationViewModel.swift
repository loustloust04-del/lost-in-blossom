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
    private var lastNavigateNodeId: String? = nil
    private var lastNavigateAt: Date? = nil

    /// Maps a displayed node id → the actual branching node id (for invisible branch points)
    var bubbledBranches: [String: String] = [:]

    /// Precomputed branch info for each node in currentPath (avoids redundant computation during rendering)
    var branchInfoMap: [String: BranchInfo] = [:]

    private var nodeMap: [String: MessageNode] = [:]
    private var mainPathIds: Set<String> = []
    private var cachedRootId: String?

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
    private var effectiveChildrenMap: [String: [String]] = [:]

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

    /// BranchMap v6 用：拍一份只读快照（root + nodeMap + childrenMap + currentPath ids）
    /// 让 sheet view 不直接碰 private 状态。
    struct BranchMapSnapshot {
        let rootId: String
        let nodeMap: [String: MessageNode]
        let childrenMap: [String: [String]]
        let currentPathIds: Set<String>
        let mainPathIds: Set<String>   // v10: conversation 永久主路径（切 currentPath 不变）
    }

    func branchMapSnapshot() -> BranchMapSnapshot? {
        guard let root = cachedRootId, nodeMap[root] != nil else { return nil }
        return BranchMapSnapshot(
            rootId: root,
            nodeMap: nodeMap,
            childrenMap: effectiveChildrenMap,
            currentPathIds: Set(currentPath.map { $0.id }),
            mainPathIds: mainPathIds
        )
    }

    /// BranchMap v6 用：单击节点 = 快切 currentPath。
    /// 不走 loadConversation（那是异步全量 buildTree，200ms+）；
    /// 沿 nodeId 的 parent 链回 root，对每个 multi-child anchor 设 branchChoices = next-child idx，
    /// 然后 rebuildPath() 主线程同步重算 currentPath。流畅秒切。
    func navigateToNodeFast(nodeId: String) {
        guard nodeMap[nodeId] != nil else { return }

        var current: String? = nodeId
        var lastVisited: String? = nil
        var visited = Set<String>()
        while let id = current, !visited.contains(id) {
            visited.insert(id)
            let kids = effectiveChildrenMap[id] ?? []
            if kids.count > 1, let next = lastVisited, let idx = kids.firstIndex(of: next) {
                branchChoices[id] = idx
            }
            lastVisited = id
            current = nodeMap[id]?.parentId
        }

        rebuildPath()
        highlightedNodeId = nodeId
        pendingScrollNodeId = nodeId
    }

    /// 旧入口保留：搜索结果 / 外部跳转 用全量 reload（含 fetch）。
    func navigateToNode(nodeId: String, conversation: Conversation, context: ModelContext) {
        pendingScrollNodeId = nodeId
        loadConversation(conversation, context: context, scrollTargetNodeId: nodeId)
        NotificationCenter.default.post(name: .conversationNavigationRequested, object: nil)
    }

    /// 搜索结果点击的统一入口（B20 part 2）。
    /// - 300ms 同 nodeId 去抖，吃掉用户连点
    /// - 主线 node：path 不切（保持 conversation.currentNodeId 主线）+ 仅 scroll
    /// - 分支 node：切 branch（loadConversation scrollTargetNodeId）+ 弹"已切换到分支"
    /// - 不论主/分支：都发 conversationNavigationRequested 通知让 ContentView 切 page 0→1
    func navigateToSearchResult(nodeId: String, conversation: Conversation, context: ModelContext) {
        // 去抖
        let now = Date()
        if let last = lastNavigateAt, lastNavigateNodeId == nodeId,
           now.timeIntervalSince(last) < 0.3 {
            return
        }
        lastNavigateNodeId = nodeId
        lastNavigateAt = now

        // 判断是否在主线
        let cid = conversation.id
        let pid = conversation.profileId
        let nodesDesc = FetchDescriptor<MessageNode>(
            predicate: #Predicate<MessageNode> { $0.conversationId == cid && $0.profileId == pid }
        )
        let allNodes = (try? context.fetch(nodesDesc)) ?? []
        let mainPathSet = Self.computeMainPathSet(nodes: allNodes, currentNodeId: conversation.currentNodeId)
        let isOnMainPath = mainPathSet.contains(nodeId)

        pendingScrollNodeId = nodeId

        if isOnMainPath {
            // 主线 node：用默认 currentNodeId 重建 path（path 维持原样），仅 scroll
            loadConversation(conversation, context: context)
        } else {
            // 分支 node：切到那条 branch + toast 提示
            loadConversation(conversation, context: context, scrollTargetNodeId: nodeId)
            transientNotice = TransientNotice("已切换到分支")
        }

        // 触发 page 0→1（同 conv 时 selectedConversation?.id 不变 onChange 不响应）
        NotificationCenter.default.post(name: .conversationNavigationRequested, object: nil)
    }

    /// Build path for selected conversation (fetch + tree computation on background thread)
    /// - scrollTargetNodeId: if set, build path through this node instead of conversation.currentNodeId
    func loadConversation(_ conversation: Conversation, context: ModelContext, scrollTargetNodeId: String? = nil) {
        #if DEBUG
        let loadT0 = CFAbsoluteTimeGetCurrent()
        print(String(format: "[PERF] loadConversation start convId=%@ t=%.3f", conversation.id, loadT0))
        #endif

        // 会话巩固：切换对话时刷新旧会话的记忆衰减
        let profileId = UserDefaults.standard.string(forKey: "lastProfileId") ?? ""
        consolidateSessionMemories(profileId: profileId, context: context)
        #if DEBUG
        let tConsolidate = CFAbsoluteTimeGetCurrent()
        print(String(format: "[PERF] loadConversation consolidate=%.0fms", (tConsolidate - loadT0) * 1000))
        #endif

        selectedConversation = conversation
        // 点击对话本身不影响排序（旧逻辑 lastOpenedAt = Date() + sidebarRefreshTrigger++
        // 会让对话立刻跳到列表顶部，粟粟的新语义是"纯浏览不打乱列表"）。
        // 真正的内容改动（发消息/rename/贴纸）走 markConversationDirty() 的 3s debounce。
        isLoading = true
        currentPath = []
        branchChoices.removeAll()
        bubbledBranches.removeAll()
        nodeMap.removeAll()
        cachedRootId = nil
        effectiveChildrenMap.removeAll()
        branchInfoMap.removeAll()

        let convId = conversation.id
        let convProfileId = conversation.profileId
        let currentNodeId = scrollTargetNodeId ?? conversation.currentNodeId
        let container = context.container

        DispatchQueue.global(qos: .userInitiated).async {
            #if DEBUG
            let bgT0 = CFAbsoluteTimeGetCurrent()
            #endif
            let treeData = Self.buildTreeInBackground(convId: convId, profileId: convProfileId, currentNodeId: currentNodeId, container: container)
            #if DEBUG
            let bgT1 = CFAbsoluteTimeGetCurrent()
            print(String(format: "[PERF] buildTreeInBackground=%.0fms nodes=%d", (bgT1 - bgT0) * 1000, treeData.allNodeIds.count))
            #endif

            DispatchQueue.main.async { [self] in
                guard selectedConversation?.id == convId else { return }
                #if DEBUG
                let applyT0 = CFAbsoluteTimeGetCurrent()
                #endif
                applyTreeData(treeData, conversation: conversation, context: context)
                #if DEBUG
                let applyT1 = CFAbsoluteTimeGetCurrent()
                print(String(format: "[PERF] applyTreeData=%.0fms loadTotal=%.0fms", (applyT1 - applyT0) * 1000, (applyT1 - loadT0) * 1000))
                #endif
            }
        }
    }

    /// Compute the main-path nodeId set for a given conversation snapshot.
    /// 给定 nodes 和 currentNodeId，按 buildTreeInBackground 同套算法
    /// （反向 trace mainPath + 正向走选 child）算出主线 nodeId Set。
    /// 用于搜索过滤、UI 高亮等不需要全套 TreeData 的场景。
    /// 算法跟 buildTreeInBackground 必须一致（搜索结果不能跟 chat 显示打架）。
    static func computeMainPathSet(nodes: [MessageNode], currentNodeId: String) -> Set<String> {
        struct NI {
            let role: String
            let hasContent: Bool
            let isDeleted: Bool
            let parentId: String?
            let childrenIds: [String]
        }
        var infoMap: [String: NI] = [:]
        infoMap.reserveCapacity(nodes.count)
        for n in nodes {
            infoMap[n.id] = NI(role: n.role, hasContent: !n.content.isEmpty, isDeleted: n.isDeleted, parentId: n.parentId, childrenIds: n.childrenIds)
        }

        // 反向 trace mainPathIds + 找 rootId
        var mainPathIds = Set<String>()
        var rootId: String? = nil
        var traceId: String? = currentNodeId
        while let nid = traceId, let info = infoMap[nid] {
            mainPathIds.insert(nid)
            if info.parentId == nil || infoMap[info.parentId ?? ""] == nil {
                rootId = nid
            }
            traceId = info.parentId
        }
        if rootId == nil {
            let candidates = infoMap.compactMap { (k, v) -> String? in
                (v.parentId == nil || infoMap[v.parentId ?? ""] == nil) ? k : nil
            }
            rootId = candidates.min()
        }

        // effective children（过滤掉 fetch 不到的孩子）
        var effectiveChildren: [String: [String]] = [:]
        effectiveChildren.reserveCapacity(infoMap.count)
        for (nid, info) in infoMap {
            effectiveChildren[nid] = info.childrenIds.filter { infoMap[$0] != nil }
        }
        for (nid, info) in infoMap {
            if let pid = info.parentId, infoMap[pid] != nil {
                if !(effectiveChildren[pid]?.contains(nid) ?? false) {
                    effectiveChildren[pid, default: []].append(nid)
                }
            }
        }

        // 正向走主线，分叉时选 mainPathIds 里的 child
        var pathNodeIds = Set<String>()
        if let rootId = rootId {
            var visited = Set<String>()
            var currentId: String? = rootId
            while let nid = currentId, let info = infoMap[nid], !visited.contains(nid) {
                visited.insert(nid)
                let isDisplayable = (info.role == "user" || info.role == "assistant") && info.hasContent && !info.isDeleted
                let children = effectiveChildren[nid] ?? []
                if isDisplayable {
                    pathNodeIds.insert(nid)
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
        return pathNodeIds
    }

    /// Heavy lifting on background thread: fetch nodes, build tree, compute path (all with pure IDs)
    private static func buildTreeInBackground(convId: String, profileId: String, currentNodeId: String, container: ModelContainer) -> TreeData {
        let bgContext = ModelContext(container)

        // Fetch all nodes for this conversation
        let descriptor = FetchDescriptor<MessageNode>(
            predicate: #Predicate<MessageNode> { node in node.conversationId == convId && node.profileId == profileId }
        )
        let nodes = (try? bgContext.fetch(descriptor)) ?? []

        // Lightweight node data for pure computation
        struct NodeInfo {
            let id: String
            let role: String
            let hasContent: Bool
            let isDeleted: Bool
            let parentId: String?
            let childrenIds: [String]
        }

        var infoMap: [String: NodeInfo] = [:]
        infoMap.reserveCapacity(nodes.count)
        for node in nodes {
            infoMap[node.id] = NodeInfo(id: node.id, role: node.role, hasContent: !node.content.isEmpty, isDeleted: node.isDeleted, parentId: node.parentId, childrenIds: node.childrenIds)
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
                    infoMap[found.id] = NodeInfo(id: found.id, role: found.role, hasContent: !found.content.isEmpty, isDeleted: found.isDeleted, parentId: found.parentId, childrenIds: found.childrenIds)
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
    private func applyTreeData(_ data: TreeData, conversation: Conversation, context: ModelContext) {
        let convId = conversation.id
        let convProfileId = conversation.profileId

        // Re-fetch on main context (fast — SQLite page cache hit)
        let descriptor = FetchDescriptor<MessageNode>(
            predicate: #Predicate<MessageNode> { node in node.conversationId == convId && node.profileId == convProfileId }
        )
        if let nodes = try? context.fetch(descriptor) {
            nodeMap.reserveCapacity(nodes.count)
            for node in nodes { nodeMap[node.id] = node }
        }

        // Fetch ancestor nodes not in this conversation
        for nodeId in data.allNodeIds where nodeMap[nodeId] == nil {
            let nid = nodeId
            let nidProfileId = convProfileId
            let desc = FetchDescriptor<MessageNode>(
                predicate: #Predicate<MessageNode> { node in node.id == nid && node.profileId == nidProfileId }
            )
            if let node = try? context.fetch(desc).first {
                nodeMap[node.id] = node
            }
        }

        // Apply pre-computed structures
        effectiveChildrenMap = data.effectiveChildrenMap
        cachedRootId = data.rootId
        mainPathIds = data.mainPathIds
        bubbledBranches = data.bubbledBranches
        currentPath = data.pathNodeIds.compactMap { nodeMap[$0] }

        // Build branchInfoMap (needs actual MessageNode objects)
        branchInfoMap.removeAll()
        for node in currentPath {
            if let bid = branchNodeId(for: node.id) {
                branchInfoMap[node.id] = BranchInfo(
                    displayedNodeId: node.id,
                    branchNodeId: bid,
                    branchCount: childrenIds(for: bid).count,
                    branchChildren: branchChildren(for: node.id)
                )
            }
        }

        conversation.nodeCount = data.displayableCount
        isLoading = false

        // Fire pending scroll after tree is loaded — must be next runloop turn
        // so ScrollView exists before onChange sees the value change
        if let pending = pendingScrollNodeId {
            pendingScrollNodeId = nil
            DispatchQueue.main.async { [self] in
                scrollToNodeId = pending
                highlightedNodeId = pending
                // Clear highlight after 3s
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [self] in
                    if highlightedNodeId == pending { highlightedNodeId = nil }
                }
            }
        }
    }

    /// Fetch ancestor nodes missing from nodeMap — query only the missing IDs
    private func chaseMissingAncestors(context: ModelContext) {
        var missingIds = Set<String>()
        for node in nodeMap.values {
            if let pid = node.parentId, !pid.isEmpty, nodeMap[pid] == nil {
                missingIds.insert(pid)
            }
        }

        guard !missingIds.isEmpty else { return }
        let profileId = selectedConversation?.profileId ?? ""

        // Chase ancestors by querying only the specific missing IDs
        var toChase = missingIds
        while !toChase.isEmpty {
            var nextChase = Set<String>()
            for mid in toChase {
                let targetId = mid
                let targetProfileId = profileId
                let desc = FetchDescriptor<MessageNode>(
                    predicate: #Predicate<MessageNode> { node in node.id == targetId && node.profileId == targetProfileId }
                )
                if let found = try? context.fetch(desc).first {
                    nodeMap[found.id] = found
                    if let pid = found.parentId, !pid.isEmpty, nodeMap[pid] == nil {
                        nextChase.insert(pid)
                    }
                }
            }
            toChase = nextChase
        }
    }

    /// Build effective children map from actual parent→child relationships
    private func buildEffectiveChildrenMap() {
        effectiveChildrenMap.removeAll()
        effectiveChildrenMap.reserveCapacity(nodeMap.count)

        // Start with original childrenIds filtered to existing nodes
        for (nodeId, node) in nodeMap {
            effectiveChildrenMap[nodeId] = node.childrenIds.filter { nodeMap[$0] != nil }
        }

        // Add children discovered via parentId (fixes branch conversations)
        for (nodeId, node) in nodeMap {
            if let pid = node.parentId, nodeMap[pid] != nil {
                if !(effectiveChildrenMap[pid]?.contains(nodeId) ?? false) {
                    effectiveChildrenMap[pid, default: []].append(nodeId)
                }
            }
        }
    }

    /// Get children IDs for a node
    private func childrenIds(for nodeId: String) -> [String] {
        effectiveChildrenMap[nodeId] ?? []
    }

    // MARK: - Path Building

    func rebuildPath() {
        currentPath.removeAll()
        bubbledBranches.removeAll()

        guard let rootId = cachedRootId ?? findRootId() else { return }

        var visited = Set<String>()
        var currentId: String? = rootId
        var lastDisplayedNodeId: String? = nil

        while let nid = currentId, let node = nodeMap[nid], !visited.contains(nid) {
            visited.insert(nid)

            let isDisplayable = (node.role == "user" || node.role == "assistant") && !node.content.isEmpty && !node.isDeleted
            let children = childrenIds(for: nid)

            if isDisplayable {
                currentPath.append(node)
                lastDisplayedNodeId = nid
            }

            if children.count > 1 && !isDisplayable {
                if let lastId = lastDisplayedNodeId {
                    bubbledBranches[lastId] = nid
                }
            }

            if children.isEmpty {
                break
            } else if children.count == 1 {
                currentId = children[0]
            } else {
                if let chosenIndex = branchChoices[nid], chosenIndex < children.count {
                    currentId = children[chosenIndex]
                } else {
                    let mainChild = children.first(where: { mainPathIds.contains($0) })
                    currentId = mainChild ?? children[0]
                }
            }
        }

        // Precompute branch info to avoid redundant lookups during rendering
        branchInfoMap.removeAll()
        for node in currentPath {
            if let bid = branchNodeId(for: node.id) {
                branchInfoMap[node.id] = BranchInfo(
                    displayedNodeId: node.id,
                    branchNodeId: bid,
                    branchCount: childrenIds(for: bid).count,
                    branchChildren: branchChildren(for: node.id)
                )
            }
        }
    }

    // MARK: - Branch Navigation

    func switchBranch(at nodeId: String, to childIndex: Int) {
        branchChoices[nodeId] = childIndex
        rebuildPath()
    }

    func branchNodeId(for displayedNodeId: String) -> String? {
        if childrenIds(for: displayedNodeId).count > 1 {
            return displayedNodeId
        }
        return bubbledBranches[displayedNodeId]
    }

    func hasBranches(for displayedNodeId: String) -> Bool {
        return branchNodeId(for: displayedNodeId) != nil
    }

    func branchCount(for displayedNodeId: String) -> Int {
        guard let bid = branchNodeId(for: displayedNodeId) else { return 0 }
        return childrenIds(for: bid).count
    }

    /// "你在哪"位置 hint — 给 BranchMapSheet v2 mini-map 标当前位置用。
    /// 直接读 highlightedNodeId（最近交互过的 node：搜索点击 / pin 跳转 / branch 切换都会设）。
    /// 3s 后会被清空，sheet 打开时如果是 nil 就不画位置 marker（视觉降级，不出 false 信息）。
    /// 详见 docs/plan-branch-map-v2-minimap.md Q1。
    var currentPositionHint: String? { highlightedNodeId }

    /// 给定 child nodeId（某条 branch 的入口），顺向走到 leaf 数 displayable node 数。
    /// 分叉时优先选 mainPathIds 里的 child，跟 buildTreeInBackground 一致。
    /// 用于分支地图显示"分支 N 共 X 条"。B20 part 2 A3 反馈。
    func branchLength(fromChildId childId: String) -> Int {
        var count = 0
        var visited = Set<String>()
        var currentId: String? = childId
        while let nid = currentId, let node = nodeMap[nid], !visited.contains(nid) {
            visited.insert(nid)
            let isDisplayable = (node.role == "user" || node.role == "assistant") && !node.content.isEmpty && !node.isDeleted
            if isDisplayable { count += 1 }
            let children = effectiveChildrenMap[nid] ?? []
            if children.isEmpty {
                break
            } else if children.count == 1 {
                currentId = children[0]
            } else {
                let mainChild = children.first(where: { mainPathIds.contains($0) })
                currentId = mainChild ?? children[0]
            }
        }
        return count
    }

    /// 一条分支的完整描述（含嵌套）。给 BranchMapSheet v2 用。
    /// branchInfoMap 只覆盖当前 currentPath 上的 anchor，看不到嵌套二级分支；
    /// 这个函数 DFS 整棵 effectiveChildrenMap 树，收集所有有 ≥2 displayable
    /// children 的 anchor 的所有非"主选 child"，包括分支之中的子分支。
    /// depth=0 表示 anchor 在主线上；depth>0 表示 anchor 自己也是别人的分支。
    struct AllBranchEntry: Identifiable {
        let id: String                  // anchor + childIndex 唯一
        let anchorNodeId: String        // 实际 branching node id（≥2 children）
        let childIndex: Int             // 该分支是 anchor 的第几个 child
        let childPreviewNode: MessageNode  // 分支起点的第一条 displayable
        let depth: Int                  // 0 = 主线分支；>0 = 分支的分支
        let parentAnchorOnMain: String?  // 一路追溯到主线 anchor 的 nodeId（用于按主线位置排序）
        let parentBranchEntryId: String?  // v5 outline tree：嵌套分支指向直接父 entry id（一级 = nil）
        let length: Int                 // 分支长度（displayable node 数）
        let location: Int               // 在主线 currentPath 第几条；嵌套分支 = parent 的 location
    }

    /// 给 collectAllBranches 用：找 anchor 在主线上能定位的"显示位置"。
    /// anchor 可能是 invisible system/tool 节点（在 mainPathIds 但不在 currentPath），
    /// 此时 currentPath.firstIndex 返回 nil。改沿 parent 链回溯，找最近的
    /// displayable + 在 currentPath 的 ancestor，取它的 index。
    private func nearestDisplayedIndexInPath(of nodeId: String) -> Int? {
        var current: String? = nodeId
        var visited = Set<String>()
        while let nid = current, !visited.contains(nid), let node = nodeMap[nid] {
            visited.insert(nid)
            if let idx = currentPath.firstIndex(where: { $0.id == nid }) {
                return idx
            }
            current = node.parentId
        }
        return nil
    }

    func collectAllBranches() -> [AllBranchEntry] {
        guard let rootId = cachedRootId, nodeMap[rootId] != nil else { return [] }

        var out: [AllBranchEntry] = []
        // DFS：(nodeId, depth, mainAnchorAncestor, mainAnchorLocation, parentBranchEntryId)
        // parentBranchEntryId：进入分支 child 后，该 child 下游所有嵌套 entry 的父
        var stack: [(String, Int, String?, Int, String?)] = [(rootId, 0, nil, -1, nil)]
        var visited = Set<String>()

        while let (nid, depth, mainAnchor, mainLoc, parentEntryId) = stack.popLast() {
            if visited.contains(nid) { continue }
            visited.insert(nid)
            let children = effectiveChildrenMap[nid] ?? []

            if children.count >= 2 {
                // anchor — 选 mainPathIds 里的 child（主选），其余都是分支
                let chosenChild = children.first(where: { mainPathIds.contains($0) }) ?? children[0]
                let anchorOnMain = mainPathIds.contains(nid)
                let anchorLocation: Int = {
                    if anchorOnMain {
                        // invisible branch（system 节点 anchor）不在 currentPath
                        // → 往 parent 链找最近的 displayed ancestor 的位置
                        return nearestDisplayedIndexInPath(of: nid) ?? mainLoc
                    }
                    return mainLoc
                }()
                let nextMainAnchor: String? = anchorOnMain ? nid : mainAnchor

                for (idx, childId) in children.enumerated() {
                    if childId == chosenChild {
                        // 主选 child 继续往下走找深层分支；parentEntryId 不变（仍属于上层 branch lane）
                        stack.append((childId, depth, nextMainAnchor, anchorLocation, parentEntryId))
                        continue
                    }
                    // 分支 child：记录一条分支 entry
                    guard let preview = firstDisplayableDescendant(from: childId) else {
                        // 无 displayable 后代，跳过；下游嵌套不会有合法 preview，但还是要透传 parent
                        stack.append((childId, depth + 1, nextMainAnchor, anchorLocation, parentEntryId))
                        continue
                    }
                    let entryId = "\(nid):\(idx)"
                    out.append(AllBranchEntry(
                        id: entryId,
                        anchorNodeId: nid,
                        childIndex: idx,
                        childPreviewNode: preview,
                        depth: anchorOnMain ? 0 : depth,
                        parentAnchorOnMain: nextMainAnchor,
                        parentBranchEntryId: parentEntryId,
                        length: branchLength(fromChildId: childId),
                        location: anchorLocation
                    ))
                    // 进入这条分支继续找子分支：下游嵌套的父 = 本 entry
                    stack.append((childId, depth + 1, nextMainAnchor, anchorLocation, entryId))
                }
            } else {
                for childId in children {
                    stack.append((childId, depth, mainAnchor, mainLoc, parentEntryId))
                }
            }
        }

        // 按主线位置排序；同位置按 depth 升序（一级在嵌套之前）
        out.sort { lhs, rhs in
            if lhs.location != rhs.location { return lhs.location < rhs.location }
            return lhs.depth < rhs.depth
        }
        return out
    }

    func branchChildren(for nodeId: String) -> [(index: Int, node: MessageNode, isMainPath: Bool)] {
        let actualId = bubbledBranches[nodeId] ?? nodeId
        let children = childrenIds(for: actualId)
        return children.enumerated().compactMap { (idx, childId) in
            let previewNode = firstDisplayableDescendant(from: childId)
            guard let preview = previewNode else { return nil }
            return (index: idx, node: preview, isMainPath: mainPathIds.contains(childId))
        }
    }

    private func firstDisplayableDescendant(from nodeId: String) -> MessageNode? {
        var visited = Set<String>()
        var current: String? = nodeId
        while let nid = current, let node = nodeMap[nid], !visited.contains(nid) {
            visited.insert(nid)
            if (node.role == "user" || node.role == "assistant") && !node.content.isEmpty && !node.isDeleted {
                return node
            }
            current = childrenIds(for: nid).first
        }
        return nil
    }

    // MARK: - In-Conversation Search

    func searchInConversation(keyword: String) {
        inConvSearchKeyword = keyword
        guard !keyword.isEmpty else {
            inConvMatches = []
            inConvMatchIndex = -1
            return
        }
        inConvMatches = currentPath.filter { node in
            (node.role == "user" || node.role == "assistant") &&
            node.content.localizedStandardContains(keyword)
        }.map(\.id)
        inConvMatchIndex = inConvMatches.isEmpty ? -1 : 0
        if let firstId = inConvMatches.first {
            scrollToNodeId = firstId
            highlightedNodeId = firstId
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [self] in
                if highlightedNodeId == firstId { highlightedNodeId = nil }
            }
        }
    }

    func navigateInConvMatch(direction: Int) {
        guard !inConvMatches.isEmpty else { return }
        inConvMatchIndex = (inConvMatchIndex + direction + inConvMatches.count) % inConvMatches.count
        let nodeId = inConvMatches[inConvMatchIndex]
        scrollToNodeId = nodeId
        highlightedNodeId = nodeId
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [self] in
            if highlightedNodeId == nodeId { highlightedNodeId = nil }
        }
    }

    func clearInConvSearch() {
        inConvSearchKeyword = ""
        inConvMatches = []
        inConvMatchIndex = -1
    }

    // MARK: - Actions

    func toggleFavorite(_ node: MessageNode) {
        node.isFavorite.toggle()
    }

    func togglePin(_ node: MessageNode) {
        if node.isPinned {
            node.isPinned = false
            node.pinnedAt = nil
        } else {
            node.isPinned = true
            node.pinnedAt = Date()
        }
    }

    func unpinAll() {
        for node in currentPath where node.isPinned {
            node.isPinned = false
            node.pinnedAt = nil
        }
    }

    /// 当前对话 pin 的节点，按 pinnedAt 降序（新 → 旧），过滤软删除
    var pinnedNodes: [MessageNode] {
        currentPath
            .filter { $0.isPinned && !$0.isDeleted }
            .sorted { ($0.pinnedAt ?? .distantPast) > ($1.pinnedAt ?? .distantPast) }
    }

    func softDelete(_ node: MessageNode) {
        // 1) Instantly remove from display path (single-item diff, no lag)
        let deletedId = node.id
        currentPath.removeAll { $0.id == deletedId }

        // 2) Defer SwiftData mutation so UI updates first, then notify sidebar
        let conv = selectedConversation
        DispatchQueue.main.async { [self] in
            node.isDeleted = true
            node.deletedAt = Date()
            // 软删除是"内容改动"，同步更新对话的 updateTime + nodeCount + 走 3s
            // debounce 重排（之前漏了，导致 sidebar 行里 nodeCount 不减、位置不变）
            if let conv {
                conv.updateTime = Date()
                conv.nodeCount = currentPath.filter {
                    ($0.role == "user" || $0.role == "assistant") && !$0.content.isEmpty
                }.count
                markConversationDirty()
            }
        }
    }

    func restore(_ node: MessageNode) {
        node.isDeleted = false
        node.deletedAt = nil
        if selectedConversation != nil {
            nodeMap[node.id] = node
            buildEffectiveChildrenMap()
            rebuildPath()
        }
    }

    // MARK: - Conversation Delete / Restore

    func softDeleteConversation(_ conversation: Conversation) {
        conversation.isDeleted = true
        conversation.deletedAt = Date()
        if selectedConversation?.id == conversation.id {
            selectedConversation = nil
            currentPath = []
        }
    }

    func restoreConversation(_ conversation: Conversation) {
        conversation.isDeleted = false
        conversation.deletedAt = nil
    }

    func permanentlyDeleteConversation(_ conversation: Conversation, context: ModelContext) {
        let convId = conversation.id
        let convProfileId = conversation.profileId

        // 清理上下文摘要
        ContextSummarizer.clear(conversationId: convId)

        // Delete all MessageNodes belonging to this conversation
        let nodeDescriptor = FetchDescriptor<MessageNode>(
            predicate: #Predicate<MessageNode> { node in
                node.conversationId == convId && node.profileId == convProfileId
            }
        )
        if let nodes = try? context.fetch(nodeDescriptor) {
            for node in nodes { context.delete(node) }
        }

        // Delete all FavoriteItems referencing this conversation
        let favDescriptor = FetchDescriptor<FavoriteItem>(
            predicate: #Predicate<FavoriteItem> { item in
                item.conversationId == convId && item.profileId == convProfileId
            }
        )
        if let items = try? context.fetch(favDescriptor) {
            for item in items { context.delete(item) }
        }

        // Clear selection if needed
        if selectedConversation?.id == convId {
            selectedConversation = nil
            currentPath = []
        }

        context.delete(conversation)
    }

    func permanentlyDeleteNode(_ node: MessageNode, context: ModelContext) {
        let nodeId = node.id
        let nodeProfileId = node.profileId

        // Delete FavoriteItems referencing this node
        let favDescriptor = FetchDescriptor<FavoriteItem>(
            predicate: #Predicate<FavoriteItem> { item in
                item.nodeId == nodeId && item.profileId == nodeProfileId
            }
        )
        if let items = try? context.fetch(favDescriptor) {
            for item in items { context.delete(item) }
        }

        context.delete(node)
    }

    private func findRootId() -> String? {
        // 确定性：按 id 字典序选 parentId==nil（或 parent 不在 nodeMap）的最小者
        // 避免 dict 迭代顺序非确定性导致 export 时选错 root
        let candidates = nodeMap.values.filter { $0.parentId == nil || nodeMap[$0.parentId ?? ""] == nil }
        return candidates.map(\.id).min()
    }

    // MARK: - Export

    /// Export the currently loaded conversation as Markdown
    func exportMarkdown(mode: ExportPathMode, userName: String, assistantName: String) -> String {
        guard let rootId = cachedRootId ?? findRootId() else { return "" }
        return MarkdownExporter.export(
            nodeMap: nodeMap,
            effectiveChildren: effectiveChildrenMap,
            rootId: rootId,
            mainPathIds: mainPathIds,
            currentPath: currentPath,
            mode: mode,
            userName: userName,
            assistantName: assistantName
        )
    }

    // MARK: - Chat (API)

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
    private let memoryExtractWindow = 5

    // MARK: - Budget (保险闸)
    /// 被拦截时 UI 层通过这个显示 alert；UI 消掉后置 nil
    var budgetBlockedMessage: String? = nil
    /// Pre-send 的估算额度，发送完没 usage 时兜底扣费
    private var pendingEstimatedCost: Double = 0

    /// 用 PromptAssembler 组装完整 prompt
    private func assemblePrompt(
        profile: Profile,
        preset: Preset,
        excludingNodeId: String? = nil,
        context: ModelContext,
        globalEntries: [WorldBookEntry] = []
    ) -> (systemPrompt: String?, messages: [(role: String, content: String)], sampling: SamplingParams) {
        // memoryEnabled=false 的对话不注入记忆
        let shouldInjectMemory = selectedConversation?.memoryEnabled ?? true
        let memories: [Memory] = shouldInjectMemory ? memoryStore.listHot(profileId: profile.id, context: context) : []
        let ids = memories.map(\.id)
        if !ids.isEmpty { try? memoryStore.recordAccess(ids: ids, context: context) }

        let chatHistory = buildAPIMessages(excluding: excludingNodeId, maxMessages: preset.sampling.contextDepth)

        // 查询当前楼层的世界书（过滤 conversation scope）
        let profileId = profile.id
        let wbDescriptor = FetchDescriptor<WorldBook>(predicate: #Predicate { $0.profileId == profileId })
        let allFloorBooks = (try? context.fetch(wbDescriptor)) ?? []
        let currentConvId = selectedConversation?.id ?? ""
        let worldBooks = allFloorBooks.filter { book in
            // nil = 楼层全体生效，有值 = 仅匹配的对话生效
            book.scopeConversationId == nil || book.scopeConversationId == currentConvId
        }

        // 读取上下文摘要
        let contextSummary = ContextSummarizer.load(conversationId: currentConvId)?.summary

        let result = PromptAssembler.assemble(
            preset: preset,
            profile: profile,
            memories: memories,
            chatHistory: chatHistory,
            worldBooks: worldBooks,
            globalEntries: globalEntries,
            contextSummary: contextSummary
        )

        return (systemPrompt: result.systemPrompt, messages: result.messages, sampling: preset.sampling)
    }

    /// ccBridge 路径：把 PromptAssembler 的输出后处理成只发 raw user 文字，
    /// 同时构造 router 的 additionalHeaders（chat_id/message_id/user）。
    /// 其他 provider 类型走原路（直接返回 assembled + 空 headers）。
    private func prepareRouterPayload(
        assembled: (systemPrompt: String?, messages: [(role: String, content: String)], sampling: SamplingParams),
        model: ProviderModel,
        conversation: Conversation,
        profile: Profile,
        providerManager: ProviderManager,
        messageNodeId: String
    ) -> (
        messages: [(role: String, content: String)],
        systemPrompt: String?,
        sampling: SamplingParams,
        additionalHeaders: [String: String]
    ) {
        guard let provider = providerManager.provider(for: model),
              provider.type == .ccBridge else {
            return (assembled.messages, assembled.systemPrompt, assembled.sampling, [:])
        }
        // ccBridge：只取最后一条 user 的 raw 文字，丢掉 system prompt 和历史
        let lastUser = assembled.messages.last(where: { $0.role == "user" })?.content ?? ""
        let userLabel = profile.userName.isEmpty ? "tianyi" : profile.userName
        let headers: [String: String] = [
            "X-MP-ChatId": conversation.id,
            "X-MP-MessageId": messageNodeId,
            "X-MP-User": userLabel,
        ]
        return (
            messages: [(role: "user", content: lastUser)],
            systemPrompt: nil,
            sampling: assembled.sampling,
            additionalHeaders: headers
        )
    }

    /// 主 provider id → 该 provider 下"便宜模型"的 modelId。粟粟批注：暂硬编码，
    /// 未来可扩展成配置。provider 不在表里就没 cheap 可用 → fallback 到主对话模型。
    private static let cheapModelIdByProvider: [String: String] = [
        "anthropic": "claude-haiku-4-5",
        "openai":    "gpt-4o-mini",
        "deepseek":  "deepseek-chat",
        "gemini":    "gemini-2.5-flash",
        "groq":      "llama-3.3-70b-versatile",
    ]

    /// 选择记忆提取 / 上下文总结等 backend agent 用的便宜模型。
    /// **只在 enabledProviders（有 key）里找**，避免落到没 key 没拨款的 provider。
    /// 顺序：用户旧设置 `memoryExtractModelId`（限 enabled）→ 主 provider 的 cheap map → fallback。
    private func cheapModel(providerManager: ProviderManager, fallback: ProviderModel) -> ProviderModel {
        let enabledModels = providerManager.enabledProviders.flatMap(\.models)

        // 老 UserDefaults key 兼容（Picker 现已被 MemoryModelConfig 替代，但之前选过的仍尊重）
        let userChoice = UserDefaults.standard.string(forKey: "memoryExtractModelId") ?? ""
        if !userChoice.isEmpty, let model = enabledModels.first(where: { $0.id == userChoice }) {
            return model
        }

        if let cheapId = Self.cheapModelIdByProvider[fallback.providerId],
           let provider = providerManager.enabledProviders.first(where: { $0.id == fallback.providerId }),
           let model = provider.models.first(where: { $0.modelId == cheapId }) {
            return model
        }

        return fallback
    }


    /// Build API message history from currentPath, excluding a specific node, limited to recent messages
    private func buildAPIMessages(excluding excludeId: String? = nil, maxMessages: Int = 40) -> [(role: String, content: String)] {
        let relevant = currentPath.compactMap { node -> (role: String, content: String)? in
            guard node.role == "user" || node.role == "assistant" else { return nil }
            if node.id == excludeId { return nil }
            guard !node.content.isEmpty else { return nil }
            // Strip thinking blocks from assistant messages before sending
            let content: String
            if node.role == "assistant" {
                let result = ContentCleaner.extractThinking(from: node.content)
                content = result.content
            } else {
                content = node.content
            }
            guard !content.isEmpty else { return nil }
            return (role: node.role, content: content)
        }
        // Only keep the most recent messages
        if relevant.count > maxMessages {
            return Array(relevant.suffix(maxMessages))
        }
        return relevant
    }

    /// Send a user message and get a streaming response
    func sendMessage(_ text: String, imageData: Data? = nil, model: ProviderModel, profile: Profile, preset: Preset, providerManager: ProviderManager, context: ModelContext) {
        guard let conversation = selectedConversation else { return }
        guard preCheckBudget(text: text, model: model, profile: profile, preset: preset, providerManager: providerManager) else { return }

        // 1. Determine parent node (last node in path, or nil for first message)
        let parentId = currentPath.last?.id

        // 2. Build content and contentType
        let (userContent, userContentType): (String, String) = {
            guard let data = imageData else { return (text, "text") }
            let b64 = data.base64EncodedString()
            let blocks: [[String: Any]] = [
                ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": b64]],
                ["type": "text", "text": text]
            ]
            let json = (try? JSONSerialization.data(withJSONObject: blocks)).flatMap { String(data: $0, encoding: .utf8) } ?? text
            return (json, "multimodal_text")
        }()

        // 3. Create user MessageNode
        let userNodeId = UUID().uuidString
        let userNode = MessageNode(
            id: userNodeId,
            role: "user",
            content: userContent,
            contentType: userContentType,
            createTime: Date(),
            parentId: parentId,
            childrenIds: [],
            conversationId: conversation.id,
            profileId: conversation.profileId
        )
        context.insert(userNode)

        // Update parent's childrenIds
        if let parentId, let parent = nodeMap[parentId] {
            if !parent.childrenIds.contains(userNodeId) {
                parent.childrenIds.append(userNodeId)
            }
        }

        // Add to nodeMap and path
        nodeMap[userNodeId] = userNode
        effectiveChildrenMap[userNodeId] = []
        if let parentId {
            effectiveChildrenMap[parentId, default: []].append(userNodeId)
        }
        currentPath.append(userNode)

        // 3. Create placeholder assistant node
        let assistantNodeId = UUID().uuidString
        let assistantNode = MessageNode(
            id: assistantNodeId,
            role: "assistant",
            content: "",
            contentType: "text",
            createTime: Date(),
            parentId: userNodeId,
            childrenIds: [],
            conversationId: conversation.id,
            profileId: conversation.profileId
        )
        context.insert(assistantNode)

        userNode.childrenIds.append(assistantNodeId)
        nodeMap[assistantNodeId] = assistantNode
        effectiveChildrenMap[assistantNodeId] = []
        effectiveChildrenMap[userNodeId, default: []].append(assistantNodeId)
        currentPath.append(assistantNode)

        // Update conversation
        conversation.currentNodeId = assistantNodeId
        conversation.updateTime = Date()
        markConversationDirty()

        streamingText = ""
        streamingThinkingText = ""
        isThinking = false
        thinkingSummary = ""

        // 4. Assemble prompt using PromptAssembler
        let assembled = assemblePrompt(profile: profile, preset: preset, excludingNodeId: assistantNodeId, context: context, globalEntries: globalWorldBookEntries)
        let payload = prepareRouterPayload(assembled: assembled, model: model, conversation: conversation, profile: profile, providerManager: providerManager, messageNodeId: assistantNodeId)

        // 5. Stream
        // 6a: 发送触觉反馈
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        providerRouter.sendStreaming(
            model: model,
            messages: payload.messages,
            systemPrompt: payload.systemPrompt,
            providerManager: providerManager,
            samplingParams: payload.sampling,
            additionalHeaders: payload.additionalHeaders,
            onSegments: { [weak assistantNode] segments in
                // 仅在存在 tool_use/tool_result 段时调用。
                // 比 onComplete 先执行，context.save() 在 onComplete 中处理。
                assistantNode?.setSegments(segments)
            },
            onThinkingToken: { [weak self] token in
                guard let self else { return }
                streamingThinkingText += token
                if !isThinking { isThinking = true }
            },
            onToken: { [weak self] token in
                guard let self else { return }
                if isThinking {
                    // 思考结束、正文开始——6c: warning 震（转折感），并异步生成一句话总结
                    isThinking = false
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    let capturedThinking = streamingThinkingText
                    let capturedModel = model
                    let capturedProvider = providerManager
                    Task { [weak self] in
                        guard let self else { return }
                        let summary = await self.providerRouter.summarizeThinking(
                            thinkingText: capturedThinking,
                            model: capturedModel,
                            providerManager: capturedProvider
                        )
                        if let s = summary { self.thinkingSummary = s }
                    }
                }
                streamingText += token
                assistantNode.content = streamingText
            },
            onComplete: { [weak self] fullText, usage in
                guard let self else { return }
                assistantNode.content = fullText
                streamingText = ""
                streamingThinkingText = ""
                isThinking = false
                conversation.nodeCount = currentPath.filter {
                    ($0.role == "user" || $0.role == "assistant") && !$0.content.isEmpty
                }.count
                // Auto-title from first user message
                if conversation.title == "新对话" {
                    let firstUserMsg = currentPath.first(where: { $0.role == "user" && !$0.content.isEmpty })?.content ?? ""
                    if !firstUserMsg.isEmpty {
                        let title = String(firstUserMsg.prefix(40)).replacingOccurrences(of: "\n", with: " ")
                        conversation.title = title
                        // 走 debounce，和发消息触发的重排合并在一次 refresh 里（避免首次发消息
                        // 标题立刻变 + 位置立刻跳的双抖动）
                        markConversationDirty()
                    }
                }
                try? context.save()
                scrollToNodeId = assistantNodeId

                // 预算扣费（Phase C 完整接入前先只用 usage）
                self.commitBudgetSpend(providerManager: providerManager, model: model, usage: usage)

                // AUDN 记忆提取（memoryEnabled=false 的对话不提取）
                if conversation.memoryEnabled {
                    self.extractMemoriesIfNeeded(profileId: profile.id, conversationId: conversation.id, model: model, providerManager: providerManager, context: context)
                }

                // 上下文总结（异步，不阻塞）
                self.triggerContextSummaryIfNeeded(
                    conversationId: conversation.id,
                    contextDepth: preset.sampling.contextDepth,
                    model: model, providerManager: providerManager
                )
            },
            onError: { [weak self] error in
                guard let self else { return }
                if streamingText.isEmpty {
                    assistantNode.content = "⚠️ \(error)"
                }
                streamingText = ""
                streamingThinkingText = ""
                isThinking = false
            }
        )

        scrollToNodeId = userNodeId
    }

    /// AUDN 记忆提取：每轮对话后异步调用便宜模型提取/更新/删除记忆
    private func extractMemoriesIfNeeded(profileId: String, conversationId: String, model: ProviderModel, providerManager: ProviderManager, context: ModelContext) {
        guard !profileId.isEmpty else { return }

        let recentMessages = Array(buildAPIMessages().suffix(memoryExtractWindow))
        guard !recentMessages.isEmpty else { return }

        let existingMemories = memoryStore.listHotAndWarm(profileId: profileId, context: context)
        let extractModel = cheapModel(providerManager: providerManager, fallback: model)
        #if DEBUG
        print("🧠 记忆提取: 使用模型 \(extractModel.name) (\(extractModel.id)), 最近 \(recentMessages.count) 条消息, 已有 \(existingMemories.count) 条记忆")
        #endif

        let request = MemoryExtractor.buildRequest(
            recentMessages: recentMessages,
            existingMemories: existingMemories
        )

        // 预算保险闸：共用主对话 provider 一个预算（粟粟批注：分词器也是粗算，保险即可）
        if backendAgentBlockedByBudget(model: model, messages: request.messages, systemPrompt: request.systemPrompt, providerManager: providerManager) {
            #if DEBUG
            print("🧠 记忆提取: 跳过（主 provider \(model.providerId) 预算已用完 / 未拨款）")
            #endif
            return
        }

        // Fire-and-forget: 异步调用，不阻塞对话
        let router = ProviderRouter()
        Task.detached { [weak self] in
            do {
                let (response, usage) = try await router.sendNonStreaming(
                    model: extractModel,
                    messages: request.messages,
                    systemPrompt: request.systemPrompt,
                    providerManager: providerManager
                )
                #if DEBUG
                print("🧠 记忆提取: 模型返回 \(response.prefix(200))...")
                #endif

                // Spent 累加到全局预算池（GlobalBudgetStore 不分 providerId，共用一个预算）。
                // 但 actualCost 必须用 extractModel（实际跑的廉价模型）查 PricingCatalog，
                // 否则 Haiku token 数 × Opus 单价会超收 ~18×（ultrareview B17 / bug_004）。
                if let usage {
                    await MainActor.run {
                        self?.commitBudgetSpend(providerManager: providerManager, model: extractModel, usage: usage)
                    }
                }

                let actions = MemoryExtractor.parseActions(response)
                #if DEBUG
                if actions.isEmpty {
                    print("🧠 记忆提取: 解析结果为空（模型返回了无法解析的格式或 NOOP）")
                } else {
                    print("🧠 记忆提取: 解析到 \(actions.count) 个操作")
                }
                #endif
                guard !actions.isEmpty else { return }

                await MainActor.run {
                    for action in actions {
                        #if DEBUG
                        switch action {
                        case .add(let content, let category, _):
                            print("🧠 记忆: ✅ ADD [\(category)] \(content.prefix(60))...")
                        case .update(let id, let content, _):
                            print("🧠 记忆: ✏️ UPDATE \(id.uuidString.prefix(8)) → \(content.prefix(60))...")
                        case .delete(let id):
                            print("🧠 记忆: 🗑️ DELETE \(id.uuidString.prefix(8))")
                        }
                        #endif
                    }
                    try? MemoryExtractor.executeActions(
                        actions,
                        store: self?.memoryStore ?? SwiftDataMemoryStore(),
                        profileId: profileId,
                        extractedBy: extractModel.name,
                        sourceConversationId: conversationId,
                        context: context
                    )
                }
            } catch {
                #if DEBUG
                print("🧠 记忆提取: ⚠️ 失败 — \(error)")
                #endif
            }
        }
    }

    /// 上下文总结触发（fire-and-forget）
    private func triggerContextSummaryIfNeeded(conversationId: String, contextDepth: Int, model: ProviderModel, providerManager: ProviderManager) {
        let allMessages = buildAPIMessages(maxMessages: Int.max)
        let sumModel = cheapModel(providerManager: providerManager, fallback: model)
        Task.detached {
            try? await ContextSummarizer.summarize(
                allMessages: allMessages,
                contextDepth: contextDepth,
                conversationId: conversationId,
                model: sumModel,
                providerManager: providerManager
            )
        }
    }

    /// 会话巩固：切换对话时刷新衰减权重
    func consolidateSessionMemories(profileId: String, context: ModelContext) {
        guard !profileId.isEmpty else { return }
        try? memoryStore.applyDecay(profileId: profileId, context: context)
    }

    /// Regenerate: create a new assistant response as a sibling branch of the existing one
    func regenerate(assistantNodeId: String, model: ProviderModel, profile: Profile, preset: Preset, providerManager: ProviderManager, context: ModelContext) {
        guard preCheckBudget(text: "", model: model, profile: profile, preset: preset, providerManager: providerManager) else { return }
        guard let conversation = selectedConversation,
              let oldNode = nodeMap[assistantNodeId],
              oldNode.role == "assistant",
              let userParentId = oldNode.parentId,
              let userParent = nodeMap[userParentId]
        else { return }

        // Create new assistant node as sibling
        let newAssistantId = UUID().uuidString
        let newNode = MessageNode(
            id: newAssistantId,
            role: "assistant",
            content: "",
            contentType: "text",
            createTime: Date(),
            parentId: userParentId,
            childrenIds: [],
            conversationId: conversation.id,
            profileId: conversation.profileId
        )
        context.insert(newNode)

        userParent.childrenIds.append(newAssistantId)
        nodeMap[newAssistantId] = newNode
        effectiveChildrenMap[newAssistantId] = []
        effectiveChildrenMap[userParentId, default: []].append(newAssistantId)

        // Replace old node in path with new one
        if let idx = currentPath.firstIndex(where: { $0.id == assistantNodeId }) {
            // Remove everything after the old assistant node
            currentPath.removeSubrange(idx...)
            currentPath.append(newNode)
        }

        conversation.currentNodeId = newAssistantId
        conversation.updateTime = Date()
        markConversationDirty()
        streamingText = ""
        streamingThinkingText = ""
        isThinking = false
        thinkingSummary = ""

        // Assemble prompt
        let assembled = assemblePrompt(profile: profile, preset: preset, excludingNodeId: newAssistantId, context: context, globalEntries: globalWorldBookEntries)
        let payload = prepareRouterPayload(assembled: assembled, model: model, conversation: conversation, profile: profile, providerManager: providerManager, messageNodeId: newAssistantId)

        // 6a: 发送触觉反馈
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        providerRouter.sendStreaming(
            model: model,
            messages: payload.messages,
            systemPrompt: payload.systemPrompt,
            providerManager: providerManager,
            samplingParams: payload.sampling,
            additionalHeaders: payload.additionalHeaders,
            onSegments: { [weak newNode] segments in
                newNode?.setSegments(segments)
            },
            onThinkingToken: { [weak self] token in
                guard let self else { return }
                streamingThinkingText += token
                if !isThinking { isThinking = true }
            },
            onToken: { [weak self] token in
                guard let self else { return }
                if isThinking {
                    isThinking = false
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    let capturedThinking = streamingThinkingText
                    let capturedModel = model
                    let capturedProvider = providerManager
                    Task { [weak self] in
                        guard let self else { return }
                        let summary = await self.providerRouter.summarizeThinking(
                            thinkingText: capturedThinking,
                            model: capturedModel,
                            providerManager: capturedProvider
                        )
                        if let s = summary { self.thinkingSummary = s }
                    }
                }
                streamingText += token
                newNode.content = streamingText
            },
            onComplete: { [weak self] fullText, usage in
                guard let self else { return }
                newNode.content = fullText
                streamingText = ""
                streamingThinkingText = ""
                isThinking = false
                try? context.save()
                scrollToNodeId = newAssistantId
                self.commitBudgetSpend(providerManager: providerManager, model: model, usage: usage)

                // 上下文总结
                self.triggerContextSummaryIfNeeded(
                    conversationId: conversation.id,
                    contextDepth: preset.sampling.contextDepth,
                    model: model, providerManager: providerManager
                )
            },
            onError: { [weak self] error in
                guard let self else { return }
                if streamingText.isEmpty {
                    newNode.content = "⚠️ \(error)"
                }
                streamingText = ""
                streamingThinkingText = ""
                isThinking = false
            }
        )

        scrollToNodeId = newAssistantId
    }

    /// Edit a user message: create a new branch from the original message's parent with new text, then get a response
    func editAndResend(_ originalNodeId: String, newText: String, model: ProviderModel, profile: Profile, preset: Preset, providerManager: ProviderManager, context: ModelContext) {
        guard preCheckBudget(text: newText, model: model, profile: profile, preset: preset, providerManager: providerManager) else { return }
        guard let conversation = selectedConversation,
              let originalNode = nodeMap[originalNodeId],
              originalNode.role == "user",
              let grandparentId = originalNode.parentId
        else { return }

        // Trim path up to (but not including) the original user node
        if let idx = currentPath.firstIndex(where: { $0.id == originalNodeId }) {
            currentPath.removeSubrange(idx...)
        }

        // Create new user node as sibling branch
        let newUserId = UUID().uuidString
        let newUserNode = MessageNode(
            id: newUserId,
            role: "user",
            content: newText,
            contentType: "text",
            createTime: Date(),
            parentId: grandparentId,
            childrenIds: [],
            conversationId: conversation.id,
            profileId: conversation.profileId
        )
        context.insert(newUserNode)

        if let grandparent = nodeMap[grandparentId] {
            if !grandparent.childrenIds.contains(newUserId) {
                grandparent.childrenIds.append(newUserId)
            }
            effectiveChildrenMap[grandparentId, default: []].append(newUserId)
        }
        nodeMap[newUserId] = newUserNode
        effectiveChildrenMap[newUserId] = []
        currentPath.append(newUserNode)

        // Create placeholder assistant node
        let newAssistantId = UUID().uuidString
        let newAssistantNode = MessageNode(
            id: newAssistantId,
            role: "assistant",
            content: "",
            contentType: "text",
            createTime: Date(),
            parentId: newUserId,
            childrenIds: [],
            conversationId: conversation.id,
            profileId: conversation.profileId
        )
        context.insert(newAssistantNode)

        newUserNode.childrenIds.append(newAssistantId)
        nodeMap[newAssistantId] = newAssistantNode
        effectiveChildrenMap[newAssistantId] = []
        effectiveChildrenMap[newUserId, default: []].append(newAssistantId)
        currentPath.append(newAssistantNode)

        conversation.currentNodeId = newAssistantId
        conversation.updateTime = Date()
        markConversationDirty()
        streamingText = ""
        streamingThinkingText = ""
        isThinking = false
        thinkingSummary = ""

        let assembled = assemblePrompt(profile: profile, preset: preset, excludingNodeId: newAssistantId, context: context, globalEntries: globalWorldBookEntries)
        let payload = prepareRouterPayload(assembled: assembled, model: model, conversation: conversation, profile: profile, providerManager: providerManager, messageNodeId: newAssistantId)

        // 6a: 发送触觉反馈
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        providerRouter.sendStreaming(
            model: model,
            messages: payload.messages,
            systemPrompt: payload.systemPrompt,
            providerManager: providerManager,
            samplingParams: payload.sampling,
            additionalHeaders: payload.additionalHeaders,
            onSegments: { [weak newAssistantNode] segments in
                newAssistantNode?.setSegments(segments)
            },
            onThinkingToken: { [weak self] token in
                guard let self else { return }
                streamingThinkingText += token
                if !isThinking { isThinking = true }
            },
            onToken: { [weak self] token in
                guard let self else { return }
                if isThinking {
                    isThinking = false
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    let capturedThinking = streamingThinkingText
                    let capturedModel = model
                    let capturedProvider = providerManager
                    Task { [weak self] in
                        guard let self else { return }
                        let summary = await self.providerRouter.summarizeThinking(
                            thinkingText: capturedThinking,
                            model: capturedModel,
                            providerManager: capturedProvider
                        )
                        if let s = summary { self.thinkingSummary = s }
                    }
                }
                streamingText += token
                newAssistantNode.content = streamingText
            },
            onComplete: { [weak self] fullText, usage in
                guard let self else { return }
                newAssistantNode.content = fullText
                streamingText = ""
                streamingThinkingText = ""
                isThinking = false
                try? context.save()
                scrollToNodeId = newAssistantId
                self.commitBudgetSpend(providerManager: providerManager, model: model, usage: usage)

                // 上下文总结
                self.triggerContextSummaryIfNeeded(
                    conversationId: conversation.id,
                    contextDepth: preset.sampling.contextDepth,
                    model: model, providerManager: providerManager
                )
            },
            onError: { [weak self] error in
                guard let self else { return }
                if streamingText.isEmpty {
                    newAssistantNode.content = "⚠️ \(error)"
                }
                streamingText = ""
                streamingThinkingText = ""
                isThinking = false
            }
        )

        scrollToNodeId = newUserId
    }

    /// Create a new empty conversation for chatting
    func createNewConversation(title: String, profileId: String, context: ModelContext) -> Conversation {
        let rootId = UUID().uuidString
        let conversation = Conversation(
            id: UUID().uuidString,
            title: title,
            createTime: Date(),
            updateTime: Date(),
            currentNodeId: rootId,
            provider: "api",
            profileId: profileId
        )
        context.insert(conversation)

        // Create invisible root node
        let rootNode = MessageNode(
            id: rootId,
            role: "system",
            content: "",
            contentType: "text",
            createTime: Date(),
            parentId: nil,
            childrenIds: [],
            conversationId: conversation.id,
            profileId: profileId
        )
        context.insert(rootNode)
        try? context.save()

        return conversation
    }

    // MARK: - Budget

    /// 发送后扣费：优先用响应里的真实 usage；没 usage 就用最近一次 pre-check 估的值保守扣。
    func commitBudgetSpend(providerManager: ProviderManager, model: ProviderModel, usage: TokenUsage?) {
        guard let provider = providerManager.provider(for: model) else { return }
        let cost: Double
        if let usage {
            cost = BudgetCalculator.actualCost(provider: provider, modelId: model.modelId, usage: usage)
        } else if pendingEstimatedCost > 0 {
            // 没 usage（流中断 / 某些 API 不回 usage）→ 按 pre-send 估算扣
            cost = pendingEstimatedCost
        } else {
            return
        }
        providerManager.commitSpend(providerId: provider.id, amount: cost)
        pendingEstimatedCost = 0
    }

    /// pre-send 门控：超额返回 false（调用方 return）。失败会写 budgetBlockedMessage 让 UI 显示 alert。
    /// 成功（ok / warning）会把 estimate 存到 pendingEstimatedCost，发送完回填扣费兜底。
    func preCheckBudget(
        text: String,
        model: ProviderModel,
        profile: Profile,
        preset: Preset,
        providerManager: ProviderManager
    ) -> Bool {
        guard let provider = providerManager.provider(for: model) else { return true }
        let maxOut = preset.sampling.maxTokens
        // 粗估 input：system + 当前 path（已有上下文）+ 新消息
        var accumulated = ""
        if !profile.systemPrompt.isEmpty { accumulated += profile.systemPrompt + "\n" }
        for node in currentPath where !node.content.isEmpty {
            accumulated += node.content + "\n"
        }
        accumulated += text
        let inputTok = HeuristicEstimator().estimate(accumulated)
        let estimated = BudgetCalculator.actualCost(
            provider: provider,
            modelId: model.modelId,
            usage: TokenUsage(inputTokens: inputTok, outputTokens: maxOut)
        )
        pendingEstimatedCost = estimated
        let gate = providerManager.budgetGate(providerId: provider.id, estimatedCost: estimated)
        switch gate {
        case .ok, .disabled, .warning:
            return true
        case .blocked(let spent, let budget):
            budgetBlockedMessage = Self.blockedMessage(providerName: provider.name, spent: spent, budget: budget)
            pendingEstimatedCost = 0
            return false
        }
    }

    /// Backend agent（memory extract / context summary 等）统一预算 gate。
    /// 返回 true = 被预算拦了，应该跳过这次 API 调用。
    func backendAgentBlockedByBudget(
        model: ProviderModel,
        messages: [(role: String, content: String)],
        systemPrompt: String?,
        providerManager: ProviderManager,
        assumedMaxOutput: Int = 1024
    ) -> Bool {
        guard let provider = providerManager.provider(for: model) else { return true }
        var accumulated = systemPrompt ?? ""
        for m in messages {
            accumulated += "\n" + m.content
        }
        let inputTok = HeuristicEstimator().estimate(accumulated)
        let estimated = BudgetCalculator.actualCost(
            provider: provider,
            modelId: model.modelId,
            usage: TokenUsage(inputTokens: inputTok, outputTokens: assumedMaxOutput)
        )
        let gate = providerManager.budgetGate(providerId: provider.id, estimatedCost: estimated)
        if case .blocked = gate { return true }
        return false
    }

    /// 友好文案：区分"没拨款（首次使用）"和"已用完"。
    private static func blockedMessage(providerName: String, spent: Double, budget: Double) -> String {
        if budget <= 0 {
            return """
            「\(providerName)」还没设预算。

            防止 app bug 把你的 key 烧干，所以默认开了保险闸。

            去「API 设置 → 预算（保险闸）」给它拨款（比如 $5），或关掉「启用预算限额」开关。
            """
        }
        return String(
            format: "「%@」预算已用完：$%.2f / $%.2f。\n\n去「API 设置 → 预算（保险闸）」点「重置已用」，或加预算上限。",
            providerName, spent, budget
        )
    }
}
