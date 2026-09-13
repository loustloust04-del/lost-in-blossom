import Foundation
import AVFoundation

#if os(iOS)
import UIKit
import PushKit
import CallKit

/// 语音通话 · 刀0「电话先响一次」——App 侧的壳。
///
/// 链路：gateway /api/call/ring → APNs VoIP 推送 → PushKit → 这里**同步**向系统报来电
///       → 系统在锁屏/后台弹出他的名字 → 她接/拒 → 回报 gateway。
///
/// 为什么最后用的是 CallKit 不是 LiveCommunicationKit（09-13 真机第一通没响，查出来的）：
///   PushKit 的合同是「delegate 返回前必须已经报了来电」，否则系统当场杀 App
///   （"Killing app because it never posted an incoming call to the system after receiving a PushKit VoIP push"）。
///   LCK 的 reportNewIncomingConversation 是 async，只能包在 Task 里——Task 是「等会儿再做」，
///   前台没事，后台/锁屏必死。苹果 DTS 在论坛承认这是 LCK 的已知 bug（thread/774958、775348）。
///   CallKit 的 reportNewIncomingCall 是同步的，同一套代码就能过。
///   国区那条禁令是 App Store 审核政策（要求上架 App 对中国用户运行时关掉 CallKit），不是系统层面的；
///   我们是粟粟签名直装，不走商店，CallKit 在她手机上能用。
/// includesCallsInRecents = false：兔兔定的，不进系统通话记录，App 自己留。
/// 计划书：docs/VOICE-CALL-PLAN.md §5 刀0。
@MainActor
final class VoIPCallService: NSObject {
    static let shared = VoIPCallService()

    private var registry: PKPushRegistry?
    private var provider: CXProvider?

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
        let config = CXProviderConfiguration()
        config.supportsVideo = false
        config.maximumCallGroups = 1
        config.maximumCallsPerCallGroup = 1
        config.includesCallsInRecents = false   // 兔兔：不进系统通话记录，App 自己留
        config.supportedHandleTypes = [.generic]
        let p = CXProvider(configuration: config)
        p.setDelegate(self, queue: nil)          // nil = 主队列，和 PushKit 同一条线
        provider = p

        let r = PKPushRegistry(queue: .main)     // DTS：PushKit 和 CallKit 都放主队列，别换线程
        r.delegate = self
        r.desiredPushTypes = [.voIP]
        registry = r

        CallGreeting.shared.ensureCached()
        print("[Call] PushKit 注册中，CallKit provider 就绪")
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

    // MARK: - 来电（必须同步完成上报，不能 Task）

    /// 收到 ring 推送：立刻报给系统。completion 在系统回话后再调。
    private func reportIncoming(sessionId: String, caller: String, completion: @escaping () -> Void) {
        guard let provider else { completion(); return }
        let uuid = UUID(uuidString: sessionId) ?? UUID()
        activeUUID = uuid
        activeSessionId = sessionId
        callerName = caller
        connectedAt = nil
        joined = false

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: caller)
        update.localizedCallerName = caller
        update.hasVideo = false
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false

