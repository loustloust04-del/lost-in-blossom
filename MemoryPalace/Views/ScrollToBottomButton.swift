import SwiftUI

/// 右下悬浮玻璃按钮 — 离底时出现，点击回底。
///
/// **iOS 26 正确做法**：用 `.buttonStyle(.glass)` 官方 GlassButtonStyle，不要
/// 用 `.glassEffect(...)` + `.buttonStyle(.plain)` 的 hack 组合（会吞 hit test
/// 和按压反馈，粟粟实测 5/6 次点不中）。
/// - Pin bar 用 `.glassEffect(...)` 没问题是因为它是 HStack + .onTapGesture，
///   不是 SwiftUI Button
struct ScrollToBottomButton: View {
    let isVisible: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.down")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Theme.textMuted)
        }
        #if os(iOS)
        // 不 clipShape、不 frame — glass 内置按压 morph 动画需要空间自由形变
        .buttonStyle(.glass)
        #else
        .buttonStyle(.plain)
        .background(Circle().fill(.ultraThinMaterial))
        .overlay(Circle().stroke(Theme.accent.opacity(0.4), lineWidth: 0.5))
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
        #endif
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 8)
        .animation(.spring(duration: 0.3), value: isVisible)
        .allowsHitTesting(isVisible)
    }
}
