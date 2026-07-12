import Foundation
import SwiftData
import AVFoundation

/// 发语音条：```voice 意向协议（零新窄工具，模式同 AgentBookNoteWriter 的 ```book-note）。
///
/// AI 在回复里输出 ```voice 块（内容 = 表演脚本，≠ 气泡正文），turn 收口时本类把块
/// 变成占位行、异步走 ElevenLabs 生成 mp3、落文件库、往 node 挂 .audioRef segment。
/// 失败时占位行替换成灰字失败行（脚本原文保住）。流式期间块可见 = 「TA 在录语音」。
enum VoiceMessageWriter {

    static let placeholderLine = "🎤 语音条生成中…"
    /// 脚本长度上限（攻略纪律 60–120 字；超长截断防误写整篇）
    static let scriptCap = 1000

    private static let intentRegex = try! NSRegularExpression(
        pattern: "```voice\\s*\\n([\\s\\S]*?)```",
        options: []
    )

    // 测试注入点
    static var client = ElevenLabsClient()
    static var apiKeyProvider: () -> String? = { KeychainStore.get(account: VoiceTuning.keychainAccount) }
    static var proactiveEnabledProvider: () -> Bool = { UserDefaults.standard.bool(forKey: VoiceTuning.proactiveKey) }
    /// 无 ProfileManager 引用的调用点（CC 主动消息 / 换一版）用；测试注入假楼层防污染真 UserDefaults
    static var profilesProvider: () -> [Profile] = { ProfileManager.loadProfiles() }

    /// 生成中的 node（占位/换一版共用，防重入）
    @MainActor static private(set) var inFlight = Set<String>()

    // MARK: - 收口入口

