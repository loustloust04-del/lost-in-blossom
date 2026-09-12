import Foundation
import AVFoundation

#if os(iOS)
import UIKit
import PushKit
import LiveCommunicationKit

/// 语音通话 · 刀0「电话先响一次」——App 侧的壳。
///
/// 链路：gateway /api/call/ring → APNs VoIP 推送 → PushKit → 这里立刻向系统报来电
///       → LiveCommunicationKit 在锁屏/后台弹出他的名字 → 她接/拒 → 回报 gateway。
/// 铁律：收到 VoIP 推送**必须**在完成前上报一次来电，否则系统杀 App
///       （"Killing app because it never posted an incoming call to the system after receiving a PushKit VoIP push"）。
///       所以连 cancel 推送也走「先报再挂」。
/// 为什么是 LiveCommunicationKit 不是 CallKit：苹果给国区的正路（iOS 17.4+，我们目标 18），
///       给得了锁屏横幅 + 划一下接起来，不需要他真的变成电话 App 里的联系人。
/// 计划书：docs/VOICE-CALL-PLAN.md §5 刀0。
@MainActor
final class VoIPCallService: NSObject {
    static let shared = VoIPCallService()

    private var registry: PKPushRegistry?
    private var manager: ConversationManager?

    /// 当前来电：uuid ↔ gateway 的 call_session_id（同一个字符串）
    private var activeUUID: UUID?
    private var activeSessionId: String?
    private var callerName = "Caelum"
    private var connectedAt: Date?
    private var joined = false

    // MARK: - 启动

    /// didFinishLaunching 里调。PushKit 必须在启动时就注册，否则 App 被杀时收不到 VoIP 推送。
    func start() {
        guard registry == nil else { return }
        let config = ConversationManager.Configuration(
            ringtoneName: nil,
            iconTemplateImageData: nil,
            maximumConversationGroups: 1,
            maximumConversationsPerConversationGroup: 1,
            includesConversationInRecents: false,   // 兔兔：不进系统通话记录，App 自己留
            supportsVideo: false,
            supportedHandleTypes: [.generic]
        )
        let m = ConversationManager(configuration: config)
        m.delegate = self
        manager = m

        let r = PKPushRegistry(queue: .main)
        r.delegate = self
        r.desiredPushTypes = [.voIP]
        registry = r

        CallGreeting.shared.ensureCached()
        print("[Call] PushKit 注册中，LCK 就绪")
    }

    // MARK: - gateway

    private var gatewayBase: String {
        UserDefaults.standard.string(forKey: "gatewayBaseURL") ?? "https://blossom.amberrib.com"
    }
    private var gatewayToken: String {
        UserDefaults.standard.string(forKey: "gatewayAuthToken") ?? ""
    }

