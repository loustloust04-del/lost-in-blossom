import Foundation
import SwiftData

// MARK: - 通知快速回复的补写
//
// 2026-09-06 兔兔实测报的 bug：「通过通知回复的话，不会落在我们的对话框里，
// 只有主人的在，我的不在。」
//
// 根因：CCBridgeWebSocketClient.sendQuickReply 只发了 WS 帧，没落库。
// App 内正常发消息走 sendMessage，那条会先建一个 user 节点再发；
// 通知回复发生在 App 后台，拿不到 ModelContext 与 viewModel，所以当时跳过了。
//
// 解法：发的时候排队（UserDefaults），App 回前台时补写。
// 不在通知 handler 里直接动 SwiftData——后台唤醒只有几十秒，
// 建容器 + 找会话 + 维护 parentId 链，中途失败反而丢消息。
// 而兔兔本来也是打开 App 才看对话框，延迟补写足够。
extension ConversationViewModel {

    /// App 回前台时调。把通知里回过的话补进对应会话。
    @MainActor
    func flushPendingQuickReplies(context: ModelContext) {
        let pending = CCBridgeWebSocketClient.drainPendingQuickReplies()
        guard !pending.isEmpty else { return }

        for item in pending {
            // chat_id 即 conversation.id（hub 协议里两者同一）
            guard let convo = selectedConversation, convo.id == item.chatId else {
                // 不是当前打开的这个会话——放回队列，等她切过去时再补，
                // 别写进错误的对话里
                CCBridgeWebSocketClient.enqueuePendingQuickReply(chatId: item.chatId, text: item.text)
                continue
            }
            // 已经有同样内容的相邻 user 节点就跳过（防重复补写）
            if let last = currentPath.last, last.role == "user", last.content == item.text { continue }

            _ = insertGroupNode(
                role: "user",
                content: item.text,
                senderId: nil,
                senderName: nil,
                conversation: convo,
                context: context
            )
        }
        try? context.save()
    }
}
