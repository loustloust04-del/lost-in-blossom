import SwiftUI

/// 等待泡的三个点——回复还没来时的「他在打字」。
///
/// 2026-08-24 兔兔真机验收后返工：第一版我做成了透明度+缩放的「呼吸」，
/// 位置全程没动，看着是明灭不是打字。粟粟那版只动一样东西——offset(y:)
/// 在 -3 / +1 之间弹，颜色和大小全程恒定，所以读起来是「跳」。
/// 本版按她的参数复刻：duration 0.45、错开 0.15、幅度 -3↔+1。
struct TypingDotsView: View {
    @State private var bouncing = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Theme.textMuted.opacity(0.5))
                    .frame(width: 5, height: 5)
                    .offset(y: bouncing ? -3 : 1)
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.15),
                        value: bouncing
                    )
            }
        }
        .padding(.vertical, 4)
        .onAppear { bouncing = true }
        .accessibilityLabel("正在输入")
    }
}
