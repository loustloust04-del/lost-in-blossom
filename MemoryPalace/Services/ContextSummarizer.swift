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

    // MARK: - 判断是否需要总结

    /// 返回需要总结的旧消息。如果不需要总结返回 nil。
    static func messagesToSummarize(
        allMessages: [(role: String, content: String)],
        contextDepth: Int,
        conversationId: String
    ) -> (oldMessages: [(role: String, content: String)], existingSummary: ContextSummary?)? {
        let totalCount = allMessages.count
        guard totalCount > contextDepth else { return nil }

        let oldCount = totalCount - contextDepth
        let oldMessages = Array(allMessages.prefix(oldCount))

        let existing = load(conversationId: conversationId)

        // 已有摘要且覆盖的消息数没变 → 不需要更新
        if let existing, existing.coveredCount == oldCount {
            return nil
        }

        return (oldMessages: oldMessages, existingSummary: existing)
    }

    // MARK: - 构建总结请求

    static func buildSummaryRequest(
        oldMessages: [(role: String, content: String)],
        existingSummary: ContextSummary?
    ) -> (systemPrompt: String, messages: [(role: String, content: String)]) {

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
