import Foundation
import SwiftData

// MARK: - Memory Store Protocol

protocol MemoryStore {
    // CRUD
    @discardableResult
    func add(content: String, category: String, keywords: [String],
             profileId: String, isUserExplicit: Bool, extractedBy: String,
             sourceConversationId: String?, context: ModelContext) throws -> Memory
    func update(id: UUID, content: String, keywords: [String], context: ModelContext) throws
    func delete(id: UUID, context: ModelContext) throws

    // 查询
    func listHot(profileId: String, context: ModelContext) -> [Memory]
    func listHotAndWarm(profileId: String, context: ModelContext) -> [Memory]
    func listAll(profileId: String, context: ModelContext) -> [Memory]

    // 生命周期
    func recordAccess(ids: [UUID], context: ModelContext) throws
    func applyDecay(profileId: String, context: ModelContext) throws
}

// MARK: - SwiftData Memory Store

struct SwiftDataMemoryStore: MemoryStore {

    @discardableResult
    func add(content: String, category: String, keywords: [String],
             profileId: String, isUserExplicit: Bool, extractedBy: String,
             sourceConversationId: String?, context: ModelContext) throws -> Memory {
        let memory = Memory(
            content: content,
            category: category,
            keywords: keywords,
            profileId: profileId,
            isUserExplicit: isUserExplicit,
            extractedBy: extractedBy,
            sourceConversationId: sourceConversationId
        )
        context.insert(memory)
        try context.save()
        return memory
    }

    func update(id: UUID, content: String, keywords: [String], context: ModelContext) throws {
        let descriptor = FetchDescriptor<Memory>(
            predicate: #Predicate<Memory> { m in m.id == id }
        )
        guard let memory = try context.fetch(descriptor).first else { return }
        memory.content = content
        memory.keywords = keywords
        memory.tokenCount = Memory.estimateTokens(content)
        memory.updatedAt = Date()
        try context.save()
    }

    func delete(id: UUID, context: ModelContext) throws {
        let descriptor = FetchDescriptor<Memory>(
            predicate: #Predicate<Memory> { m in m.id == id }
        )
        if let memory = try context.fetch(descriptor).first {
            context.delete(memory)
            try context.save()
        }
    }