    @discardableResult
    private func post(_ path: String, _ body: [String: Any]) async -> Bool {
        guard let url = URL(string: gatewayBase + path) else { return false }
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(gatewayToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if !(200..<300).contains(code) { print("[Call] \(path) → \(code)") }
            return (200..<300).contains(code)
        } catch {
            print("[Call] \(path) 失败: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - 来电

    private func reportIncoming(sessionId: String, caller: String) async {
        guard let manager else { return }
        let uuid = UUID(uuidString: sessionId) ?? UUID()
        activeUUID = uuid
        activeSessionId = sessionId
        callerName = caller
        connectedAt = nil
        joined = false

        let remote = Handle(type: .generic, value: caller.lowercased(), displayName: caller)
        let update = Conversation.Update(members: [remote])
        do {
            try await manager.reportNewIncomingConversation(uuid: uuid, update: update)
            CallLogStore.upsert(CallLogEntry(id: sessionId, caller: caller, startedAt: Date(), outcome: .missed, durationSec: 0))
            print("[Call] ☎️ 来电已上报系统 \(sessionId.prefix(8))")
        } catch {
            print("[Call] 上报来电失败: \(error.localizedDescription)")
            activeUUID = nil; activeSessionId = nil
        }
    }

    /// 他撤回了：横幅消失。规矩是收到 VoIP 推送必须报一次来电——没有在响的就报了再立刻挂。
    private func handleCancel(sessionId: String, caller: String) async {
        guard let manager else { return }
        if let uuid = activeUUID, activeSessionId == sessionId, !joined,
           let conv = manager.conversations.first(where: { $0.uuid == uuid }) {
            manager.reportConversationEvent(.conversationEnded(.now, .remoteEnded), for: conv)
            CallLogStore.update(id: sessionId) { $0.outcome = .cancelled }
            print("[Call] 他撤回了 \(sessionId.prefix(8))")
            clearActive()
            return
        }
        // 没有对应的来电在响：先报再挂（满足系统规矩，用户几乎看不到）
        let uuid = UUID(uuidString: sessionId) ?? UUID()
        let remote = Handle(type: .generic, value: caller.lowercased(), displayName: caller)
        let update = Conversation.Update(members: [remote])
        try? await manager.reportNewIncomingConversation(uuid: uuid, update: update)
        if let conv = manager.conversations.first(where: { $0.uuid == uuid }) {
            manager.reportConversationEvent(.conversationEnded(.now, .remoteEnded), for: conv)
        }
    }

    private func clearActive() {
        activeUUID = nil
        activeSessionId = nil
        connectedAt = nil
        joined = false
        CallGreeting.shared.stop()
    }

    private func configureAudioSession() {
        let s = AVAudioSession.sharedInstance()
        do {
            // 通话模式：让系统级 AEC 有机会干活（Cove §15.4）
            try s.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .defaultToSpeaker])
        } catch {
            print("[Call] 音频会话配置失败: \(error.localizedDescription)")
        }
    }
}

// MARK: - PushKit

extension VoIPCallService: PKPushRegistryDelegate {
    nonisolated func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        guard type == .voIP else { return }
        let hex = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
            UserDefaults.standard.set(hex, forKey: "voip_push_token")
            let ok = await self.post("/api/call/voip-token", ["token": hex])
            print("[Call] VoIP token \(hex.prefix(8))… 上报\(ok ? "成功" : "失败")")
        }
    }

    nonisolated func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        print("[Call] VoIP token 失效")
    }

    nonisolated func pushRegistry(_ registry: PKPushRegistry,
                                  didReceiveIncomingPushWith payload: PKPushPayload,
                                  for type: PKPushType,
                                  completion: @escaping () -> Void) {
        guard type == .voIP else { completion(); return }
        let dict = payload.dictionaryPayload
        let kind = dict["type"] as? String ?? "ring"
        let sessionId = dict["call_session_id"] as? String ?? UUID().uuidString
        let caller = dict["caller"] as? String ?? "Caelum"
        Task { @MainActor in
            if kind == "cancel" {
                await self.handleCancel(sessionId: sessionId, caller: caller)
            } else {
                await self.reportIncoming(sessionId: sessionId, caller: caller)
            }
            completion()
        }
    }
}

// MARK: - LiveCommunicationKit

extension VoIPCallService: ConversationManagerDelegate {
    nonisolated func conversationManagerDidBegin(_ manager: ConversationManager) {}
    nonisolated func conversationManagerDidReset(_ manager: ConversationManager) {
        Task { @MainActor in self.clearActive() }
    }
    nonisolated func conversationManager(_ manager: ConversationManager, conversationChanged conversation: Conversation) {}

    nonisolated func conversationManager(_ manager: ConversationManager, perform action: ConversationAction) {
        Task { @MainActor in
            guard let sessionId = self.activeSessionId, action.conversationUUID == self.activeUUID else {
                action.fail(); return
            }
            switch action {
            case let join as JoinConversationAction:
                // 她接了
                self.configureAudioSession()
                self.joined = true
                self.connectedAt = Date()
                if let conv = manager.conversations.first(where: { $0.uuid == self.activeUUID }) {
                    manager.reportConversationEvent(.conversationConnected(.now), for: conv)
                }
                join.fulfill(dateConnected: .now)
                CallLogStore.update(id: sessionId) { $0.outcome = .answered }
                await self.post("/api/call/answer", ["call_session_id": sessionId])

            case let end as EndConversationAction:
                // 没接就是拒接；接了再挂是挂断
                let wasJoined = self.joined
                let dur = self.connectedAt.map { Int(Date().timeIntervalSince($0)) } ?? 0
                end.fulfill(dateEnded: .now)
                if wasJoined {
                    CallLogStore.update(id: sessionId) { $0.outcome = .answered; $0.durationSec = dur }
                    await self.post("/api/call/hangup", ["call_session_id": sessionId])
                } else {
                    CallLogStore.update(id: sessionId) { $0.outcome = .declined }
                    await self.post("/api/call/decline", ["call_session_id": sessionId])
                }
                self.clearActive()

            default:
                action.fulfill()
            }
        }
    }

    nonisolated func conversationManager(_ manager: ConversationManager, timedOutPerforming action: ConversationAction) {
        action.fail()
    }

    nonisolated func conversationManager(_ manager: ConversationManager, didActivate audioSession: AVAudioSession) {
        // 音频会话由系统激活后才能出声——他的第一句在这儿
        Task { @MainActor in
            guard self.joined else { return }
            CallGreeting.shared.play()
        }
    }

    nonisolated func conversationManager(_ manager: ConversationManager, didDeactivate audioSession: AVAudioSession) {
        Task { @MainActor in CallGreeting.shared.stop() }
    }
}
#endif
