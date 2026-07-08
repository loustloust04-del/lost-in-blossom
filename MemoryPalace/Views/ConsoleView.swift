import SwiftUI
import SwiftData

/// Caelum's Console — 右滑 page 2 控制台页面（v6：杂志式分区 + 衬线 + 绿调）
///
/// 分区：日常（饮水/进食）→ 待办 → 屏幕 → 身体（步数/睡眠/药物）→ 经期 → 留言
/// 数据来源：
///   - DailyContext（SwiftData）— Caelum tool call 写入
///   - HealthKitService — 步数 / 睡眠 / 月经
///   - VitalsClient / ScreenTimeClient — 网关数据
///   - TodoManager — 待办（G1 本地；G2 上网关）
struct ConsoleView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DailyContext.date, order: .reverse) private var allContexts: [DailyContext]

    @State private var healthKit = HealthKitService()
    @State private var vitalsData: VitalsResponse? = nil
    @State private var memoTabForYou: Bool = true
    @State private var showMemoBoard: Bool = false
    @State private var showAddTodo: Bool = false
    @State private var newTodoText: String = ""
    @State private var todo = TodoManager.shared

    private var todayCtx: DailyContext? {
        let today = Calendar.current.startOfDay(for: Date())
        return allContexts.first { Calendar.current.isDate($0.date, inSameDayAs: today) }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                headerView
                VStack(alignment: .leading, spacing: 0) {
                    dailySection
                    todoSection
                    screenSection
                    bodySection
                    cycleSection
                    messagesSection
                }
                .padding(.horizontal, 22)
                Color.clear.frame(height: 48)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Self.pageBg.ignoresSafeArea())
        .task {
            loadVitals()
            ensureTodayContext()
            await todo.refresh()
            await healthKit.requestAuthorization()
            if healthKit.authState == .authorized, let ctx = todayCtx {
                await healthKit.populate(context: ctx)
            }
            if let st = await ScreenTimeClient.fetch(), let ctx = todayCtx {
                ctx.screenTime = st.total_minutes / 60.0
                ctx.socialScreenTime = st.social_minutes / 60.0
                try? modelContext.save()
            }
        }
        .alert("添加待办", isPresented: $showAddTodo) {
            TextField("要做的事…", text: $newTodoText)
            Button("取消", role: .cancel) { newTodoText = "" }
            Button("添加") {
                todo.add(newTodoText)
                newTodoText = ""
            }
        }
    }

    private func ensureTodayContext() { DailyContextStore.ensureToday(context: modelContext) }
    private func loadVitals() {
        Task { let v = await VitalsClient.fetch(); await MainActor.run { vitalsData = v } }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CAELUM'S CONSOLE")
                .font(.cormorant(12))
                .foregroundColor(Self.greenDeep)
                .tracking(5)
            Text(greetingString)
                .font(.songti(28))
                .foregroundColor(Self.textPrimary)
                .tracking(3)
                .padding(.top, 10)
            Text(dateString)
                .font(.cormorant(14))
                .foregroundColor(Self.textMuted)
                .tracking(0.5)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 56)
        .padding(.horizontal, 24)
        .padding(.bottom, 4)
    }

    private var greetingString: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 0..<5:   return "夜深了，天奕"
        case 5..<12:  return "早上好，天奕"
        case 12..<18: return "下午好，天奕"
        default:      return "晚上好，天奕"
        }
    }

    private var dateString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMMM d, yyyy"
        return "\(f.string(from: Date())) · Lost in Blossom"
    }

    // MARK: - Section header

    private func sectionHeader(_ cn: String, _ en: String, note: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(cn)
                .font(.songti(15))
                .tracking(6)
                .foregroundColor(Self.textPrimary)
            Text(en.uppercased())
                .font(.cormorant(12))
                .tracking(2)
                .foregroundColor(Self.textFaint)
            if let note {
                Spacer()
                Text(note)
                    .font(.system(size: 11))
                    .foregroundColor(Self.textFaint)
                    .tracking(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 30)
        .padding(.bottom, 14)
        .padding(.horizontal, 2)
    }

    // MARK: - 日常

    private var dailySection: some View {
        Group {
            sectionHeader("日 常", "Daily")
            HStack(spacing: 13) {
                bigStat(label: "饮水",
                        value: todayCtx?.waterCount ?? 0, goal: 6,
                        note: (todayCtx?.waterCount ?? 0) >= 6 ? "今日达标 🎉" : "还差 \(max(0, 6 - (todayCtx?.waterCount ?? 0))) 杯")
                bigStat(label: "进食",
                        value: todayCtx?.meals.count ?? vitalsData?.food.count ?? 0,
                        goal: vitalsData?.food.goal ?? 3,
                        note: vitalsData?.food.meals.last ?? todayCtx?.meals.last?.description ?? "未记录")
            }
        }
    }

    private func bigStat(label: String, value: Int, goal: Int, note: String) -> some View {
        card {
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 13)).foregroundColor(Self.textSub).tracking(1)
                    .padding(.bottom, 10)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(value)")
                        .font(.cormorant(44))
                        .foregroundColor(Self.textPrimary)
                    Text("/\(goal)")
                        .font(.cormorant(15))
                        .foregroundColor(Self.textFaint)
                }
                ProgressBar(ratio: goal > 0 ? min(1, Double(value) / Double(goal)) : 0)
                    .padding(.top, 12)
                Text(note)
                    .font(.system(size: 12)).foregroundColor(Self.greenDeep)
                    .lineLimit(1)
                    .padding(.top, 10)
            }
        }
    }

    // MARK: - 待办

    private var todoSection: some View {
        Group {
            sectionHeader("待 办", "To Do", note: "Caelum 也能记")
            card(padding: false) {
                VStack(spacing: 0) {
                    let items = todo.sorted
                    if items.isEmpty {
                        HStack {
                            Text("今天还没有待办")
                                .font(.system(size: 14)).foregroundColor(Self.textFaint)
                            Spacer()
                        }
                        .padding(.horizontal, 20).padding(.vertical, 16)
                    } else {
                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                            todoRow(item, isLast: false)
                            if idx < items.count - 1 {
                                Rectangle().fill(Self.line).frame(height: 0.5).padding(.leading, 20)
                            }
                        }
                        Rectangle().fill(Self.line).frame(height: 0.5).padding(.leading, 20)
                    }
                    Button { showAddTodo = true } label: {
                        HStack {
                            Text("＋ 添加待办")
                                .font(.system(size: 13)).foregroundColor(Self.greenDeep).tracking(1)
                            Spacer()
                        }
                        .padding(.horizontal, 20).padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func todoRow(_ item: TodoItem, isLast: Bool) -> some View {
        HStack(spacing: 13) {
            Button { withAnimation(.easeInOut(duration: 0.15)) { todo.toggle(item.id) } } label: {
                ZStack {
                    Circle()
                        .strokeBorder(item.done ? Self.green : Color(red: 214/255, green: 207/255, blue: 195/255), lineWidth: 1.5)
                        .background(Circle().fill(item.done ? Self.green : Color.clear))
                        .frame(width: 19, height: 19)
                    if item.done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            Text(item.text)
                .font(.system(size: 14.5))
                .foregroundColor(item.done ? Self.textFaint : Color(red: 61/255, green: 56/255, blue: 51/255))
                .strikethrough(item.done, color: Self.textFaint)
            Spacer()
            if let src = item.source {
                Text(src).font(.system(size: 10)).foregroundColor(Self.textFaint)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 13)
        .contentShape(Rectangle())
        .contextMenu {
            Button(role: .destructive) { todo.delete(item.id) } label: { Label("删除", systemImage: "trash") }
            if item.done {
                Button { todo.toggle(item.id) } label: { Label("标为未完成", systemImage: "arrow.uturn.backward") }
            }
        }
    }

    // MARK: - 屏幕

    private var screenSection: some View {
        Group {
            sectionHeader("屏 幕", "Screen")
            card {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("今日使用").font(.system(size: 13)).foregroundColor(Self.textSub).tracking(1)
                        if let st = todayCtx?.screenTime {
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text(String(format: "%.1f", st))
                                    .font(.cormorant(34))
                                    .foregroundColor(Self.textPrimary)
                                Text("h").font(.cormorant(13)).foregroundColor(Self.textFaint)
                            }
                        } else {
                            Text("—")
                                .font(.cormorant(34))
                                .foregroundColor(Self.textMuted)
                        }
                    }
                    Spacer()
                    if let st = todayCtx?.screenTime {
                        let social = todayCtx?.socialScreenTime.map { String(format: "%.1fh", $0) } ?? "—"
                        Text("社交 \(social) / 3h")
                            .font(.system(size: 12)).foregroundColor(Self.textMuted)
                    } else {
                        Text("Screen Time API\n暂不可用")
                            .font(.system(size: 11)).foregroundColor(Self.textFaint)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
    }

    // MARK: - 身体

    private var bodySection: some View {
        Group {
            sectionHeader("身 体", "Body")
            HStack(spacing: 13) {
                iconStat(icon: "figure.walk", label: "步数",
                         value: todayCtx?.steps.map(stepsFormatted) ?? "—",
                         sub: todayCtx?.steps != nil ? "步" : "未记录")
                iconStat(icon: "moon", label: "睡眠",
                         value: sleepValue, sub: sleepSub)
                iconStat(icon: "pills", label: "药物",
                         value: medsTaken ? "已服" : "未报告",
                         sub: medsName, valueColor: medsTaken ? Self.green : Self.gold, small: true)
            }
        }
    }

    private var sleepValue: String {
        guard let dur = todayCtx?.sleepDuration else { return "—" }
        let h = Int(dur), m = Int((dur - Double(h)) * 60)
        return m > 0 ? "\(h)h\(m)" : "\(h)h"
    }
    private var sleepSub: String {
        if let s = todayCtx?.sleepStart, let e = todayCtx?.sleepEnd {
            return "\(timeString(s))–\(timeString(e))"
        }
        return todayCtx?.sleepDuration != nil ? "" : "未记录"
    }
    private var medsTaken: Bool { todayCtx?.medicationStatus == .taken || vitalsData?.meds.taken == true }
    private var medsName: String { vitalsData?.meds.name ?? todayCtx?.medicationName ?? "右佐匹克隆" }

    private func iconStat(icon: String, label: String, value: String, sub: String,
                          valueColor: Color? = nil, small: Bool = false) -> some View {
        card {
            VStack(spacing: 0) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .light))
                    .foregroundColor(Self.green.opacity(0.85))
                    .frame(height: 24)
                    .padding(.bottom, 8)
                Text(label).font(.system(size: 12)).foregroundColor(Self.textSub).tracking(1)
                    .padding(.bottom, 8)
                Text(value)
                    .font(.cormorant(small ? 18 : 24))
                    .foregroundColor(valueColor ?? Self.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if !sub.isEmpty {
                    Text(sub).font(.songti(11)).foregroundColor(Self.textMuted)
                        .padding(.top, 5).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - 经期（极简排版）

    private var cycleSection: some View {
        Group {
            sectionHeader("经 期", "Cycle")
            card {
                if let day = todayCtx?.menstrualDay {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .bottom) {
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text("\(day)")
                                    .font(.cormorant(54))
                                    .foregroundColor(Self.textPrimary)
                                Text("天").font(.songti(15)).foregroundColor(Self.textFaint)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 5) {
                                Text(menstrualPhase(day))
                                    .font(.songti(20))
                                    .foregroundColor(Self.greenDeep).tracking(2)
                                if let next = todayCtx?.nextPeriodDate {
                                    let d = max(0, Calendar.current.dateComponents([.day], from: Date(), to: next).day ?? 0)
                                    Text("预计 \(d) 天后来潮").font(.system(size: 12)).foregroundColor(Self.textSub)
                                }
                            }
                        }
                        Divider().background(Self.line).padding(.top, 20).padding(.bottom, 16)
                        HStack(spacing: 28) {
                            cycleStat("29", "上次周期")
                            cycleStat("5", "经期时长")
                            if let next = todayCtx?.nextPeriodDate {
                                cycleStat(shortMD(next), "预计来潮")
                            }
                        }
                    }
                } else {
                    HStack {
                        Text("未记录经期").font(.system(size: 14)).foregroundColor(Self.textMuted)
                        Spacer()
                    }
                }
            }
        }
    }

    private func cycleStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.cormorant(20)).foregroundColor(Self.textPrimary)
            Text(label).font(.system(size: 11)).foregroundColor(Self.textMuted)
        }
    }

    private func menstrualPhase(_ day: Int) -> String {
        switch day {
        case ...5:   return "经期"
        case 6...13: return "卵泡期"
        case 14...16: return "排卵期"
        default:     return "黄体期"
        }
    }

    // MARK: - 留言

    private var messagesSection: some View {
        Group {
            sectionHeader("留 言", "Messages")
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 26) {
                    tabButton("给你的", active: memoTabForYou) { memoTabForYou = true }
                    tabButton("给世界的", active: !memoTabForYou) { memoTabForYou = false }
                    Spacer()
                }
                Rectangle().fill(Self.line).frame(height: 0.5).padding(.top, -0.5)
                    .padding(.bottom, 14)
                card {
                    if memoTabForYou {
                        let latest = vitalsData?.notes?.last
                        VStack(alignment: .leading, spacing: 10) {
                            Text(latest?.text ?? "这里会显示 Caelum 的最新留言～")
                                .font(.system(size: 14.5))
                                .foregroundColor(latest != nil ? Self.textPrimary : Self.textSub)
                                .lineSpacing(4)
                            HStack {
                                Text("\(noteTime(latest?.ts)) · \(latest?.by ?? "Caelum")")
                                    .font(.cormorant(12)).foregroundColor(Self.textMuted)
                                Spacer()
                                Text("查看全部 →").font(.system(size: 12)).foregroundColor(Self.greenDeep)
                            }
                        }
                    } else {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                if let count = todayCtx?.tweetCount {
                                    Text("今日 \(count) 条").font(.songti(18)).foregroundColor(Self.textPrimary)
                                    if let s = todayCtx?.latestTweetSummary {
                                        Text(s).font(.system(size: 12)).foregroundColor(Self.textMuted).lineLimit(2)
                                    }
                                } else {
                                    Text("—").font(.cormorant(18)).foregroundColor(Self.textMuted)
                                    Text("待接入 Twitter MCP").font(.system(size: 11)).foregroundColor(Self.textFaint)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 13)).foregroundColor(Self.textFaint)
                        }
                    }
                }
            }
            .onTapGesture { if memoTabForYou { showMemoBoard = true } }
        }
        .sheet(isPresented: $showMemoBoard) { MemoBoardPlaceholder() }
    }

    private func tabButton(_ title: String, active: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 14))
                    .tracking(2)
                    .foregroundColor(active ? Self.textPrimary : Self.textMuted)
                Rectangle().fill(active ? Self.green : Color.clear).frame(height: 2)
            }
            .fixedSize()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: date)
    }
    private func shortMD(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "M.d"; return f.string(from: date)
    }
    /// console_write 备注的 ISO 时间戳 → HH:mm；解析失败给"刚刚"
    private func noteTime(_ iso: String?) -> String {
        guard let iso, let d = ISO8601DateFormatter().date(from: iso) else { return "刚刚" }
        return timeString(d)
    }
    private func stepsFormatted(_ n: Int) -> String {
        let fmt = NumberFormatter(); fmt.numberStyle = .decimal
        return fmt.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    // MARK: - Card container

    @ViewBuilder
    private func card<C: View>(padding: Bool = true, @ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(padding ? EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20) : EdgeInsets())
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white)
                    .shadow(color: Color(red: 80/255, green: 70/255, blue: 55/255).opacity(0.05), radius: 3, x: 0, y: 1)
            )
    }
}