        CallLogStore.upsert(CallLogEntry(id: sessionId, caller: caller, startedAt: Date(), outcome: .missed, durationSec: 0))
        provider.reportNewIncomingCall(with: uuid, update: update) { error in
            if let error {
                print("[Call] 上报来电失败: \(error.localizedDescription)")
                Task { @MainActor in
                    if self.activeUUID == uuid { self.clearActive() }
                }
            } else {
                print("[Call] ☎️ 来电已上报系统 \(sessionId.prefix(8))")
            }
            completion()
        }
    }

    /// 他撤回了：横幅消失。规矩是收到 VoIP 推送必须报一次来电——没有在响的就报了再立刻挂。
    private func handleCancel(sessionId: String, caller: String, completion: @escaping () -> Void) {
        guard let provider else { completion(); return }
        if let uuid = activeUUID, activeSessionId == sessionId, !joined {
            provider.reportCall(with: uuid, endedAt: nil, reason: .remoteEnded)
            CallLogStore.update(id: sessionId) { $0.outcome = .cancelled }
            print("[Call] 他撤回了 \(sessionId.prefix(8))")
            clearActive()
            completion()
            return
        }
        // 没有对应的来电在响：先报再挂（满足系统规矩，用户几乎看不到）
        let uuid = UUID(uuidString: sessionId) ?? UUID()
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: caller)
        update.localizedCallerName = caller
        provider.reportNewIncomingCall(with: uuid, update: update) { _ in
            provider.reportCall(with: uuid, endedAt: nil, reason: .unanswered)
            completion()
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

    // MARK: - CallKit 动作（provider 队列 = 主队列，assumeIsolated 不跳线程）

    fileprivate func handleAnswer(_ action: CXAnswerCallAction) {
        guard let sessionId = activeSessionId, action.callUUID == activeUUID else { action.fail(); return }
        configureAudioSession()
        joined = true
        connectedAt = Date()
        action.fulfill()
        CallLogStore.update(id: sessionId) { $0.outcome = .answered }
        Task { await self.post("/api/call/answer", ["call_session_id": sessionId]) }
    }

    fileprivate func handleEnd(_ action: CXEndCallAction) {
        guard let sessionId = activeSessionId, action.callUUID == activeUUID else { action.fail(); return }
        // 没接就是拒接；接了再挂是挂断
        let wasJoined = joined
        let dur = connectedAt.map { Int(Date().timeIntervalSince($0)) } ?? 0
        action.fulfill()
        if wasJoined {
            CallLogStore.update(id: sessionId) { $0.outcome = .answered; $0.durationSec = dur }
            Task { await self.post("/api/call/hangup", ["call_session_id": sessionId]) }
        } else {
            CallLogStore.update(id: sessionId) { $0.outcome = .declined }
            Task { await self.post("/api/call/decline", ["call_session_id": sessionId]) }
        }
        clearActive()
    }

    fileprivate func handleAudioActivated() {
        // 音频会话由系统激活后才能出声——他的第一句在这儿
        guard joined else { return }
        CallGreeting.shared.play()
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

    /// 注册时 queue = .main，所以这里已经在主线程：用 assumeIsolated 同步进主 actor，
    /// 在返回前把来电报给系统。这里绝对不能用 Task（09-13 第一通没响就是因为它）。
    nonisolated func pushRegistry(_ registry: PKPushRegistry,
                                  didReceiveIncomingPushWith payload: PKPushPayload,
                                  for type: PKPushType,
                                  completion: @escaping () -> Void) {
        guard type == .voIP else { completion(); return }
        let dict = payload.dictionaryPayload
        let kind = dict["type"] as? String ?? "ring"
        let sessionId = dict["call_session_id"] as? String ?? UUID().uuidString
        let caller = dict["caller"] as? String ?? "Caelum"
        MainActor.assumeIsolated {
            if kind == "cancel" {
                self.handleCancel(sessionId: sessionId, caller: caller, completion: completion)
            } else {
                self.reportIncoming(sessionId: sessionId, caller: caller, completion: completion)
            }
        }
    }
}

// MARK: - CallKit

extension VoIPCallService: CXProviderDelegate {
    nonisolated func providerDidReset(_ provider: CXProvider) {
        MainActor.assumeIsolated { self.clearActive() }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        MainActor.assumeIsolated { self.handleAnswer(action) }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        MainActor.assumeIsolated { self.handleEnd(action) }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        action.fulfill()
    }

    nonisolated func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        action.fail()
    }

    nonisolated func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        MainActor.assumeIsolated { self.handleAudioActivated() }
    }

    nonisolated func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        MainActor.assumeIsolated { CallGreeting.shared.stop() }
    }
}
#endif
