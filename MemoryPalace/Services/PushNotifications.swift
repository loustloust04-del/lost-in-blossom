import SwiftUI

#if os(iOS)
import UIKit
import UserNotifications

/// 远程推送（APNs）：启动请求授权 + 注册 → 拿 device token 发给 hub。
final class PushAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UserDefaults.standard.set("1_delegate_init", forKey: "push_debug")
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                UserDefaults.standard.set("2_auth_granted", forKey: "push_debug")
                DispatchQueue.main.async {
                    UserDefaults.standard.set("3_calling_register", forKey: "push_debug")
                    UIApplication.shared.registerForRemoteNotifications()
                }
            } else {
                let reason = error?.localizedDescription ?? "denied"
                UserDefaults.standard.set("2_auth_denied:\(reason)", forKey: "push_debug")
            }
        }
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("[Push] ✅ device token: \(hex.prefix(16))...")
        UserDefaults.standard.set(hex, forKey: "apns_device_token")
        UserDefaults.standard.set("4_SUCCESS", forKey: "push_debug")
        CCBridgeWebSocketClient.shared.sendPushToken(hex)
        CCBridgeWebSocketClient.shared.sendAppState("push_registered")
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[Push] ❌ registration failed: \(error.localizedDescription)")
        UserDefaults.standard.set("4_FAILED:\(error.localizedDescription)", forKey: "push_debug")
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
