import SwiftUI

#if os(iOS)
import UIKit
import UserNotifications

/// 远程推送（APNs）：启动请求授权 + 注册 → 拿 device token 发给 hub。
final class PushAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        }
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        CCBridgeWebSocketClient.shared.sendPushToken(hex)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // 注册失败（模拟器/无网络等）——静默，下次启动重试。
    }

    /// 前台到达也弹横幅。
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// 点通知 → 记下 chat_id + 发通知请求打开对应会话。
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard let chatId = response.notification.request.content.userInfo["chat_id"] as? String else { return }
        UserDefaults.standard.set(chatId, forKey: "pendingPushChatId")
        await MainActor.run {
            NotificationCenter.default.post(name: .pushConversationRequested, object: nil)
        }
    }
}
#endif

extension Notification.Name {
    static let pushConversationRequested = Notification.Name("pushConversationRequested")
}
