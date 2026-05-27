import SwiftUI

/// Caelum's Console — 右滑 page 2 控制台页面
///
/// 设计稿: docs/console-design-reference.html
struct ConsoleView: View {
    @State private var medicationTaken: Bool = true
    @State private var medicationToggled: Bool = false
    @State private var tappedCardId: String? = nil

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                headerView
                cardStack
                    .padding(.horizontal, 20)
                Color.clear.frame(height: 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Self.pageBg.ignoresSafeArea())
        .sensoryFeedback(.impact(weight: .light), trigger: tappedCardId)
        .sensoryFeedback(.success, trigger: medicationToggled)
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CAELUM'S CONSOLE")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Self.textMuted)
                .tracking(2)

            Text(greetingString)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Self.textPrimary)
                .padding(.top, 6)

            Text(dateString)
                .font(.system(size: 13))
                .foregroundColor(Self.textMuted)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 56)
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    private var greetingString: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 0..<5:  return "夜深了，天奕"
        case 5..<12: return "早上好，天奕"
        case 12..<18: return "下午好，天奕"
        default:     return "晚上好，天奕"
        }
    }

    private var dateString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d, yyyy"
        return "\(f.string(from: Date())) · Lost in Blossom"
    }

    // MARK: - Cards

    private var cardStack: some View {
        VStack(spacing: 10) {
            // Row 1: 饮水 + 进食 (two columns)
            HStack(spacing: 10) {
                waterCard
                foodCard
            }

            // Row 2: 药物 + 睡眠 (two columns)
            HStack(spacing: 10) {
                medicationCard
                sleepCard
            }

            menstrualCard
            stepsCard
            screenTimeCard
            twitterCard
        }
    }

    // MARK: - 1. 饮水

    private var waterCard: some View {
        ConsoleCard(id: "water", tappedCardId: $tappedCardId) {
            ConsoleTag(icon: "drop", label: "饮水")
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("2")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Self.textPrimary)
                Text("/ 6 杯")
                    .font(.system(size: 13))
                    .foregroundColor(Self.textUnit)
            }
            Text("还差 4 杯")
                .font(.system(size: 12))
                .foregroundColor(Self.textMuted)
                .padding(.top, 3)
        }
    }

    // MARK: - 2. 进食

    private var foodCard: some View {
        ConsoleCard(id: "food", tappedCardId: $tappedCardId) {
            ConsoleTag(icon: "fork.knife", label: "进食")
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("1")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Self.textPrimary)
                Text("/ 3 餐")
                    .font(.system(size: 13))
                    .foregroundColor(Self.textUnit)
            }
            Text("泡面 · 03:30")
                .font(.system(size: 12))
                .foregroundColor(Self.textMuted)
                .padding(.top, 3)
        }
    }

    // MARK: - 3. 药物

    private var medicationCard: some View {
        ConsoleCard(id: "medication", tappedCardId: $tappedCardId) {
            ConsoleTag(icon: "pills", label: "药物")
            ConsolePill(text: medicationTaken ? "已服用" : "未服用",
                        style: medicationTaken ? .ok : .warn)
                .padding(.top, 4)
                .onTapGesture {
                    medicationTaken.toggle()
                    medicationToggled.toggle()
                }
            Text("右佐匹克隆 · 昨晚")
                .font(.system(size: 12))
                .foregroundColor(Self.textMuted)
                .padding(.top, 6)
        }
    }

    // MARK: - 4. 睡眠

    private var sleepCard: some View {
        ConsoleCard(id: "sleep", tappedCardId: $tappedCardId) {
            ConsoleTag(icon: "moon", label: "睡眠")
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("5.2")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Self.textPrimary)
                Text("小时")
                    .font(.system(size: 13))
                    .foregroundColor(Self.textUnit)
            }
            Text("04:15 – 09:30")
                .font(.system(size: 12))
                .foregroundColor(Self.textMuted)
                .padding(.top, 3)
        }
    }

    // MARK: - 5. 月经周期

    private var menstrualCard: some View {
        ConsoleCard(id: "menstrual", tappedCardId: $tappedCardId) {
            ConsoleTag(icon: "calendar", label: "月经周期")
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("第 21 天")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Self.textPrimary)
                    Text("预计 6月14日 来潮 · 还有 18 天")
                        .font(.system(size: 12))
                        .foregroundColor(Self.textMuted)
                }
                Spacer()
                // Mini bar chart — cycle phase bars (height as fraction of 28pt)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(menstrualBars) { bar in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(bar.color)
                            .frame(width: 3, height: 28 * bar.height)
                    }
                }
                .frame(height: 28)
            }
        }
    }

    private struct BarSpec: Identifiable {
        let id = UUID()
        let height: CGFloat
        let color: Color
    }

    private var menstrualBars: [BarSpec] {[
        BarSpec(height: 0.40, color: Color(red: 212/255, green: 200/255, blue: 184/255)), // #D4C8B8
        BarSpec(height: 0.25, color: Color(red: 212/255, green: 200/255, blue: 184/255)),
        BarSpec(height: 0.15, color: Color(red: 232/255, green: 224/255, blue: 212/255)), // #E8E0D4
        BarSpec(height: 0.10, color: Color(red: 232/255, green: 224/255, blue: 212/255)),
        BarSpec(height: 0.10, color: Color(red: 232/255, green: 224/255, blue: 212/255)),
        BarSpec(height: 0.10, color: Color(red: 232/255, green: 224/255, blue: 212/255)),
        BarSpec(height: 0.10, color: Color(red: 232/255, green: 224/255, blue: 212/255)),
        BarSpec(height: 0.60, color: Color(red: 188/255, green: 143/255, blue: 123/255).opacity(0.4)), // #BC8F7B predicted
    ]}

    // MARK: - 6. 步数

    private var stepsCard: some View {
        ConsoleCard(id: "steps", tappedCardId: $tappedCardId) {
            ConsoleTag(icon: "figure.walk", label: "步数")
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("847")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Self.textPrimary)
                    Text("HealthKit · 今日")
                        .font(.system(size: 12))
                        .foregroundColor(Self.textMuted)
                }
                Spacer()
                // 7-day bar chart (6px wide bars, 32pt height)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(stepsBars) { bar in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(bar.color)
                            .frame(width: 6, height: 32 * bar.height)
                    }
                }
                .frame(height: 32)
            }
        }
    }

    private var stepsBars: [BarSpec] {
        let pastColor = Color(red: 212/255, green: 200/255, blue: 184/255) // #D4C8B8
        let todayColor = Color(red: 168/255, green: 158/255, blue: 142/255) // #A89E8E
        return [
            BarSpec(height: 0.60, color: pastColor),
            BarSpec(height: 0.35, color: pastColor),
            BarSpec(height: 0.80, color: pastColor),
            BarSpec(height: 0.45, color: pastColor),
            BarSpec(height: 0.20, color: pastColor),
            BarSpec(height: 0.55, color: pastColor),
            BarSpec(height: 0.12, color: todayColor),
        ]
    }

    // MARK: - 7. 屏幕使用时间

    private var screenTimeCard: some View {
        ConsoleCard(id: "screen", tappedCardId: $tappedCardId) {
            ConsoleTag(icon: "iphone", label: "屏幕使用时间")
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("6.5")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(Self.textPrimary)
                        Text("小时")
                            .font(.system(size: 13))
                            .foregroundColor(Self.textUnit)
                    }
                    Text("上限 10h · 社交 APP 2.1h / 3h")
                        .font(.system(size: 12))
                        .foregroundColor(Self.textMuted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    ConsolePill(text: "正常", style: .ok)
                    // Progress bar 65% of 10h limit
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(red: 232/255, green: 224/255, blue: 212/255))
                            .frame(width: 80, height: 5)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 139/255, green: 115/255, blue:  85/255),
                                        Color(red: 166/255, green: 144/255, blue: 111/255)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 80 * 0.65, height: 5)
                    }
                    .frame(width: 80, height: 5)
                }
            }
        }
    }

    // MARK: - 8. 推特动态

    private var twitterCard: some View {
        ConsoleCard(id: "twitter", tappedCardId: $tappedCardId) {
            ConsoleTag(icon: "at", label: "推特动态")
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("今日 3 条")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Self.textPrimary)
                    Text("最近：分享了 Lost in Blossom 的界面截图")
                        .font(.system(size: 12))
                        .foregroundColor(Self.textMuted)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(Color(red: 196/255, green: 184/255, blue: 168/255)) // #C4B8A8
            }
        }
    }
}

