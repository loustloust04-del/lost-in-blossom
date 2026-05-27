import SwiftUI

/// Caelum's Console — 右滑 page 2 控制台页面
///
/// 设计稿: https://lib.amberrib.com/console.html
/// 配色:
///   - 页面背景: #F5EFE6 (warm cream)
///   - 卡片背景: #FFFFFF
///   - 主文本: #3A332B
///   - 标签文本: #A89E8E
///   - 副文本: #B5AA9A
///   - 强调色: #C8956D (sage / warm tan)
struct ConsoleView: View {
    /// 触发 light haptic 当卡片被点击
    @State private var tappedCardId: String? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // ── 页面头部 ───────────────────────────────────────────
                header
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 4)

                // ── 卡片区（占位，下个 commit 填充）───────────────────
                placeholder
                    .padding(.horizontal, 18)

                Color.clear.frame(height: 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Self.pageBg.ignoresSafeArea())
        .sensoryFeedback(.impact(weight: .light), trigger: tappedCardId)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Caelum's Console")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Self.textPrimary)
            Text(todayString)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Self.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            ForEach(0..<3) { _ in
                RoundedRectangle(cornerRadius: 16)
                    .fill(Self.cardBg)
                    .frame(height: 96)
                    .shadow(color: Color.black.opacity(0.03), radius: 3, x: 0, y: 1)
            }
        }
    }

    private var todayString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: Date())
    }
}

// MARK: - Design tokens

extension ConsoleView {
    static let pageBg     = Color(red: 245/255, green: 239/255, blue: 230/255) // #F5EFE6
    static let cardBg     = Color.white
    static let textPrimary = Color(red:  58/255, green:  51/255, blue:  43/255) // #3A332B
    static let textLabel  = Color(red: 168/255, green: 158/255, blue: 142/255) // #A89E8E
    static let textMuted  = Color(red: 181/255, green: 170/255, blue: 154/255) // #B5AA9A
    static let accent     = Color(red: 200/255, green: 149/255, blue: 109/255) // #C8956D
    static let accentSoft = Color(red: 230/255, green: 215/255, blue: 195/255)
}

#Preview {
    ConsoleView()
}
