import Foundation

// MARK: - Push Agent Service（Phase 3.2 框架）
//
// 定位：基于 AI 驱动的主动消息生成与排期。
// 当前状态：骨架占位，所有 TODO 标注的逻辑在 Phase 3.2 实现。
//
// 架构思路：
//   App 启动 → PushAgentService.start()
//     → 注册 BGProcessingTask（com.bunny.lostinblossom.push-agent）
//   BGTask 触发 → handleBackgroundTask()
//     → scheduleNext(for: profile)
//       → generateProactiveMessage()    ← AI 生成
//       → LocalNotificationService.scheduleProactiveMessage()
//   用户点击通知 → notificationNavigationRequested → 打开对话
//
// Phase 3.2 里还需要：
//   - Info-iOS.plist 添加 BGTaskSchedulerPermittedIdentifiers
//   - 在 App 里注册 BGTaskScheduler handler（必须在 applicationDidFinishLaunching 之前）

@Observable
final class PushAgentService {
    static let shared = PushAgentService()
    private init() {}

    // MARK: - 状态

    private(set) var isRunning: Bool = false

    // MARK: - 启动 / 停止

    /// App 启动后调用（在 LocalNotificationService 初始化之后）。
    /// TODO: Phase 3.2 — 注册 BGProcessingTask，设置调度策略。
    func start(profileManager: ProfileManager, providerManager: ProviderManager) {
        guard !isRunning else { return }
        isRunning = true
        // TODO: Phase 3.2 —— 在 App(@main) 的 init() 里，用 BGTaskScheduler.shared.register
        //   forTaskWithIdentifier: "com.bunny.lostinblossom.push-agent"
        //   using: nil
        //   launchHandler: { task in Task { await self.handleBackgroundTask(...) } }
        //
        // scheduleBackgroundTask()
    }

    func stop() {
        isRunning = false
        // TODO: Phase 3.2 — 取消已注册的 BGTask
    }

    // MARK: - 消息生成

    /// 为指定楼层生成一条主动消息文本。
    ///
    /// TODO: Phase 3.2 实现步骤：
    ///   1. 调用 imprint-memory MCP SSE 拉取最近记忆（memory_search / memory_list）
    ///   2. 拼 prompt：
    ///      "你是 Caelum，天奕的 AI 伴侣。结合以下记忆，写一句主动发起聊天的消息，不超过 20 字，
    ///       自然口语，第一人称，不带感叹号。记忆：{memories}"
    ///   3. 调 ProviderRouter.sendNonStreaming（用当前楼层 preferredModel）
    ///   4. 解析返回，去掉首尾引号/换行
    func generateProactiveMessage(
        for profile: Profile,
        providerManager: ProviderManager
    ) async -> String? {
        // TODO: Phase 3.2
        return nil
    }

    // MARK: - 排期下一条

    /// 生成并排期下一条主动消息通知。
    ///
    /// TODO: Phase 3.2 实现步骤：
    ///   1. 计算最佳发送时刻（查 UserDefaults 里的历史活跃时段，避开睡眠时间）
    ///   2. 调 generateProactiveMessage
    ///   3. 调 LocalNotificationService.shared.scheduleProactiveMessage
    func scheduleNext(
        for profile: Profile,
        providerManager: ProviderManager,
        conversationId: String? = nil
    ) async {
        let text = await generateProactiveMessage(for: profile, providerManager: providerManager)
        guard let text, !text.isEmpty else { return }

        // TODO: Phase 3.2 — 智能计算 delay（活跃时段 + 间隔策略），现在是 stub
        let delay: TimeInterval = 6 * 60 * 60 // 6 小时占位
        LocalNotificationService.shared.scheduleProactiveMessage(
            text,
            in: delay,
            conversationId: conversationId
        )
    }

    // MARK: - Background Task Handler

    /// BGProcessingTask handler，在 App 注册的 launchHandler 里调用。
    ///
    /// TODO: Phase 3.2 实现步骤：
    ///   1. 设置 task.expirationHandler（超时清理）
    ///   2. 遍历所有楼层，调 scheduleNext(for:)
    ///   3. task.setTaskCompleted(success: true)
    ///   4. 调 scheduleBackgroundTask() 安排下次
    func handleBackgroundTask(
        profileManager: ProfileManager,
        providerManager: ProviderManager
    ) async {
        // TODO: Phase 3.2
    }

    // MARK: - BGTask 调度

    /// 注册下次 BGTask 触发时间（建议 6–12 小时后，避免频繁唤醒）。
    ///
    /// TODO: Phase 3.2 实现：
    ///   import BackgroundTasks
    ///   let request = BGProcessingTaskRequest(identifier: "com.bunny.lostinblossom.push-agent")
    ///   request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 60 * 60)
    ///   request.requiresNetworkConnectivity = true
    ///   try? BGTaskScheduler.shared.submit(request)
    private func scheduleBackgroundTask() {
        // TODO: Phase 3.2
    }
}
