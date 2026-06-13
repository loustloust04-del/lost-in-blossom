import SwiftUI
import SwiftData

/// Caelum's Console — 右滑 page 2 控制台页面
///
/// 数据来源：
///   - DailyContext（SwiftData） — 手动记录（由 Caelum tool call 写入）
///   - HealthKitService          — 步数 / 睡眠 / 月经（HealthKit）
///   - 无数据 → 显示 "—" 或 "未报告"
struct ConsoleView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DailyContext.date, order: .reverse) private var allContexts: [DailyContext]

    @State private var healthKit = HealthKitService()
    @State private var medicationToggled: Bool = false
    @State private var tappedCardId: String? = nil
    @State private var memoTabForYou: Bool = true
    @State private var showMemoBoard: Bool = false

    // 今天的 DailyContext（如果没有则为 nil）
    private var todayCtx: DailyContext? {
        let today = Calendar.current.startOfDay(for: Date())
        return allContexts.first { Calendar.current.isDate($0.date, inSameDayAs: today) }
    }

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
        .task {
            ensureTodayContext()
            await healthKit.requestAuthorization()
            if healthKit.authState == .authorized, let ctx = todayCtx {
                await healthKit.populate(context: ctx)
            }
        }
    }

    // MARK: - Ensure today context

    private func ensureTodayContext() {
        DailyContextStore.ensureToday(context: modelContext)
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
        case 0..<5:   return "夜深了，天奕"
        case 5..<12:  return "早上好，天奕"
        case 12..<18: return "下午好，天奕"
        default:      return "晚上好，天奕"
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
            HStack(spacing: 10) { waterCard; foodCard }
            HStack(spacing: 10) { medicationCard; sleepCard }
            menstrualCard
            stepsCard
            screenTimeCard
            memoCard
        }
    }

    // MARK: - 1. 饮水

    private var waterCard: some View {
        ConsoleCard(id: "water", tappedCardId: $tappedCardId) {
            ConsoleTag(icon: "drop", label: "饮水")
            if let ctx = todayCtx {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(ctx.waterCount)")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Self.textPrimary)
                    Text("/ 6 杯")
                        .font(.system(size: 13))
                        .foregroundColor(Self.textUnit)
                }
                Text(ctx.waterCount >= 6 ? "今日达标 🎉" : "还差 \(6 - ctx.waterCount) 杯")
                    .font(.system(size: 12))
                    .foregroundColor(Self.textMuted)
                    .padding(.top, 3)
            } else {
                noDataView
            }
        }
    }

    // MARK: - 2. 进食

    private var foodCard: some View {
        ConsoleCard(id: "food", tappedCardId: $tappedCardId) {
            ConsoleTag(icon: "fork.knife", label: "进食")
            if let ctx = todayCtx {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(ctx.meals.count)")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Self.textPrimary)
                    Text("/ 3 餐")
                        .font(.system(size: 13))
                        .foregroundColor(Self.textUnit)
                }
                if let meal = ctx.latestMeal {
                    Text("\(meal.description) · \(timeString(meal.time))")
                        .font(.system(size: 12))
                        .foregroundColor(Self.textMuted)
                        .padding(.top, 3)
                        .lineLimit(1)
                } else {
                    Text("未记录")
                        .font(.system(size: 12))
                        .foregroundColor(Self.textMuted)
                        .padding(.top, 3)
                }
            } else {
                noDataView
            }
        }
    }

    // MARK: - 3. 药物

    private var medicationCard: some View {
        ConsoleCard(id: "medication", tappedCardId: $tappedCardId) {
            ConsoleTag(icon: "pills", label: "药物")
            if let ctx = todayCtx {
                let pillStyle: PillStyle = ctx.medicationStatus == .taken  ? .ok  :
                                          ctx.medicationStatus == .skipped ? .off : .warn
                let pillText =            ctx.medicationStatus == .taken  ? "已服用" :
                                          ctx.medicationStatus == .skipped ? "已跳过" : "未报告"
                ConsolePill(text: pillText, style: pillStyle)
                    .padding(.top, 4)
                Text("\(ctx.medicationName) · 昨晚")
                    .font(.system(size: 12))
                    .foregroundColor(Self.textMuted)
                    .padding(.top, 6)
                    .lineLimit(1)
            } else {
                noDataView
            }
        }
    }

    // MARK: - 4. 睡眠

    private var sleepCard: some View {
        ConsoleCard(id: "sleep", tappedCardId: $tappedCardId) {
            ConsoleTag(icon: "moon", label: "睡眠")
            if let ctx = todayCtx, let dur = ctx.sleepDuration {
                let h = Int(dur)
                let m = Int((dur - Double(h)) * 60)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(m > 0 ? "\(h)h \(m)m" : "\(h)h")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Self.textPrimary)
                }
                if let start = ctx.sleepStart, let end = ctx.sleepEnd {
                    Text("\(timeString(start)) – \(timeString(end))")
                        .font(.system(size: 12))
                        .foregroundColor(Self.textMuted)
                        .padding(.top, 3)
                }
            } else {
                noDataView
            }
        }
    }

    // MARK: - 5. 月经周期

    private var menstrualCard: some View {
        ConsoleCard(id: "menstrual", tappedCardId: $tappedCardId) {
            ConsoleTag(icon: "calendar", label: "月经周期")
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    if let ctx = todayCtx, let day = ctx.menstrualDay {
                        Text("第 \(day) 天")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(Self.textPrimary)
                        if let next = ctx.nextPeriodDate {
                            let daysLeft = max(0, Calendar.current.dateComponents(
                                [.day], from: Date(), to: next).day ?? 0)
                            Text("预计 \(shortDateString(next)) 来潮 · 还有 \(daysLeft) 天")
                                .font(.system(size: 12))
                                .foregroundColor(Self.textMuted)
                        } else {
                            Text("未设置预计来潮日")
                                .font(.system(size: 12))
                                .foregroundColor(Self.textMuted)
                        }
                    } else {
                        Text("—")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(Self.textMuted)
                    }
                }
                Spacer()
                // 静态示意 bar chart（周期相位可视化）
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(menstrualBarSpecs) { bar in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(bar.color)
                            .frame(width: 3, height: 28 * bar.height)
                    }
                }
                .frame(height: 28)
            }
        }
    }

    // MARK: - 6. 步数

    private var stepsCard: some View {
        ConsoleCard(id: "steps", tappedCardId: $tappedCardId) {
            ConsoleTag(icon: "figure.walk", label: "步数")
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    if let steps = todayCtx?.steps {
                        Text(stepsFormatted(steps))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(Self.textPrimary)
                        Text(healthKit.authState == .unavailable
                             ? "手动记录 · 今日"
                             : "HealthKit · 今日")
                            .font(.system(size: 12))
                            .foregroundColor(Self.textMuted)
                    } else if healthKit.authState == .denied {
                        Text("未授权")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(Self.textMuted)
                        Text("前往设置 › 健康 授权")
                            .font(.system(size: 11))
                            .foregroundColor(Self.textMuted)
                    } else {
                        noDataView
                    }
                }
                Spacer()
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(stepsBarSpecs) { bar in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(bar.color)
                            .frame(width: 6, height: 32 * bar.height)
                    }
                }
                .frame(height: 32)
            }
        }
    }

    // MARK: - 7. 屏幕使用时间

    private var screenTimeCard: some View {
        ConsoleCard(id: "screen", tappedCardId: $tappedCardId) {
            ConsoleTag(icon: "iphone", label: "屏幕使用时间")
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    if let st = todayCtx?.screenTime {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(String(format: "%.1f", st))
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(Self.textPrimary)
                            Text("小时")
                                .font(.system(size: 13))
                                .foregroundColor(Self.textUnit)
                        }
                        let social = todayCtx?.socialScreenTime.map {
                            String(format: "%.1fh", $0)
                        } ?? "—"
                        Text("上限 10h · 社交 APP \(social) / 3h")
                            .font(.system(size: 12))
                            .foregroundColor(Self.textMuted)
                    } else {
                        Text("—")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(Self.textMuted)
                        Text("Screen Time API 暂不可用")
                            .font(.system(size: 11))
                            .foregroundColor(Self.textMuted)
                    }
                }
                Spacer()
                if let st = todayCtx?.screenTime {
                    let ratio = min(1.0, st / 10.0)
                    let style: PillStyle = st < 6 ? .ok : st < 9 ? .warn : .off
                    VStack(alignment: .trailing, spacing: 4) {
                        ConsolePill(text: st < 6 ? "正常" : st < 9 ? "偏多" : "超标",
                                    style: style)
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(red: 232/255, green: 224/255, blue: 212/255))
                                .frame(width: 80, height: 5)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(LinearGradient(
                                    colors: [
                                        Color(red: 139/255, green: 115/255, blue:  85/255),
                                        Color(red: 166/255, green: 144/255, blue: 111/255)
                                    ],
                                    startPoint: .leading, endPoint: .trailing
                                ))
                                .frame(width: 80 * ratio, height: 5)
                        }
                        .frame(width: 80, height: 5)
                    }
                }
            }
        }
    }

    // MARK: - 8. 碎碎念

    private var memoCard: some View {
        ConsoleCard(id: "memo", tappedCardId: $tappedCardId, onTap: {
            if memoTabForYou { showMemoBoard = true }
        }) {
            HStack(spacing: 14) {
                Button { memoTabForYou = true } label: {
                    Text("给你的")
                        .font(.system(size: 12, weight: memoTabForYou ? .semibold : .regular))
                        .foregroundColor(memoTabForYou ? Self.textPrimary : Self.textMuted)
                        .underline(memoTabForYou)
                }
                .buttonStyle(.plain)
                Button { memoTabForYou = false } label: {
                    Text("给世界的")
                        .font(.system(size: 12, weight: !memoTabForYou ? .semibold : .regular))
                        .foregroundColor(!memoTabForYou ? Self.textPrimary : Self.textMuted)
                        .underline(!memoTabForYou)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.bottom, 10)

            if memoTabForYou {
                VStack(alignment: .leading, spacing: 6) {
                    Text("这里会显示最新的留言～")
                        .font(.system(size: 14))
                        .foregroundColor(Self.textPrimary)
                        .lineLimit(2)
                    HStack {
                        Text("刚刚")
                            .font(.system(size: 11))
                            .foregroundColor(Self.textMuted)
                        Spacer()
                        Text("查看全部 →")
                            .font(.system(size: 11))
                            .foregroundColor(Self.textMuted)
                    }
                }
            } else {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        if let count = todayCtx?.tweetCount {
                            Text("今日 \(count) 条")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(Self.textPrimary)
                            if let summary = todayCtx?.latestTweetSummary {
                                Text("最近：\(summary)")
                                    .font(.system(size: 12))
                                    .foregroundColor(Self.textMuted)
                                    .lineLimit(2)
                            }
                        } else {
                            Text("—")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(Self.textMuted)
                            Text("Phase 2 接入 Twitter MCP")
                                .font(.system(size: 11))
                                .foregroundColor(Self.textMuted)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Color(red: 196/255, green: 184/255, blue: 168/255))
                }
            }
        }
        .sheet(isPresented: $showMemoBoard) {
            MemoBoardPlaceholder()
        }
    }

    // MARK: - Helpers

    private var noDataView: some View {
        Text("—")
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(Self.textMuted)
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private func shortDateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f.string(from: date)
    }

    private func stepsFormatted(_ n: Int) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        return fmt.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    // MARK: - Static bar chart specs

    private struct BarSpec: Identifiable {
        let id = UUID()
        let height: CGFloat
        let color: Color
    }

    private var menstrualBarSpecs: [BarSpec] {[
        BarSpec(height: 0.40, color: Color(red: 212/255, green: 200/255, blue: 184/255)),
        BarSpec(height: 0.25, color: Color(red: 212/255, green: 200/255, blue: 184/255)),
        BarSpec(height: 0.15, color: Color(red: 232/255, green: 224/255, blue: 212/255)),
        BarSpec(height: 0.10, color: Color(red: 232/255, green: 224/255, blue: 212/255)),
        BarSpec(height: 0.10, color: Color(red: 232/255, green: 224/255, blue: 212/255)),
        BarSpec(height: 0.10, color: Color(red: 232/255, green: 224/255, blue: 212/255)),
        BarSpec(height: 0.10, color: Color(red: 232/255, green: 224/255, blue: 212/255)),
        BarSpec(height: 0.60, color: Color(red: 188/255, green: 143/255, blue: 123/255).opacity(0.4)),
    ]}

    private var stepsBarSpecs: [BarSpec] {
        let past  = Color(red: 212/255, green: 200/255, blue: 184/255)
        let today = Color(red: 168/255, green: 158/255, blue: 142/255)
        return [
            BarSpec(height: 0.60, color: past),
            BarSpec(height: 0.35, color: past),
            BarSpec(height: 0.80, color: past),
            BarSpec(height: 0.45, color: past),
            BarSpec(height: 0.20, color: past),
            BarSpec(height: 0.55, color: past),
            BarSpec(height: 0.12, color: today),
        ]
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

// MARK: - ConsoleCard

private struct ConsoleCard<Content: View>: View {
    let id: String
    @Binding var tappedCardId: String?
    var onTap: (() -> Void)? = nil
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
            onTap?()
        }
    }
}

