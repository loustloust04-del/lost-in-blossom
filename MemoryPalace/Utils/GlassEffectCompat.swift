#if os(iOS)
import SwiftUI

// MARK: - Glass Effect Compatibility
//
// iOS 26+ 用原生 .glassEffect() / .buttonStyle(.glass)；
// iOS 17–25 fallback 到 .background(shape.fill(.ultraThinMaterial))。
// 视觉原则：iOS 26 上效果与原始代码完全一致，iOS 17 用半透明材质近似。

extension View {
    /// 带形状的玻璃效果兼容封装。
    /// - Parameters:
    ///   - tint: tint 颜色，对应原 `.regular.tint(color)`
    ///   - interactive: 是否加 `.interactive()`（允许内容接收点击穿透）
    ///   - shape: 玻璃/背景形状
    @ViewBuilder
    func glassEffectCompat<S: Shape>(
        tint: Color,
        interactive: Bool = false,
        in shape: S
    ) -> some View {
        if #available(iOS 26.0, *) {
            self.modifier(_GlassShapeModifier(tint: tint, interactive: interactive, shape: AnyShape(shape)))
        } else {
            self.background(shape.fill(.ultraThinMaterial))
        }
    }

    /// 不指定形状时的玻璃效果兼容封装（矩形背景）。
    @ViewBuilder
    func glassEffectCompat(tint: Color, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.modifier(_GlassShapeModifier(tint: tint, interactive: interactive, shape: AnyShape(Rectangle())))
        } else {
            self.background(.ultraThinMaterial)
        }
    }

    /// `.buttonStyle(.glass)` 的兼容封装（用于 ScrollToBottomButton）。
    /// iOS 26+ 用原生 GlassButtonStyle；iOS 17–25 用 plain + ultraThinMaterial 圆圈。
    @ViewBuilder
    func glassButtonStyleCompat() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self
                .buttonStyle(.plain)
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
        }
    }
}

/// iOS 26+ 专用 ViewModifier，封装原生 glassEffect 调用。
/// 标记 @available 保证只在支持的系统上实例化。
@available(iOS 26.0, *)
private struct _GlassShapeModifier: ViewModifier {
    let tint: Color
    let interactive: Bool
    let shape: AnyShape

    func body(content: Content) -> some View {
        if interactive {
            content.glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else {
            content.glassEffect(.regular.tint(tint), in: shape)
        }
    }
}
#endif
