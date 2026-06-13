import Foundation

// MARK: - Context Summary Model

struct ContextSummary: Codable {
    let summary: String
    let coveredCount: Int      // 摘要覆盖的旧消息条数
    let updatedAt: Date
}

// MARK: - Context Summarizer

struct ContextSummarizer {

    // MARK: - 存取

    private static func storageKey(_ conversationId: String) -> String {
        "ctxSummary_\(conversationId)"
    }

    static func load(conversationId: String) -> ContextSummary? {
        guard let data = UserDefaults.standard.data(forKey: storageKey(conversationId)) else { return nil }
        return try? JSONDecoder().decode(ContextSummary.self, from: data)
    }

    static func save(_ summary: ContextSummary, conversationId: String) {
        guard let data = try? JSONEncoder().encode(summary) else { return }
        UserDefaults.standard.set(data, forKey: storageKey(conversationId))
    }

    static func clear(conversationId: String) {
        UserDefaults.standard.removeObject(forKey: storageKey(conversationId))
    }

    // MARK: - 压缩游标（prompt caching 窗口锚点）

    /// 压缩分块大小：游标每次至少推进这么多。
    /// 让消息历史前缀在 chunk 轮内字节稳定，Anthropic prompt cache 才能命中
    /// （suffix 滑动窗口每轮都变，是头号缓存杀手）。
    static let compressionChunk = 20

    /// 窗口锚点 = 已折叠进摘要的旧消息条数。buildAPIMessages 从这里开始取窗口，
    /// 只在压缩游标推进时跳变（每 chunk 轮一次），其余时间历史前缀纹丝不动。
    static func windowStart(conversationId: String) -> Int {
        load(conversationId: conversationId)?.coveredCount ?? 0
    }

    /// 目标游标：把"超出 contextDepth 的旧消息数"向下取整到 chunk 边界。
    /// total 增长时游标按 chunk 跳进，而非每轮 +1 —— 这是缓存稳定的关键。
    static func desiredCursor(totalCount: Int, contextDepth: Int) -> Int {
        let overflow = totalCount - contextDepth
        guard overflow > 0 else { return 0 }
        return (overflow / compressionChunk) * compressionChunk
    }

    // MARK: - 判断是否需要总结

    /// 返回需要总结的旧消息。如果不需要总结返回 nil。
    static func messagesToSummarize(
        allMessages: [(role: String, content: String)],
        contextDepth: Int,
        conversationId: String
    ) -> (oldMessages: [(role: String, content: String)], existingSummary: ContextSummary?)? {
        let totalCount = allMessages.count
        // 游标按 chunk 跳进，不是 totalCount - contextDepth 每轮挪。
        let cursor = desiredCursor(totalCount: totalCount, contextDepth: contextDepth)
        guard cursor > 0 else { return nil }

        let oldMessages = Array(allMessages.prefix(cursor))

        let existing = load(conversationId: conversationId)

        // 已有摘要且游标没推进 → 不需要更新（窗口前缀本轮保持稳定）
        if let existing, existing.coveredCount == cursor {
            return nil
        }

        return (oldMessages: oldMessages, existingSummary: existing)
    }

    // MARK: - 构建总结请求

