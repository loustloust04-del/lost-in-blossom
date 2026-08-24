import SwiftUI

/// 等待泡的三个点——回复还没来时的「他在打字」。
///
/// 原本这里是三个静止的 Circle（CardFlowView 内联），看着像加载失败。
/// 思路取自粟粟 MemoryPalace 的 ChatBubbleStyle.TypingDotsView：灵魂在 delay 错开，
/// 三个点依次起落形成波，而不是齐刷刷一起闪。
/// 2026-08-24 Fable：与 latestThinking 串台的拆除同批——那具尸体让开的位置，由它补上。
struct TypingDotsView: View {
    @State private var phase = false

    /// 单点起落时长；三点各自延后 0.15s 形成行进波。
    private let duration = 0.6
    private let stagger = 0.15

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Theme.textMuted.opacity(phase ? 0.75 : 0.3))
                    .frame(width: 5, height: 5)
                    .scaleEffect(phase ? 1.0 : 0.72)
                    .animation(
                        .easeInOut(duration: duration)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * stagger),
                        value: phase
                    )
            }
        }
        .padding(.vertical, 4)
        // onAppear 里翻转，动画才会从「出现那一刻」起算
        .onAppear { phase = true }
        .accessibilityLabel("正在输入")
    }
}