// MARK: - Design tokens

extension ConsoleView {
    static let pageBg      = Color(red: 248/255, green: 245/255, blue: 240/255) // #F8F5F0
    static let textPrimary = Color(red:  58/255, green:  51/255, blue:  43/255) // #3A332B
    static let textUnit    = Color(red: 155/255, green: 142/255, blue: 126/255) // #9B8E7E
    static let textLabel   = Color(red: 168/255, green: 158/255, blue: 142/255) // #A89E8E
    static let textMuted   = Color(red: 181/255, green: 170/255, blue: 154/255) // #B5AA9A
}

// MARK: - Reusable card container

private struct ConsoleCard<Content: View>: View {
    let id: String
    @Binding var tappedCardId: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture {
            tappedCardId = UUID().uuidString
        }
    }
}

// MARK: - Tag row (icon + label, 粟粟风格)

private struct ConsoleTag: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(Color(red: 168/255, green: 158/255, blue: 142/255))
                .frame(width: 16, height: 16)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(red: 168/255, green: 158/255, blue: 142/255))
                .tracking(0.3)
        }
        .padding(.bottom, 8)
    }
}

// MARK: - Status pill

private enum PillStyle { case ok, warn, off }

private struct ConsolePill: View {
    let text: String
    let style: PillStyle

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(fgColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(bgColor)
            .clipShape(Capsule())
    }

    private var bgColor: Color {
        switch style {
        case .ok:   return Color(red: 232/255, green: 240/255, blue: 228/255) // #E8F0E4
        case .warn: return Color(red: 245/255, green: 235/255, blue: 223/255) // #F5EBDF
        case .off:  return Color(red: 240/255, green: 234/255, blue: 234/255) // #F0EAEA
        }
    }

    private var fgColor: Color {
        switch style {
        case .ok:   return Color(red: 107/255, green: 140/255, blue:  90/255) // #6B8C5A
        case .warn: return Color(red: 166/255, green: 139/255, blue:  91/255) // #A68B5B
        case .off:  return Color(red: 155/255, green: 142/255, blue: 142/255) // #9B8E8E
        }
    }
}

#Preview {
    ConsoleView()
}