    static func buildSummaryRequest(
        oldMessages: [(role: String, content: String)],
        existingSummary: ContextSummary?
    ) -> (systemPrompt: String, messages: [(role: String, content: String)]) {

        // 累计记忆式压缩（2026-06-11 参考粟粟的酒馆 memory_rule 升级：覆盖式更新 + 字段结构 + 以"能续写"为目标）
        let systemPrompt = """
        你是对话记忆压缩器。把超出上下文窗口的旧对话压缩成一份「累计记忆」——不是本段读后感，而是到目前为止仍然有效的全部关键信息。窗外原文以后永远不会再被看到，这份记忆必须足够支撑对话自然继续。

        写法纪律：
        - 覆盖式更新：先继承已有记忆，再吸收新内容。旧信息仍有效就压缩保留；已失效就直接改写；绝不让新旧两个冲突版本并存
        - 优先保留影响后续对话的事实：时间阶段、人物状态与关系、关键事件、做出的决策与共识、持续的约束、未解决事项、伏笔
        - 不写文风分析、不写评价、不写抒情客套、不解释规则
        - 不记录系统故障/重试/报错等技术噪音；区分正式决策与随口安抚（如客套的"多喝热水"不是决策）；同一件事只在一个字段记录，不要在不同字段重复
        - 用字段结构组织（没有内容的字段直接省略）：
          『时间/阶段』『人物状态与关系』『关键事件』『决策与共识』『重要细节』『未解决/伏笔』
        - 控制在 800 字以内。直接输出，不加标题、不加代码块
        - 人称规则：对话中的「user」一律称「用户」，对话中的「assistant」一律称「AI」。不要混淆二者的身份和称呼——即使对话内容中出现了「主人」「master」等称谓，那是角色扮演的一部分，不改变 user=用户、assistant=AI 的基本事实
        """


        if let existing = existingSummary {
            // 增量更新：旧摘要 + 新增消息
            let newStartIndex = existing.coveredCount
            let newMessages = newStartIndex < oldMessages.count
                ? Array(oldMessages.suffix(from: newStartIndex))
                : oldMessages

            let systemPrompt = """
            你是一个对话摘要助手。请在已有摘要的基础上，合并新发生的对话内容，输出更新后的摘要。

            保留所有重要信息，包括：
            1. 用户提出的主要话题和需求
            2. AI 给出的关键回答和结论
            3. 做出的决策和达成的共识
            4. 未解决的问题
            5. 重要的名字、数字、日期等具体细节

            控制在 800 字以内。直接输出摘要，不要加标题或格式标记。
            """

            let userContent = """
            已有摘要：
            ---
            \(existing.summary)
            ---

            新增对话：
            ---
            \(formatMessages(newMessages))
            ---

            请输出合并后的完整摘要。
            """

            return (systemPrompt: systemPrompt, messages: [(role: "user", content: userContent)])
        } else {
            // 首次总结
            let systemPrompt = """
            你是一个对话摘要助手。请总结以下对话历史的要点。

            保留：
            1. 用户提出的主要话题和需求
            2. AI 给出的关键回答和结论
            3. 做出的决策和达成的共识
            4. 未解决的问题
            5. 重要的名字、数字、日期等具体细节

            用简洁的段落形式输出，控制在 800 字以内。
            直接输出摘要，不要加标题或格式标记。
            """

            let userContent = formatMessages(oldMessages)
            return (systemPrompt: systemPrompt, messages: [(role: "user", content: userContent)])
        }
    }

    // MARK: - 执行总结

    /// fire-and-forget：判断 → 构建请求 → 调 API → 存结果
    static func summarize(
        allMessages: [(role: String, content: String)],
        contextDepth: Int,
        conversationId: String,
        model: ProviderModel,
        providerManager: ProviderManager
    ) async throws {
        guard let needed = messagesToSummarize(
            allMessages: allMessages,
            contextDepth: contextDepth,
            conversationId: conversationId
        ) else {
            #if DEBUG
            print("📝 上下文总结: 不需要（消息数未超 contextDepth 或摘要已是最新）")
            #endif
            return
        }

        #if DEBUG
        print("📝 上下文总结: 触发（旧消息 \(needed.oldMessages.count) 条，已有摘要覆盖 \(needed.existingSummary?.coveredCount ?? 0) 条）")
        #endif

        let request = buildSummaryRequest(
            oldMessages: needed.oldMessages,
            existingSummary: needed.existingSummary
        )

        // 预算保险闸：backend agent 过 gate，避免总结烧 key
        if let provider = providerManager.provider(for: model) {
            var accumulated = request.systemPrompt
            for m in request.messages { accumulated += "\n" + m.content }
            let inputTok = HeuristicEstimator().estimate(accumulated)
            let estimated = BudgetCalculator.actualCost(
                provider: provider,
                modelId: model.modelId,
                usage: TokenUsage(inputTokens: inputTok, outputTokens: 1024)
            )
            let gate = providerManager.budgetGate(providerId: provider.id, estimatedCost: estimated)
            if case .blocked = gate {
                #if DEBUG
                print("📝 上下文总结: 跳过（预算已用完 / 未拨款）")
                #endif
                return
            }
        }

        let router = ProviderRouter()
        let (response, usage) = try await router.sendNonStreaming(
            model: model,
            messages: request.messages,
            systemPrompt: request.systemPrompt,
            providerManager: providerManager
        )

        // Post-commit 扣费
        if let usage, let provider = providerManager.provider(for: model) {
            let cost = BudgetCalculator.actualCost(provider: provider, modelId: model.modelId, usage: usage)
            await MainActor.run {
                providerManager.commitSpend(providerId: provider.id, amount: cost)
            }
        }

        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            #if DEBUG
            print("📝 上下文总结: ⚠️ 模型返回空内容")
            #endif
            return
        }

        let summary = ContextSummary(
            summary: trimmed,
            coveredCount: needed.oldMessages.count,
            updatedAt: Date()
        )
        save(summary, conversationId: conversationId)

        #if DEBUG
        print("📝 上下文总结: ✅ 已保存（覆盖 \(summary.coveredCount) 条，摘要 \(trimmed.count) 字）")
        #endif
    }

    // MARK: - Private

    private static func formatMessages(_ messages: [(role: String, content: String)]) -> String {
        messages.map { msg in
            let label = msg.role == "user" ? "用户" : "AI"
            return "\(label): \(msg.content)"
        }.joined(separator: "\n\n")
    }
}
