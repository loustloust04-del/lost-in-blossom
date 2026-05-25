import Foundation

/// API 响应里回传的 token 计数。流式要合并多个 event 取最终值。
struct TokenUsage: Equatable {
    let inputTokens: Int
    let outputTokens: Int
}

/// 预算保险闸的门控结果。
enum BudgetGate: Equatable {
    case ok
    /// 当前花费占比已过警戒线（0.8-0.99）
    case warning(percent: Double, spent: Double, budget: Double)
    /// 已用完或本次估算会超额
    case blocked(spent: Double, budget: Double)
    /// 开关未启用，放行
    case disabled
}

enum BudgetCalculator {
    /// 发送前粗估。output 按 max_tokens 上限估，偏保守。
    static func estimateCost(
        provider: APIProvider,
        modelId: String,
        messages: [(role: String, content: String)],
        systemPrompt: String?,
        maxOutputTokens: Int,
        estimator: BudgetTokenEstimator
    ) -> Double {
        var input = ""
        if let sp = systemPrompt, !sp.isEmpty { input += sp + "\n" }
        input += messages.map(\.content).joined(separator: "\n")
        let inputTokens = estimator.estimate(input)
        return applyRatios(
            provider: provider,
            modelId: modelId,
            inputTokens: Double(inputTokens),
            outputTokens: Double(max(0, maxOutputTokens))
        )
    }

    /// 发送后按真实 usage 精算。
    static func actualCost(
        provider: APIProvider,
        modelId: String,
        usage: TokenUsage
    ) -> Double {
        applyRatios(
            provider: provider,
            modelId: modelId,
            inputTokens: Double(usage.inputTokens),
            outputTokens: Double(usage.outputTokens)
        )
    }

    /// 检查全局保险闸是否放行 estimatedCost。粟粟决策（2026-04-23）：
    /// 水库总闸门，无论哪个 provider 哪个 model 的调用都汇总到 GlobalBudgetStore。
    static func gate(estimatedCost: Double) -> BudgetGate {
        let store = GlobalBudgetStore.shared
        guard store.enabled else { return .disabled }
        let budget = store.budgetUSD
        let spent = store.spentUSD
        // 预算 <= 0 视为"未拨款"，一律拦截
        if budget <= 0 {
            return .blocked(spent: spent, budget: budget)
        }
        if spent + estimatedCost >= budget {
            return .blocked(spent: spent, budget: budget)
        }
        let percent = (spent + estimatedCost) / budget
        if percent >= 0.8 {
            return .warning(percent: percent, spent: spent, budget: budget)
        }
        return .ok
    }

    // MARK: - Private

    private static func applyRatios(
        provider: APIProvider,
        modelId: String,
        inputTokens: Double,
        outputTokens: Double
    ) -> Double {
        let pricing = PricingCatalog.price(for: modelId)
        let inputUSD = inputTokens / 1_000_000 * pricing.inputUSDPerMTok
        // 补全倍率作用在 output 侧（one-api 约定）
        let outputUSD = outputTokens / 1_000_000 * pricing.outputUSDPerMTok * provider.completionRatio
        return (inputUSD + outputUSD)
            * provider.modelRatio
            * provider.groupRatio
            * provider.currencyRate
    }
}
