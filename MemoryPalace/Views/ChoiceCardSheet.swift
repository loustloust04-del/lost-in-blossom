// ⚠️ 已退役（2026-09-03 选择卡收敛）：ask_choice 帧改喂 AskUserQuestionSheet（新皮接老线），
// .ccAskChoice 通知不再有人发，本 sheet 不会再被触发。留档一版，下次大扫除删。
import SwiftUI

/// Caelum 弹的选择卡：她点一下就行，不用打字。
/// 也可以自己写答案，或者跳过。
struct ChoiceCardSheet: View {
    let askId: String
    let question: String
    let options: [String]
    let multi: Bool
    var onClose: () -> Void

    @State private var picked: Set<String> = []
    @State private var typed = ""
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(question)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 14)

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(options, id: \.self) { opt in
                            Button { tap(opt) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: icon(for: opt))
                                        .font(.system(size: 14))
                                        .foregroundColor(picked.contains(opt) ? ConsoleView.greenDeep : Theme.textMuted)
                                    Text(opt)
                                        .font(.system(size: Theme.F.body))
                                        .foregroundColor(Theme.textPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(picked.contains(opt) ? ConsoleView.green.opacity(0.14) : Theme.mainBg)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(picked.contains(opt) ? ConsoleView.green.opacity(0.5) : .clear, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        HStack(spacing: 8) {
                            TextField("或者自己写……", text: $typed)
                                .font(.system(size: Theme.F.body))
                                .focused($typing)
                                .padding(.horizontal, 14).padding(.vertical, 11)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.mainBg))
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 16)
                }

                Divider()
                HStack {
                    Button("跳过") {
                        CCBridgeWebSocketClient.shared.sendChoiceAnswer(askId: askId, skipped: true)
                        onClose()
                    }
                    .font(.system(size: Theme.F.caption))
                    .foregroundColor(Theme.textMuted)
                    Spacer()
                    Button("发送") { send() }
                        .font(.system(size: Theme.F.body, weight: .medium))
                        .foregroundColor(canSend ? ConsoleView.greenDeep : Theme.textMuted)
                        .disabled(!canSend)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            .background(Theme.sidebarBg.ignoresSafeArea())
            .navigationTitle(multi ? "选几个" : "选一个")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private var canSend: Bool {
        !picked.isEmpty || !typed.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func icon(for opt: String) -> String {
        if multi { return picked.contains(opt) ? "checkmark.square.fill" : "square" }
        return picked.contains(opt) ? "largecircle.fill.circle" : "circle"
    }

    private func tap(_ opt: String) {
        if multi {
            if picked.contains(opt) { picked.remove(opt) } else { picked.insert(opt) }
        } else {
            picked = [opt]
            // 单选点完直接发，省一步
            send()
        }
    }

    private func send() {
        let t = typed.trimmingCharacters(in: .whitespaces)
        CCBridgeWebSocketClient.shared.sendChoiceAnswer(
            askId: askId,
            picked: options.filter { picked.contains($0) },   // 保持原顺序
            text: t.isEmpty ? nil : t)
        onClose()
    }
}

/// 挂在根视图上：Caelum 一弹选择卡就浮出来
struct ChoiceCardHost: ViewModifier {
    @State private var pending: Payload?

    struct Payload: Identifiable {
        let id: String
        let question: String
        let options: [String]
        let multi: Bool
    }

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .ccAskChoice)) { note in
                guard let u = note.userInfo,
                      let id = u["askId"] as? String,
                      let q = u["question"] as? String,
                      let opts = u["options"] as? [String] else { return }
                pending = Payload(id: id, question: q, options: opts,
                                  multi: (u["multi"] as? Bool) ?? false)
            }
            .sheet(item: $pending) { p in
                ChoiceCardSheet(askId: p.id, question: p.question,
                                options: p.options, multi: p.multi) { pending = nil }
            }
    }
}