private struct MemoBoardPlaceholder: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "envelope.open")
                    .font(.system(size: 48))
                    .foregroundColor(Color(red: 168/255, green: 158/255, blue: 142/255))
                Text("留言板")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Color(red: 58/255, green: 51/255, blue: 43/255))
                Text("Coming soon · 后续接入粟粟的贴纸系统")
                    .font(.system(size: 14))
                    .foregroundColor(Color(red: 181/255, green: 170/255, blue: 154/255))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 248/255, green: 245/255, blue: 240/255))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

// MARK: - ConsoleTag

private struct ConsoleTag: View {
    let icon: String
    let label: String
    private let c = Color(red: 168/255, green: 158/255, blue: 142/255)

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(c)
                .frame(width: 16, height: 16)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(c)
                .tracking(0.3)
        }
        .padding(.bottom, 8)
    }
}

// MARK: - ConsolePill

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
        case .ok:   return Color(red: 232/255, green: 240/255, blue: 228/255)
        case .warn: return Color(red: 245/255, green: 235/255, blue: 223/255)
        case .off:  return Color(red: 240/255, green: 234/255, blue: 234/255)
        }
    }

    private var fgColor: Color {
        switch style {
        case .ok:   return Color(red: 107/255, green: 140/255, blue:  90/255)
        case .warn: return Color(red: 166/255, green: 139/255, blue:  91/255)
        case .off:  return Color(red: 155/255, green: 142/255, blue: 142/255)
        }
    }
}

#Preview {
    ConsoleView()
        .modelContainer(for: DailyContext.self, inMemory: true)
}
