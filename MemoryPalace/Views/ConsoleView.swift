import SwiftUI

/// Caelum's Console — 右滑 page 2 控制台页面
///
/// 设计稿: https://lib.amberrib.com/console.html
struct ConsoleView: View {
    /// 触发 light haptic：卡片被点击
    @State private var tappedCardId: String? = nil
    /// 状态切换 success haptic：例如标记已服药
    @State private var medicationTaken: Bool = true

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 4)

                cards
                    .padding(.horizontal, 18)

                Color.clear.frame(height: 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Self.pageBg.ignoresSafeArea())
        .sensoryFeedback(.impact(weight: .light), trigger: tappedCardId)
        .sensoryFeedback(.success, trigger: medicationTaken)
    }

    // MARK: - Header

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

    // MARK: - Cards container

    private var cards: some View {
        VStack(spacing: 12) {
            waterCard
            foodCard
            medicationCard
            sleepCard
            menstrualCard
            stepsCard
            screenTimeCard
            twitterCard
        }
    }

    // MARK: - 1. 饮水

    private var waterCard: some View {
        ConsoleCard(id: "water", tappedCardId: $tappedCardId) {
            HStack(spacing: 16) {
                ProgressRing(progress: 4.0 / 6.0, size: 56, lineWidth: 6) {
                    Text("4")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Self.textPrimary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    CardLabel("饮水", icon: "drop")
                    Text("4 杯 / 6")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Self.textPrimary)
                    Text("再喝 2 杯就达标了")
                        .font(.system(size: 12))
                        .foregroundColor(Self.textMuted)
                }
                Spacer()
            }
        }
    }

    // MARK: - 2. 进食

    private var foodCard: some View {
        ConsoleCard(id: "food", tappedCardId: $tappedCardId) {
            HStack(spacing: 16) {
                ProgressRing(progress: 2.0 / 3.0, size: 56, lineWidth: 6) {
                    Text("2")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Self.textPrimary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    CardLabel("进食", icon: "fork.knife")
                    Text("2 餐 / 3")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Self.textPrimary)
                    Text("最近: 燕麦粥 + 蓝莓")
                        .font(.system(size: 12))
                        .foregroundColor(Self.textMuted)
                }
                Spacer()
            }
        }
    }

    // MARK: - 3. 药物

    private var medicationCard: some View {
        ConsoleCard(id: "medication", tappedCardId: $tappedCardId) {
            HStack(spacing: 16) {
                Image(systemName: "pills")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundColor(Self.textLabel)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle().fill(Self.accentSoft.opacity(0.5))
                    )
                VStack(alignment: .leading, spacing: 4) {
                    CardLabel("药物", icon: nil)
                    Text("维生素 D + 益生菌")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Self.textPrimary)
                    Text("今日 1 / 1")
                        .font(.system(size: 12))
                        .foregroundColor(Self.textMuted)
                }
                Spacer()
                StatusChip(
                    text: medicationTaken ? "已服用" : "未服用",
                    color: medicationTaken ? Self.successGreen : Self.warnAmber
                )
                .onTapGesture {
                    medicationTaken.toggle()
                }
            }
        }
    }

    // MARK: - 4. 睡眠

    private var sleepCard: some View {
        ConsoleCard(id: "sleep", tappedCardId: $tappedCardId) {
            HStack(spacing: 16) {
                Image(systemName: "moon")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundColor(Self.textLabel)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Self.accentSoft.opacity(0.5)))
                VStack(alignment: .leading, spacing: 4) {
                    CardLabel("睡眠", icon: nil)
                    Text("7 h 32 m")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Self.textPrimary)
                    Text("23:18 → 06:50")
                        .font(.system(size: 12))
                        .foregroundColor(Self.textMuted)
                }
                Spacer()
            }
        }
    }

    // MARK: - 5. 月经周期

    private var menstrualCard: some View {
        ConsoleCard(id: "menstrual", tappedCardId: $tappedCardId) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    CardLabel("月经周期", icon: "calendar")
                    Spacer()
                    Text("第 18 天")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Self.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Self.accentSoft))
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("预计下次")
                        .font(.system(size: 12))
                        .foregroundColor(Self.textMuted)
                    Text("5 月 12 日")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Self.textPrimary)
                    Spacer()
                }
                MiniBarChart(values: [0.3, 0.5, 0.4, 0.6, 0.9, 0.7, 0.5, 0.3, 0.2, 0.4, 0.5, 0.6])
                    .frame(height: 28)
            }
        }
    }

    // MARK: - 6. 步数

    private var stepsCard: some View {
        ConsoleCard(id: "steps", tappedCardId: $tappedCardId) {
            VStack(alignment: .leading, spacing: 8) {
                CardLabel("步数", icon: "figure.walk")
                HStack(alignment: .firstTextBaseline) {
                    Text("8,423")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Self.textPrimary)
                    Text("步")
                        .font(.system(size: 12))
                        .foregroundColor(Self.textMuted)
                    Spacer()
                    Text("目标 10,000")
                        .font(.system(size: 11))
                        .foregroundColor(Self.textLabel)
                }
                MiniBarChart(values: [0.5, 0.8, 0.6, 0.9, 0.7, 0.4, 0.84])
                    .frame(height: 32)
            }
        }
    }

    // MARK: - 7. 屏幕使用时间

    private var screenTimeCard: some View {
        ConsoleCard(id: "screen", tappedCardId: $tappedCardId) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    CardLabel("屏幕使用时间", icon: "iphone")
                    Spacer()
                    StatusChip(text: "适度", color: Self.successGreen)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("3 h 12 m")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Self.textPrimary)
                    Spacer()
                    Text("/ 5 h 目标")
                        .font(.system(size: 11))
                        .foregroundColor(Self.textLabel)
                }
                ProgressBar(progress: 3.2 / 5.0, color: Self.accent)
                    .frame(height: 6)
                VStack(spacing: 6) {
                    socialAppRow(name: "微信", value: "45 m", icon: "message")
                    socialAppRow(name: "Twitter", value: "32 m", icon: "bubble.left")
                }
                .padding(.top, 2)
            }
        }
    }

    private func socialAppRow(name: String, value: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(Self.textLabel)
                .frame(width: 16)
            Text(name)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Self.textPrimary.opacity(0.8))
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Self.textLabel)
                .monospacedDigit()
        }
    }

    // MARK: - 8. 推特动态

    private var twitterCard: some View {
        ConsoleCard(id: "twitter", tappedCardId: $tappedCardId) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    CardLabel("推特动态", icon: "at")
                    Spacer()
                    Text("今日 12 条")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Self.accent)
                }
                Text("最近: 今天读到一篇关于具身智能的论文，发现 token-level world model 跟早期 hidden Markov model 思路其实是一脉相承的……")
                    .font(.system(size: 13))
                    .foregroundColor(Self.textPrimary.opacity(0.85))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 12) {
                    Label("23", systemImage: "heart")
                    Label("5", systemImage: "arrow.2.squarepath")
                    Label("8", systemImage: "bubble.left")
                }
                .font(.system(size: 11))
                .foregroundColor(Self.textLabel)
                .padding(.top, 2)
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
    static let successGreen = Color(red: 132/255, green: 174/255, blue: 124/255) // #84AE7C
    static let warnAmber    = Color(red: 218/255, green: 162/255, blue:  88/255) // #DAA258
}

