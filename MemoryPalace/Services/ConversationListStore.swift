import Foundation
import SwiftData

/// 侧栏（会话列表/收藏/回收站/标签）的 SwiftData 数据访问层。
/// 解耦方向四：SidebarView 不再直接 fetch/insert/delete/save modelContext。
/// 注意：insertTag / insertFavorite 沿用原行为——只 insert 不显式 save，
/// 交给主 context 的 autosave（改成显式 save 会改变撤销/回滚语义，别动）。
enum ConversationListStore {

    /// 楼层内按 id 查单个对话（侧栏跳转用，原来散落 6 处的同款 fetch）
    static func conversation(id: String, profileId: String, context: ModelContext) -> Conversation? {
        let cid = id
        let pid = profileId
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate<Conversation> { conv in conv.id == cid && conv.profileId == pid }
        )
        return try? context.fetch(descriptor).first
    }

    /// 跨楼层按 id 查单个对话（推送跳转/PROBE 用——通知里只有 convId 没有楼层）
    static func conversation(id: String, context: ModelContext) -> Conversation? {
        let cid = id
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate<Conversation> { $0.id == cid }
        )
        return try? context.fetch(descriptor).first
    }

    /// 楼层内是否存在未删除的对话（首启自动建对话的判断）
    static func hasActiveConversations(profileId: String, context: ModelContext) -> Bool {
        let pid = profileId
        var desc = FetchDescriptor<Conversation>(
            predicate: #Predicate<Conversation> { $0.profileId == pid && $0.isDeleted == false }
        )
        desc.fetchLimit = 1
        return ((try? context.fetchCount(desc)) ?? 0) > 0
    }

    /// 楼层内全部对话的 [id: title] 映射（一次查询，避免 N 次单查）
    static func titleMap(profileId: String, context: ModelContext) -> [String: String] {
        let pid = profileId
        let desc = FetchDescriptor<Conversation>(
            predicate: #Predicate<Conversation> { $0.profileId == pid }
        )
        guard let allConvs = try? context.fetch(desc) else { return [:] }
        var map: [String: String] = [:]
        map.reserveCapacity(allConvs.count)
        for conv in allConvs { map[conv.id] = conv.title }
        return map
    }

    /// 收藏的消息节点（带所属对话标题），按创建时间倒序
    static func favoritedNodes(profileId: String, context: ModelContext) -> [(node: MessageNode, convTitle: String)] {
        let pid = profileId
        let descriptor = FetchDescriptor<MessageNode>(
            predicate: #Predicate<MessageNode> { node in
                node.profileId == pid && node.isFavorite == true && node.isDeleted == false
            },
            sortBy: [SortDescriptor(\MessageNode.createTime, order: .reverse)]
        )
        guard let nodes = try? context.fetch(descriptor) else { return [] }
        let titles = titleMap(profileId: profileId, context: context)
        return nodes.map { node in
            (node: node, convTitle: titles[node.conversationId] ?? "未知对话")
        }
    }

    /// 回收站里的消息节点（带所属对话标题），按删除时间倒序
    static func deletedNodes(profileId: String, context: ModelContext) -> [(node: MessageNode, convTitle: String)] {
        let pid = profileId
        let descriptor = FetchDescriptor<MessageNode>(
            predicate: #Predicate<MessageNode> { node in
                node.profileId == pid && node.isDeleted == true
            },
            sortBy: [SortDescriptor(\MessageNode.deletedAt, order: .reverse)]
        )
        guard let nodes = try? context.fetch(descriptor) else { return [] }
        let titles = titleMap(profileId: profileId, context: context)
        return nodes.map { node in
            (node: node, convTitle: titles[node.conversationId] ?? "未知对话")
        }
    }

    /// 「收藏」tab 的搜索范围：所有未删除且已收藏的对话 id
    static func favoriteConversationIds(profileId: String, context: ModelContext) -> Set<String> {
        let pid = profileId
        let desc = FetchDescriptor<Conversation>(
            predicate: #Predicate<Conversation> { $0.profileId == pid && $0.isDeleted == false && $0.isFavorite == true }
        )
        let convs = (try? context.fetch(desc)) ?? []
        return Set(convs.map(\.id))
    }

    /// 自定义 tag 的搜索范围：该 tag 下 FavoriteItem 对应的对话 id
    static func taggedConversationIds(tagId: String, profileId: String, context: ModelContext) -> Set<String> {
        let tid = tagId
        let pid = profileId
        let desc = FetchDescriptor<FavoriteItem>(
            predicate: #Predicate<FavoriteItem> { $0.profileId == pid && $0.tagId == tid }
        )
        let items = (try? context.fetch(desc)) ?? []
        return Set(items.map(\.conversationId))
    }

    /// 删除 tag：连带清掉该 tag 在当前楼层的所有 FavoriteItem，然后落盘
    static func deleteTag(_ tag: ConversationTag, profileId: String, context: ModelContext) {
        let tid = tag.id
        let pid = profileId
        let descriptor = FetchDescriptor<FavoriteItem>(
            predicate: #Predicate<FavoriteItem> { item in item.tagId == tid && item.profileId == pid }
        )
        if let items = try? context.fetch(descriptor) {
            for item in items { context.delete(item) }
        }
        context.delete(tag)
        try? context.save()
    }

    /// 新建 tag（只 insert，autosave 落盘）
    static func insertTag(_ tag: ConversationTag, context: ModelContext) {
        context.insert(tag)
    }

    /// 把对话挂到 tag（只 insert，autosave 落盘）
    static func insertFavorite(_ item: FavoriteItem, context: ModelContext) {
        context.insert(item)
    }

    /// 取消挂 tag（只 delete，autosave 落盘，与 insertFavorite 对称）
    static func deleteFavorite(_ item: FavoriteItem, context: ModelContext) {
        context.delete(item)
    }

    /// 托管对象就地修改（tag 排序等）后的统一落盘出口
    static func persist(context: ModelContext) {
        try? context.save()
    }

    /// CC Bridge session → 占用它的对话标题映射（CCSessionPickerSheet 用）。
    /// excludingConversationId / excludingSession：当前对话和默认 session 不算占用。
    /// TODO: 谓词可下推（ccBridgeSessionName != nil && isDeleted == false），对话多时这里是全表扫
    static func ccSessionOwners(
        excludingConversationId: String,
        excludingSession: String,
        context: ModelContext
    ) -> [String: String] {
        var descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate<Conversation> { $0.isDeleted == false }
        )
        guard let all = try? context.fetch(descriptor) else { return [:] }
        var map: [String: String] = [:]
        for c in all {
            guard !c.isDeleted, c.id != excludingConversationId,
                  let name = c.ccBridgeSessionName,
                  !name.isEmpty, name != excludingSession else { continue }
            map[name] = c.title
        }
        return map
    }

    // MARK: - Paginated conversation list (fetchPage)

    struct ConversationPage {
        var conversations: [Conversation]
        var totalCount: Int
    }

    /// 会话列表分页查询，覆盖 trash / tag / chats / source-filtered 四条路径。
    /// sourceFilter: nil = chats（分页）；"claude"/"chatgpt" = 全量 source 过滤（Almond/Amber）
    static func fetchPage(
        offset: Int,
        pageSize: Int,
        profileId: String,
        showTrash: Bool,
        selectedTagId: String?,
        sourceFilter: String?,
        searchText: String,
        sortDescriptors: [SortDescriptor<Conversation>],
        favoritesOnly: Bool,
        dateInterval: (start: Date, end: Date)?,
        context: ModelContext
    ) -> ConversationPage {

        // ── Trash path ────────────────────────────────────────────────────
        if showTrash {
            var descriptor = FetchDescriptor<Conversation>(sortBy: sortDescriptors)
            descriptor.predicate = trashPredicate(profileId: profileId, search: searchText, interval: dateInterval)
            let total = (try? context.fetchCount(descriptor)) ?? 0
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = pageSize
            let results = (try? context.fetch(descriptor)) ?? []
            return ConversationPage(conversations: results, totalCount: total)
        }

        // ── Tag path ──────────────────────────────────────────────────────
        if let tagId = selectedTagId {
            let tid = tagId
            let pid = profileId
            let favDescriptor = FetchDescriptor<FavoriteItem>(
                predicate: #Predicate<FavoriteItem> { item in item.profileId == pid && item.tagId == tid }
            )
            if let items = try? context.fetch(favDescriptor) {
                let convIds = Set(items.map(\.conversationId))
                var convDescriptor = FetchDescriptor<Conversation>(sortBy: sortDescriptors)
                convDescriptor.predicate = normalPredicate(profileId: profileId, search: searchText, interval: dateInterval, favoritesOnly: false)
                if let allConvs = try? context.fetch(convDescriptor) {
                    let filtered = allConvs.filter { convIds.contains($0.id) }
                    return ConversationPage(conversations: Array(filtered.prefix(pageSize)), totalCount: filtered.count)
                }
            }
            return ConversationPage(conversations: [], totalCount: 0)
        }

        var descriptor = FetchDescriptor<Conversation>(sortBy: sortDescriptors)
        descriptor.predicate = normalPredicate(profileId: profileId, search: searchText, interval: dateInterval, favoritesOnly: favoritesOnly)

        // ── Source-filtered path (Almond/Amber): full load ────────────────
        if let src = sourceFilter {
            if let results = try? context.fetch(descriptor) {
                let filtered = results.filter { $0.source == src }
                let sorted = filtered.sorted { ($0.updateTime ?? .distantPast) > ($1.updateTime ?? .distantPast) }
                return ConversationPage(conversations: Array(sorted), totalCount: filtered.count)
            }
            return ConversationPage(conversations: [], totalCount: 0)
        }

        // ── Chats path: paginated ─────────────────────────────────────────
        let total = (try? context.fetchCount(descriptor)) ?? 0
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = pageSize
        let results = (try? context.fetch(descriptor)) ?? []
        return ConversationPage(conversations: results, totalCount: total)
    }

    // MARK: - Predicate builders (private)

    private static func normalPredicate(
        profileId: String,
        search: String,
        interval: (start: Date, end: Date)?,
        favoritesOnly: Bool
    ) -> Predicate<Conversation> {
        let hasKeyword = !search.isEmpty
        let kw = search
        let pid = profileId
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

    private static func trashPredicate(
        profileId: String,
        search: String,
        interval: (start: Date, end: Date)?
    ) -> Predicate<Conversation> {
        let hasKeyword = !search.isEmpty
        let kw = search
        let pid = profileId
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
}