    /// assistant turn 收口时调（ContentView .assistantTurnDidFinish 订阅者）。
    /// 无块零成本；块被消费后不再匹配 = 天然幂等。
    @MainActor
    static func processChatIntents(nodeId: String, context: ModelContext, profiles: [Profile]) {
        let nodeDesc = FetchDescriptor<MessageNode>(predicate: #Predicate { $0.id == nodeId })
        guard let node = (try? context.fetch(nodeDesc))?.first,
              node.role == "assistant",
              node.content.contains("```voice") else { return }

        let content = node.content
        let ns = content as NSString
        let matches = intentRegex.matches(in: content, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return }

        let profile = profiles.first { $0.id == node.profileId }
        let key = apiKeyProvider()
        let voiceId = profile?.elevenVoiceId
        let script = String(ns.substring(with: matches[0].range(at: 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(scriptCap))
        let canGenerate = proactiveEnabledProvider()
            && !(key ?? "").isEmpty && !(voiceId ?? "").isEmpty && !script.isEmpty

        // 倒序替换保 range 有效：首块 → 占位行（可生成）/ 脚本文字（降级）；多余块 → 脚本文字
        var newContent = content
        for (idx, m) in Array(matches.enumerated()).reversed() {
            let body = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let replacement = (idx == 0 && canGenerate) ? placeholderLine : body
            newContent = (newContent as NSString).replacingCharacters(in: m.range, with: replacement)
        }
        node.content = newContent
        try? context.save()

        guard canGenerate, let key, let voiceId else { return }
        generate(script: script, nodeId: nodeId, voiceId: voiceId, apiKey: key, context: context)
    }

    // MARK: - 换一版

    /// 语音条胶囊菜单「换一版」：拿 segment 里存的脚本重跑 TTS，原地换文件。
    @MainActor
    static func regenerate(nodeId: String, context: ModelContext) {
        guard !inFlight.contains(nodeId),
              let node = fetchNode(nodeId, context: context),
              let segs = node.segments,
              let audioIdx = segs.firstIndex(where: {
                  if case .audioRef = $0 { return true } else { return false }
              }),
              case .audioRef(_, _, let oldPath, _, let script?) = segs[audioIdx],
              !script.isEmpty,
              let key = apiKeyProvider(), !key.isEmpty else {
            ToastCenter.shared.show("换不了：脚本或 key 不在")
            return
        }
        // voice 用 node 所在楼层当前配置（楼层可能换过声音——换一版跟新声音走）
        guard let profile = profilesProvider().first(where: { $0.id == node.profileId }),
              let voiceId = profile.elevenVoiceId, !voiceId.isEmpty else {
            ToastCenter.shared.show("这个楼层还没选声音")
            return
        }

        inFlight.insert(nodeId)
        ToastCenter.shared.show("正在换一版…")
        Task { @MainActor in
            defer { inFlight.remove(nodeId) }
            do {
                let audio = try await client.synthesize(script: script, voiceId: voiceId, apiKey: key)
                guard let node = fetchNode(nodeId, context: context), var segs = node.segments else { return }
                let (path, duration) = try persistAudio(audio, node: node, context: context)
                // 删旧文件（失败不阻断——孤儿文件无害）
                if let old = FileLibraryStore.absoluteURL(oldPath, profileId: node.profileId) {
                    try? FileManager.default.removeItem(at: old)
                }
                if let idx = segs.firstIndex(where: {
                    if case .audioRef = $0 { return true } else { return false }
                }) {
                    segs[idx] = .audioRef(
                        name: (path as NSString).lastPathComponent, mime: "audio/mpeg",
                        path: path, duration: duration, script: script
                    )
                    node.setSegments(segs)
                    try? context.save()
                    ToastCenter.shared.show("换好了")
                }
            } catch {
                ToastCenter.shared.show("换一版没成功（\(shortPhrase(error))）")
            }
        }
    }

    // MARK: - 生成

    @MainActor
    private static func generate(script: String, nodeId: String, voiceId: String, apiKey: String, context: ModelContext) {
        guard !inFlight.contains(nodeId) else { return }
        inFlight.insert(nodeId)
        Task { @MainActor in
            defer { inFlight.remove(nodeId) }
            do {
                let audio = try await client.synthesize(script: script, voiceId: voiceId, apiKey: apiKey)
                // 收尾时 node 可能已被删/换楼层——fetch 不到就静默放弃（孤儿 mp3 不落盘）
                guard let node = fetchNode(nodeId, context: context) else { return }
                let (path, duration) = try persistAudio(audio, node: node, context: context)
                var segs = node.segments ?? []
                segs.append(.audioRef(
                    name: (path as NSString).lastPathComponent, mime: "audio/mpeg",
                    path: path, duration: duration, script: script
                ))
                node.setSegments(segs)
                removePlaceholder(from: node)
                try? context.save()
            } catch {
                guard let node = fetchNode(nodeId, context: context) else { return }
                let quoted = script.split(separator: "\n").map { "> \($0)" }.joined(separator: "\n")
                let failLine = "> 🎤 语音条没成功（\(shortPhrase(error))）\n\(quoted)"
                node.content = node.content.replacingOccurrences(of: placeholderLine, with: failLine)
                try? context.save()
            }
        }
    }

    /// mp3 落文件库（attachments/{对话目录}/voice-*.mp3），返回 (相对路径, 时长)
    private static func persistAudio(_ audio: Data, node: MessageNode, context: ModelContext) throws -> (String, Double?) {
        let stamp = Self.fileStampFormatter.string(from: Date())
        let path = try AttachmentStore.save(
            fileName: "voice-\(stamp).mp3", data: audio,
            conversationId: node.conversationId,
            conversationTitle: conversationTitle(node: node, context: context),
            profileId: node.profileId
        )
        var duration: Double? = nil
        if let url = FileLibraryStore.absoluteURL(path, profileId: node.profileId),
           let player = try? AVAudioPlayer(contentsOf: url),
           player.duration.isFinite, player.duration > 0 {
            duration = player.duration
        }
        return (path, duration)
    }

    @MainActor
    private static func removePlaceholder(from node: MessageNode) {
        var content = node.content.replacingOccurrences(of: placeholderLine, with: "")
        // 清占位行留下的连续空行
        while content.contains("\n\n\n") { content = content.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        node.content = content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fetchNode(_ nodeId: String, context: ModelContext) -> MessageNode? {
        let desc = FetchDescriptor<MessageNode>(predicate: #Predicate { $0.id == nodeId })
        return (try? context.fetch(desc))?.first
    }

    private static func conversationTitle(node: MessageNode, context: ModelContext) -> String? {
        let convId = node.conversationId
        let desc = FetchDescriptor<Conversation>(predicate: #Predicate { $0.id == convId })
        return (try? context.fetch(desc))?.first?.title
    }

    private static func shortPhrase(_ error: Error) -> String {
        (error as? ElevenLabsError)?.shortPhrase ?? "出了点问题"
    }

    private static let fileStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