// MARK: - Reusable subviews

/// 通用卡片容器：白底，圆角 16，浅阴影，点击触发 haptic
private struct ConsoleCard<Content: View>: View {
    let id: String
    @Binding var tappedCardId: String?
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(ConsoleView.cardBg)
                    .shadow(color: Color.black.opacity(0.03), radius: 3, x: 0, y: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .onTapGesture {
                tappedCardId = UUID().uuidString
            }
    }
}

/// 卡片标签（小号 11pt 标签色 + 可选图标）
private struct CardLabel: View {
    let text: String
    let icon: String?

    init(_ text: String, icon: String?) {
        self.text = text
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .regular))
            }
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .tracking(0.3)
        }
        .foregroundColor(ConsoleView.textLabel)
    }
}

/// 圆环进度
private struct ProgressRing<Center: View>: View {
    let progress: Double
    let size: CGFloat
    let lineWidth: CGFloat
    @ViewBuilder let center: Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(ConsoleView.accentSoft.opacity(0.5), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(progress, 0), 1)))
                .stroke(ConsoleView.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center
        }
        .frame(width: size, height: size)
    }
}

/// 横向进度条
private struct ProgressBar: View {
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(ConsoleView.accentSoft.opacity(0.5))
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(min(max(progress, 0), 1)))
            }
        }
    }
}

/// 状态标签 chip
private struct StatusChip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}

/// 迷你柱状图
private struct MiniBarChart: View {
    let values: [Double] // 0...1

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(values.indices, id: \.self) { i in
                    let h = max(2, geo.size.height * CGFloat(values[i]))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(ConsoleView.accent.opacity(0.7))
                        .frame(height: h)
                }
            }
        }
    }
}

#Preview {
    ConsoleView()
}
