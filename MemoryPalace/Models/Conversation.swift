import Foundation
import SwiftData

@Model
final class Conversation {
    #Index<Conversation>(
        [\.profileId],
        [\.profileId, \.lastOpenedAt],
        [\.profileId, \.isDeleted, \.lastOpenedAt]
    )

    @Attribute(.unique) var id: String
    /// 楼层隔离。路线 B 单 ModelContainer 下所有 fetch 必须带 profileId predicate。
    /// 新建时必填；迁移老数据时补填。默认 "" 只为 SwiftData lightweight migration。
    var profileId: String = ""
    var title: String
    var createTime: Date
    var updateTime: Date
    var currentNodeId: String
    var isFavorite: Bool = false
    var folderId: String?

    var nodeCount: Int = 0
    var lastOpenedAt: Date?

    var isDeleted: Bool = false
    var deletedAt: Date?

    /// "chatgpt", "claude", "api", "sillytavern"
    var provider: String = "chatgpt"

    /// Links to ImportRecord.id for batch undo
    var importBatchId: UUID?

    /// 记忆参与开关（默认 true）
    /// false = 此对话不贡献记忆到楼层池，也不接收记忆注入
    var memoryEnabled: Bool = true

    init(id: String, title: String, createTime: Date, updateTime: Date, currentNodeId: String, provider: String = "chatgpt", profileId: String = "") {
        self.id = id
        self.title = title
        self.createTime = createTime
        self.updateTime = updateTime
        self.currentNodeId = currentNodeId
        self.provider = provider
        self.profileId = profileId
    }
}

@Model
final class MessageNode {
    #Index<MessageNode>(
        [\.profileId],
        [\.profileId, \.conversationId],
        [\.profileId, \.conversationId, \.isDeleted]
    )

    @Attribute(.unique) var id: String
    /// 楼层隔离。Migration 会给老数据补填。注：MessageNode 用 parentId: String? 做树
    /// 关系，不是 @Relationship —— migration 时 1-pass copy 即可，无需 2-pass。
    var profileId: String = ""
    var role: String            // user, assistant, system, tool
    var content: String
    var contentType: String     // text, code, multimodal_text, segmented 等
    var createTime: Date?
    var parentId: String?
    var childrenIds: [String] = []
    var conversationId: String

    var isFavorite: Bool = false
    var isPinned: Bool = false
    var pinnedAt: Date? = nil
    var isDeleted: Bool = false
    var deletedAt: Date?

    /// 结构化分段（Claude importer v2 写入）。JSON 编码的 [MessageSegment]。
    /// 为 nil 时消息按旧路径渲染（基于 content 字符串 + extractThinking）。
    @Attribute(.externalStorage) var segmentsData: Data?

    // Computed: has branches (more than 1 child)
    var hasBranches: Bool {
        childrenIds.count > 1
    }

    var branchCount: Int {
        childrenIds.count
    }

    /// 解码 segmentsData。nil 表示这是旧数据 / 非 Claude v2 导入的节点。
    var segments: [MessageSegment]? {
        guard let data = segmentsData else { return nil }
        return try? JSONDecoder().decode([MessageSegment].self, from: data)
    }

    /// Claude importer v2 用：一次写入分段数组。
    func setSegments(_ segs: [MessageSegment]) {
        self.segmentsData = try? JSONEncoder().encode(segs)
    }

    init(id: String, role: String, content: String, contentType: String,
         createTime: Date?, parentId: String?, childrenIds: [String], conversationId: String,
         profileId: String = "") {
        self.id = id
        self.role = role
        self.content = content
        self.contentType = contentType
        self.createTime = createTime
        self.parentId = parentId
        self.childrenIds = childrenIds
        self.conversationId = conversationId
        self.profileId = profileId
    }
}

@Model
final class UserCard {
    #Index<UserCard>(
        [\.profileId],
        [\.profileId, \.attachedToNodeId]
    )

    var id: UUID = UUID()
    /// 楼层隔离。新建角色卡必填。
    var profileId: String = ""
    var content: String = ""
    var imageData: Data?
    var attachedToNodeId: String?
    var positionX: Double = 0
    var positionY: Double = 0
    var createTime: Date = Date()

    init(content: String = "", attachedToNodeId: String? = nil, profileId: String = "") {
        self.content = content
        self.attachedToNodeId = attachedToNodeId
        self.profileId = profileId
    }
}