    func listHot(profileId: String, context: ModelContext) -> [Memory] {
        let hotThreshold = 0.3
        let descriptor = FetchDescriptor<Memory>(
            predicate: #Predicate<Memory> { m in
                m.profileId == profileId && (m.isUserExplicit == true || m.decayWeight >= hotThreshold)
            },
            sortBy: [SortDescriptor(\Memory.decayWeight, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func listHotAndWarm(profileId: String, context: ModelContext) -> [Memory] {
        let warmThreshold = 0.05
        let descriptor = FetchDescriptor<Memory>(
            predicate: #Predicate<Memory> { m in
                m.profileId == profileId && (m.isUserExplicit == true || m.decayWeight >= warmThreshold)
            },
            sortBy: [SortDescriptor(\Memory.decayWeight, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func listAll(profileId: String, context: ModelContext) -> [Memory] {
        let descriptor = FetchDescriptor<Memory>(
            predicate: #Predicate<Memory> { m in m.profileId == profileId },
            sortBy: [SortDescriptor(\Memory.updatedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func recordAccess(ids: [UUID], context: ModelContext) throws {
        for id in ids {
            let descriptor = FetchDescriptor<Memory>(
                predicate: #Predicate<Memory> { m in m.id == id }
            )
            if let memory = try context.fetch(descriptor).first {
                DecayEngine.reinforce(memory)
            }
        }
        try context.save()
    }

    func applyDecay(profileId: String, context: ModelContext) throws {
        let all = listAll(profileId: profileId, context: context)
        DecayEngine.applyDecay(memories: all)
        try context.save()
    }
}

// MARK: - Decay Engine

enum MemoryTier: String, Hashable {
    case hot    // 自动注入
    case warm   // 可搜索，不自动注入
    case cold   // 归档
}

struct DecayEngine {
    /// 计算记忆当前有效权重（惰性计算，不写入）
    static func effectiveWeight(_ memory: Memory) -> Double {
        guard !memory.isUserExplicit else { return 1.0 }
        let days = Date().timeIntervalSince(memory.lastAccessedAt) / 86400
        return memory.decayWeight * exp(-0.1 * days)
    }

    /// 访问时强化
    static func reinforce(_ memory: Memory) {
        memory.decayWeight = min(1.0, memory.decayWeight + 0.2)
        memory.lastAccessedAt = Date()
        memory.accessCount += 1
    }

    /// 批量衰减：将 effectiveWeight 写回 decayWeight
    static func applyDecay(memories: [Memory]) {
        for memory in memories {
            guard !memory.isUserExplicit else { continue }
            memory.decayWeight = effectiveWeight(memory)
            memory.lastAccessedAt = Date()
            // 检查 validUntil
            if let until = memory.validUntil, Date() > until {
                memory.decayWeight = min(memory.decayWeight, 0.05)
            }
        }
    }

    /// 温区分类
    static func tier(_ memory: Memory) -> MemoryTier {
        let w = effectiveWeight(memory)
        if memory.isUserExplicit || w >= 0.3 { return .hot }
        if w >= 0.05 { return .warm }
        return .cold
    }
}

// MARK: - Memory Injector

struct MemoryInjector {
    static let tokenBudget = 2000

    /// 分类标签中文映射
    private static let categoryLabels: [String: String] = [
        "preference": "偏好",
        "fact": "事实",
        "relationship": "关系",
        "goal": "目标",
        "context": "情境",
    ]

    /// 从 hot 记忆中选择注入内容，按权重排序，不超过 token 预算
    static func buildInjection(memories: [Memory], budget: Int = tokenBudget) -> String {
        guard !memories.isEmpty else { return "" }

        // 分离：用户手动的始终注入，自动的按权重排序
        let explicit = memories.filter { $0.isUserExplicit }
        let auto = memories.filter { !$0.isUserExplicit }
            .sorted { score($0) > score($1) }

        var lines: [String] = []
        var usedTokens = 0

        // 用户手动的始终注入
        for m in explicit {
            let label = categoryLabels[m.category] ?? m.category
            lines.append("- \(m.content) [\(label)]")
            usedTokens += m.tokenCount
        }

        // 自动的按预算注入
        for m in auto {
            if usedTokens + m.tokenCount > budget { break }
            let label = categoryLabels[m.category] ?? m.category
            lines.append("- \(m.content) [\(label)]")
            usedTokens += m.tokenCount
        }

        return lines.joined(separator: "\n")
    }

    /// 拼接到 system prompt
    static func inject(systemPrompt: String?, memories: [Memory]) -> String? {
        let injection = buildInjection(memories: memories)
        let base = systemPrompt ?? ""

        guard !injection.isEmpty else {
            return base.isEmpty ? nil : base
        }

        let block = "[关于用户]\n\(injection)"

        if base.isEmpty {
            return block
        }
        return "\(base)\n\n\(block)"
    }

    /// 打分：decayWeight × log(1 + accessCount)
    private static func score(_ memory: Memory) -> Double {
        DecayEngine.effectiveWeight(memory) * log(1.0 + Double(memory.accessCount))
    }
}

// MARK: - Memory Extractor (AUDN)

enum MemoryAction {
    case add(content: String, category: String, keywords: [String])
    case update(id: UUID, content: String, keywords: [String])
    case delete(id: UUID)
}

struct MemoryExtractor {
    static let extractionPrompt = """
你是记忆管理助手。分析最近的对话，决定是否需要更新用户的记忆库。

## 当前记忆
{{MEMORIES}}

## 规则
1. 提取原子事实 — 每条记忆是一个独立的陈述（"喜欢暖色调"而不是"有各种审美偏好"）
2. 分类：preference（偏好）、fact（事实）、relationship（人际关系）、goal（目标/项目）、context（当前情境，有时效性）
3. 对每条新信息做出一个判断：
   - add: 全新信息，现有记忆未覆盖
   - update: 已有记忆需要修正或补充 — 提供要更新的记忆 ID
   - delete: 已有记忆被明确否定或过时 — 提供要删除的记忆 ID
   - 不操作: 已充分覆盖，或不值得存储
4. 只存用户明确说出或强烈暗示的信息。不要推断敏感信息。
5. 用简洁的第三人称：「用户喜欢...」而不是「你喜欢...」
6. 需要时加时间限定词：「用户目前在做...」
7. 新旧矛盾时，delete 旧记忆 + add 新版本。
8. 不存：日常闲聊、一次性问题、用户在问（而非陈述）的信息。

## 输出格式
只输出 JSON，不要解释：
{"actions": [{"type": "add", "content": "记忆内容", "category": "分类", "keywords": ["关键词"]}, {"type": "update", "id": "记忆ID", "content": "新内容", "keywords": ["关键词"]}, {"type": "delete", "id": "记忆ID"}]}
如果没有需要操作的，输出：{"actions": []}
"""

    /// 构建提取请求（优先用用户自定义提示词）
    static func buildPrompt(existingMemories: [Memory]) -> String {
        var memoriesJSON = "无"
        if !existingMemories.isEmpty {
            let items = existingMemories.map { m in
                "  {\"id\": \"\(m.id.uuidString)\", \"content\": \"\(m.content)\", \"category\": \"\(m.category)\"}"
            }
            memoriesJSON = "[\n\(items.joined(separator: ",\n"))\n]"
        }

        let customPrompt = UserDefaults.standard.string(forKey: "customMemoryExtractionPrompt") ?? ""
        let template = customPrompt.isEmpty ? extractionPrompt : customPrompt
        return template.replacingOccurrences(of: "{{MEMORIES}}", with: memoriesJSON)
    }

    /// 构建发给 LLM 的 system prompt 和 messages
    static func buildRequest(
        recentMessages: [(role: String, content: String)],
        existingMemories: [Memory]
    ) -> (systemPrompt: String, messages: [(role: String, content: String)]) {
        let prompt = buildPrompt(existingMemories: existingMemories)

        // 把最近对话格式化为用户消息
        var conversationText = ""
        for msg in recentMessages {
            let label = msg.role == "user" ? "用户" : "AI"
            conversationText += "\(label): \(msg.content)\n\n"
        }

        let messages = [(role: "user", content: "以下是最近的对话，请分析并执行记忆操作：\n\n\(conversationText)")]
        return (systemPrompt: prompt, messages: messages)
    }

    /// 解析 LLM 返回的 JSON 为操作列表
    static func parseActions(_ jsonString: String) -> [MemoryAction] {
        // 尝试直接解析
        if let actions = parseJSON(jsonString) { return actions }

        // Fallback: 从文本中提取 JSON 块
        if let range = jsonString.range(of: "\\{[\\s\\S]*\\}", options: .regularExpression),
           let actions = parseJSON(String(jsonString[range])) {
            return actions
        }

        return []
    }

    private static func parseJSON(_ json: String) -> [MemoryAction]? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let actions = obj["actions"] as? [[String: Any]] else {
            return nil
        }

        var result: [MemoryAction] = []

        for action in actions {
            guard let type = action["type"] as? String else { continue }

            switch type {
            case "add":
                guard let content = action["content"] as? String,
                      let category = action["category"] as? String else { continue }
                let keywords = action["keywords"] as? [String] ?? []
                result.append(.add(content: content, category: category, keywords: keywords))

            case "update":
                guard let idStr = action["id"] as? String,
                      let id = UUID(uuidString: idStr),
                      let content = action["content"] as? String else { continue }
                let keywords = action["keywords"] as? [String] ?? []
                result.append(.update(id: id, content: content, keywords: keywords))

            case "delete":
                guard let idStr = action["id"] as? String,
                      let id = UUID(uuidString: idStr) else { continue }
                result.append(.delete(id: id))

            default:
                break
            }
        }

        return result.isEmpty ? nil : result
    }

    /// 执行操作列表
    static func executeActions(
        _ actions: [MemoryAction],
        store: MemoryStore,
        profileId: String,
        extractedBy: String,
        sourceConversationId: String?,
        context: ModelContext
    ) throws {
        for action in actions {
            switch action {
            case .add(let content, let category, let keywords):
                try store.add(
                    content: content,
                    category: category,
                    keywords: keywords,
                    profileId: profileId,
                    isUserExplicit: false,
                    extractedBy: extractedBy,
                    sourceConversationId: sourceConversationId,
                    context: context
                )

            case .update(let id, let content, let keywords):
                try store.update(id: id, content: content, keywords: keywords, context: context)

            case .delete(let id):
                try store.delete(id: id, context: context)
            }
        }
    }
}
