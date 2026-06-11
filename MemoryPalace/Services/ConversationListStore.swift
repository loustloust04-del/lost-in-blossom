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

    /// 托管对象就地修改（tag 排序等）后的统一落盘出口
    static func persist(context: ModelContext) {
        try? context.save()
    }
}