// MARK: - Progress bar

private struct ProgressBar: View {
    let ratio: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(red: 238/255, green: 232/255, blue: 221/255))
                Capsule().fill(ConsoleView.green)
                    .frame(width: max(ratio > 0 ? 3 : 0, geo.size.width * ratio))
            }
        }
        .frame(height: 3)
    }
}

// MARK: - Design tokens (v6：暖奶油 + 鼠尾草绿)

extension ConsoleView {
    static let pageBg      = Color(red: 246/255, green: 243/255, blue: 236/255) // #F6F3EC
    static let textPrimary = Color(red:  58/255, green:  51/255, blue:  43/255) // #3A332B
    static let textSub     = Color(red: 124/255, green: 118/255, blue: 107/255) // #7C766B
    static let textUnit    = Color(red: 155/255, green: 142/255, blue: 126/255) // #9B8E7E
    static let textLabel   = Color(red: 168/255, green: 158/255, blue: 142/255) // #A89E8E
    static let textMuted   = Color(red: 167/255, green: 158/255, blue: 143/255) // #A79E8F
    static let textFaint   = Color(red: 188/255, green: 178/255, blue: 162/255) // #BCB2A2
    static let line        = Color(red: 236/255, green: 229/255, blue: 217/255) // #ECE5D9
    static let green       = Color(red: 143/255, green: 174/255, blue: 146/255) // #8FAE92
    static let greenDeep   = Color(red: 110/255, green: 138/255, blue: 114/255) // #6E8A72
    static let rose        = Color(red: 199/255, green: 145/255, blue: 145/255) // #C79191
    static let gold        = Color(red: 205/255, green: 169/255, blue: 104/255) // #CDA968
}

private struct MemoBoardPlaceholder: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "envelope.open")
                    .font(.system(size: 48))
                    .foregroundColor(ConsoleView.textLabel)
                Text("留言板")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(ConsoleView.textPrimary)
                Text("Coming soon · 后续接入留言系统")
                    .font(.system(size: 14))
                    .foregroundColor(ConsoleView.textMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ConsoleView.pageBg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } }
            }
        }
    }
}

#Preview {
    ConsoleView()
        .modelContainer(for: DailyContext.self, inMemory: true)
}

// MARK: - 控制台自定义字体（Cormorant Garamond 数字/英文 + 思源宋体 中文）
private extension Font {
    /// Cormorant Garamond — 数字与拉丁字母（古典衬线，oldstyle 数字，还原 console-v6 原型）
    static func cormorant(_ size: CGFloat) -> Font { .custom("CormorantGaramondLight-SemiBold", size: size) }
    /// 思源宋体 Source Han Serif SC — 中文标题与标签
    static func songti(_ size: CGFloat) -> Font { .custom("SourceHanSerifSC-Regular", size: size) }
}
