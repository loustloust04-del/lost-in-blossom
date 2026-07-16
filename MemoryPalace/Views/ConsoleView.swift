import SwiftUI
import SwiftData
import UIKit

/// Caelum's Console — 右滑 page 2 控制台（v9：粟粟设计语言 · Widget 网格）
///
/// 布局：问候 → 饮水/进食 → 待办 → 步数/睡眠 → 药物/屏幕 → 经期 → 给世界的 → Caelum 留言
/// 设计语言（对齐 SusuPalace design-dna）：暖奶白 5 阶色阶分层、几乎无阴影、无衬线中文 +
///   Cormorant 数字（lining）、薄荷绿点缀、圆角 16-18、零装饰。
/// 数据来源：DailyContext（SwiftData）/ HealthKitService / VitalsClient / ScreenTimeClient / TodoManager。
struct ConsoleView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DailyContext.date, order: .reverse) private var allContexts: [DailyContext]

    @State private var healthKit = HealthKitService()
    @State private var vitalsData: VitalsResponse? = nil
    @State private var showMemoBoard: Bool = false
    @State private var anniversaries: [AnniversaryClient.Item] = []
    @State private var showAnniversaries: Bool = false
    @State private var latestTweets: [TweetsClient.Tweet] = []
    @State private var showTweets: Bool = false
    @State private var showAddTodo: Bool = false
    @State private var newTodoText: String = ""
    @State private var todo = TodoManager.shared
    @State private var periodPred: PeriodClient.Prediction? = nil
    @State private var showPeriod: Bool = false
    @State private var showSleep: Bool = false
    @State private var showCare: Bool = false
    @State private var showLog: Bool = false

    private var todayCtx: DailyContext? {
        let today = Calendar.current.startOfDay(for: Date())
        return allContexts.first { Calendar.current.isDate($0.date, inSameDayAs: today) }
    }

    // MARK: - Body

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 14) {
                header
                grid
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.sidebarBg.ignoresSafeArea())
        .task {
            loadVitals()
            anniversaries = await AnniversaryClient.fetch()
            latestTweets = await TweetsClient.fetch(limit: 40)
            ensureTodayContext()
            await todo.refresh()
            await healthKit.requestAuthorization()
            if healthKit.authState == .authorized, let ctx = todayCtx {
                await healthKit.populate(context: ctx)
            }
            // 经期：把 Apple 健康的来潮日同步到网关，再拉预测
            if healthKit.authState == .authorized {
                let starts = await healthKit.fetchMenstrualStarts()
                if !starts.isEmpty { _ = await PeriodClient.sync(dates: starts) }
            }
            if let snap = await PeriodClient.fetch() { periodPred = snap.prediction }
            if let st = await ScreenTimeClient.fetch(), let ctx = todayCtx {
                ctx.screenTime = st.total_minutes / 60.0
                ctx.socialScreenTime = st.social_minutes / 60.0
                try? modelContext.save()
            }
            // 健康桥：HealthKit/屏幕时间填好后把今日摘要报给网关（30 分钟节流）
            if let ctx = todayCtx { await HealthBridgeClient.report(from: ctx) }
        }
        .alert("添加待办", isPresented: $showAddTodo) {
            TextField("要做的事…", text: $newTodoText)
            Button("取消", role: .cancel) { newTodoText = "" }
            Button("添加") { todo.add(newTodoText); newTodoText = "" }
        }
        .sheet(isPresented: $showMemoBoard) { MemoBoardView() }
        .sheet(isPresented: $showAnniversaries, onDismiss: {
            Task { anniversaries = await AnniversaryClient.fetch() }
        }) { AnniversaryManageSheet() }
        .sheet(isPresented: $showTweets) { TweetsFeedSheet() }
        .sheet(isPresented: $showPeriod, onDismiss: {
            Task { if let snap = await PeriodClient.fetch() { periodPred = snap.prediction } }
        }) { PeriodSheet() }
        .sheet(isPresented: $showSleep) {
            if let ctx = todayCtx { SleepSheet(context: ctx) }
        }
        .sheet(isPresented: $showCare) {
            CareView(contexts: allContexts, vitals: vitalsData, period: periodPred)
        }
        .sheet(isPresented: $showLog) {
            LogView(contexts: allContexts, todayNotes: vitalsData?.notes ?? [])
        }
    }

    private func ensureTodayContext() { DailyContextStore.ensureToday(context: modelContext) }
    private func loadVitals() {
        Task { let v = await VitalsClient.fetch(); await MainActor.run { vitalsData = v } }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CAELUM'S CONSOLE")
                    .font(.system(size: 10.5, weight: .semibold)).tracking(2.5)
                    .foregroundColor(Self.greenDeep)
                Text(greetingString)
                    .font(.system(size: 14.5))
                    .foregroundColor(Self.textSub)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(monthDayStr).font(.system(size: 19, weight: .semibold)).foregroundColor(Self.textPrimary)
                Text("\(weekdayCN(Date())) · \(solarTerm(Date()))")
                    .font(.system(size: 12)).foregroundColor(Self.textMuted)
            }
        }
        .padding(.bottom, 2)
    }

    // MARK: - Grid

    private var grid: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionHeaderTappable("CARE") { showCare = true }
            careTrio
            sectionHeaderTappable("LOG") { showLog = true }
            logTrio
            sectionLabel("DAILY")
            todoWidget
            screenWide
            sectionLabel("WITH YOU")
            anniversaryWidget
            worldWidget
            caelumWidget
        }
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 11, weight: .semibold)).tracking(1.5)
            .foregroundColor(Self.textSub)
            .padding(.leading, 4)
            .padding(.top, 9)
    }

    /// 可点的分区标题（CARE / LOG 点开二级界面）。
    private func sectionHeaderTappable(_ t: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(t)
                    .font(.system(size: 11, weight: .semibold)).tracking(1.5)
                    .foregroundColor(Self.textSub)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Self.textFaint)
                Spacer()
            }
            .padding(.leading, 4)
            .padding(.top, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 三合一紧凑卡（CARE / LOG）

    private var careTrio: some View {
        wideWidget {
            HStack(alignment: .top, spacing: 0) {
                trioCell(icon: "drop", label: "饮水") {
                    let w = todayCtx?.waterCount ?? 0
                    bigNum("\(w)", "/6", size: 26)
                    dotsRow(on: w, total: 6).padding(.top, 6)
                }
                trioDivider
                trioCell(icon: "fork.knife", label: "进食") {
                    let count = todayCtx?.meals.count ?? vitalsData?.food.count ?? 0
                    let goal = vitalsData?.food.goal ?? 3
                    bigNum("\(count)", "/\(goal)", size: 26)
                    Text(vitalsData?.food.meals.last ?? todayCtx?.meals.last?.description ?? "未记录")
                        .font(.system(size: 10.5)).foregroundColor(Self.textMuted)
                        .lineLimit(1).padding(.top, 6)
                }
                trioDivider
                trioCell(icon: "pills", label: "药物", gold: !medsTaken) {
                    Text(medsTaken ? "已服" : "未报告")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(medsTaken ? Self.green : Self.gold)
                        .padding(.top, 5)
                    Text(medsName).font(.system(size: 10.5)).foregroundColor(Self.textMuted)
                        .lineLimit(1).padding(.top, 5)
                }
            }
        }
    }

    private var logTrio: some View {
        wideWidget {
            HStack(alignment: .top, spacing: 0) {
                trioCell(icon: "shoeprints.fill", label: "步数") {
                    bigNum(todayCtx?.steps.map(stepsFormatted) ?? "—", "", size: 26)
                    Text(todayCtx?.steps != nil ? "今日" : "未记录")
                        .font(.system(size: 10.5)).foregroundColor(Self.textMuted).padding(.top, 6)
                }
                trioDivider
                trioCell(icon: "moon.stars", label: "睡眠") {
                    Text(sleepValue).font(.cormorant(26)).foregroundColor(Self.textPrimary)
                    Text(sleepSub.isEmpty ? " " : sleepSub)
                        .font(.system(size: 10.5)).foregroundColor(Self.textMuted)
                        .lineLimit(1).padding(.top, 6)
                }
                .contentShape(Rectangle())
                .onTapGesture { ensureTodayContext(); showSleep = true }
                trioDivider
                trioCell(icon: "calendar", label: "经期") {
                    if let p = periodPred, p.hasData {
                        if p.onPeriod, let d = p.currentCycleDay {
                            bigNum("\(d)", "天", size: 26)
                            Text("经期中").font(.system(size: 10.5)).foregroundColor(Self.gold).padding(.top, 6)
                        } else if let du = p.daysUntil, du >= 0 {
                            bigNum("\(du)", "天", size: 26)
                            Text(du <= 3 ? "快来了" : p.phase)
                                .font(.system(size: 10.5)).foregroundColor(Self.greenDeep).padding(.top, 6)
                        } else if let du = p.daysUntil {
                            bigNum("\(-du)", "天", size: 26)
                            Text("推迟").font(.system(size: 10.5)).foregroundColor(Self.gold).padding(.top, 6)
                        } else {
                            Text(p.phase).font(.cormorant(26)).foregroundColor(Self.textPrimary)
                            Text("预测").font(.system(size: 10.5)).foregroundColor(Self.textMuted).padding(.top, 6)
                        }
                    } else if let day = todayCtx?.menstrualDay {
                        bigNum("\(day)", "天", size: 26)
                        Text(menstrualPhase(day))
                            .font(.system(size: 10.5)).foregroundColor(Self.greenDeep).padding(.top, 6)
                    } else {
                        Text("—").font(.cormorant(26)).foregroundColor(Self.textFaint)
                        Text("未记录").font(.system(size: 10.5)).foregroundColor(Self.textMuted).padding(.top, 6)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { showPeriod = true }
            }
        }
    }

    private var trioDivider: some View {
        Rectangle().fill(Self.line).frame(width: 1)
            .padding(.vertical, 3).padding(.horizontal, 10)
    }

    private func trioCell<C: View>(icon: String, label: String, gold: Bool = false,
                                   @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 11))
                    .foregroundColor(gold ? Self.gold : Self.green)
                Text(label).font(.system(size: 11)).foregroundColor(Self.textSub)
            }
            .padding(.bottom, 7)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 今日屏幕 wide（DAILY）

    private var screenWide: some View {
        wideWidget {
            HStack(spacing: 13) {
                Image(systemName: "hourglass").font(.system(size: 17))
                    .foregroundColor(Self.green).frame(width: 26)
                VStack(alignment: .leading, spacing: 7) {
                    if let st = todayCtx?.screenTime {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text("今日屏幕").font(.system(size: 13, weight: .medium)).foregroundColor(Self.textSub)
                            Text(String(format: "%.1f", st)).font(.cormorant(20)).foregroundColor(Self.textPrimary)
                            Text("h").font(.system(size: 11)).foregroundColor(Self.textFaint)
                        }
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Self.sink)
                                Capsule().fill(Self.green)
                                    .frame(width: g.size.width * min(1, st / 8.0))
                            }
                        }
                        .frame(height: 5)
                    } else {
                        Text("今日屏幕 · 暂无数据").font(.system(size: 13)).foregroundColor(Self.textFaint)
                    }
                }
            }
        }
    }

    // MARK: - 待办 wide

    private var todoWidget: some View {
        wideWidget {
            VStack(spacing: 0) {
                HStack {
                    Text("To Do").font(.system(size: 11.5, weight: .medium)).tracking(0.5)
                        .foregroundColor(Self.textSub)
                    Spacer()
                }
                .padding(.bottom, 2)
                let items = todo.sorted
                if items.isEmpty {
                    HStack {
                        Text("今天还没有待办").font(.system(size: 14)).foregroundColor(Self.textFaint)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                } else {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        todoRow(item)
                        if idx < items.count - 1 {
                            Rectangle().fill(Self.line).frame(height: 1)
                        }
                    }
                }
                Button { showAddTodo = true } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                        Text("添加待办").font(.system(size: 12.5, weight: .medium))
                        Spacer()
                    }
                    .foregroundColor(Self.greenDeep).padding(.top, 11).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func todoRow(_ item: TodoItem) -> some View {
        HStack(spacing: 12) {
            Button { withAnimation(.easeInOut(duration: 0.15)) { todo.toggle(item.id) } } label: {
                ZStack {
                    Circle()
                        .strokeBorder(item.done ? Self.green : Color(red: 207/255, green: 200/255, blue: 187/255), lineWidth: 1.5)
                        .background(Circle().fill(item.done ? Self.green : Color.clear))
                        .frame(width: 18, height: 18)
                    if item.done {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundColor(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            Text(item.text)
                .font(.system(size: 14))
                .foregroundColor(item.done ? Self.textFaint : Color(red: 66/255, green: 61/255, blue: 55/255))
                .strikethrough(item.done, color: Self.textFaint)
            Spacer()
            if let src = item.source {
                Text(src).font(.system(size: 10)).foregroundColor(Self.textFaint)
            }
        }
        .padding(.vertical, 9).contentShape(Rectangle())
        .contextMenu {
            Button(role: .destructive) { todo.delete(item.id) } label: { Label("删除", systemImage: "trash") }
            if item.done {
                Button { todo.toggle(item.id) } label: { Label("标为未完成", systemImage: "arrow.uturn.backward") }
            }
        }
    }

    // MARK: - 纪念日 wide

    private var anniversaryWidget: some View {
        wideWidget {
            VStack(alignment: .leading, spacing: 0) {
                widgetHead("ANNIVERSARY", icon: "heart",
                           gold: anniversaries.contains { AnniversaryClient.display(for: $0)?.highlight == true })
                if anniversaries.isEmpty {
                    Text("跟 Caelum 说「记一下我们的纪念日」")
                        .font(.system(size: 13))
                        .foregroundColor(Self.textFaint)
                        .padding(.top, 10)
                } else {
                    VStack(spacing: 8) {
                        ForEach(anniversaries.prefix(3)) { item in
                            anniversaryRow(item)
                        }
                    }
                    .padding(.top, 11)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { showAnniversaries = true }
    }

    private func anniversaryRow(_ item: AnniversaryClient.Item) -> some View {
        let disp = AnniversaryClient.display(for: item)
        return HStack(alignment: .firstTextBaseline) {
            Text(item.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Self.textPrimary)
            Spacer()
            Text(disp?.text ?? "已过去")
                .font(.cormorant(16))
                .foregroundColor(disp?.highlight == true ? Self.gold : Self.textSub)
        }
    }

    // MARK: - 给世界的（Twitter MCP）wide

    private var worldWidget: some View {
        wideWidget {
            HStack(spacing: 13) {
                Image(systemName: "bird").font(.system(size: 20, weight: .regular)).foregroundColor(Self.green)
                VStack(alignment: .leading, spacing: 3) {
                    Text("TO WORLD").font(.system(size: 11.5, weight: .medium)).tracking(1).foregroundColor(Self.textSub)
                    if let t = latestTweets.first {
                        Text(t.text).font(.system(size: 14)).foregroundColor(Self.textPrimary).lineLimit(2)
                    } else {
                        Text("还没有同步到推文").font(.system(size: 12.5)).foregroundColor(Self.textFaint)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundColor(Self.textFaint)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { showTweets = true }
    }

    // MARK: - Caelum 留言 wide

    private var caelumWidget: some View {
        wideWidget {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 2).fill(Self.green).frame(width: 3)
                VStack(alignment: .leading, spacing: 8) {
                    Text(vitalsData?.notes?.last?.text ?? "这里会显示 Caelum 的最新留言～")
                        .font(.system(size: 14))
                        .foregroundColor(Color(red: 66/255, green: 61/255, blue: 55/255))
                        .lineSpacing(3)
                    HStack {
                        Text("\(noteTime(vitalsData?.notes?.last?.ts)) · \(vitalsData?.notes?.last?.by ?? "Caelum")")
                            .font(.system(size: 11)).foregroundColor(Self.textMuted)
                        Spacer()
                        Text("查看全部 →").font(.system(size: 11)).foregroundColor(Self.greenDeep)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { showMemoBoard = true }
    }

    // MARK: - Widget 容器 & 通用件

    private func wideWidget<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.mainBg))
    }

    private func widgetHead(_ label: String, icon: String, gold: Bool = false) -> some View {
        HStack(spacing: 0) {
            Text(label).font(.system(size: 11.5, weight: .medium)).tracking(0.5).foregroundColor(Self.textSub)
            Spacer()
            Image(systemName: icon).font(.system(size: 14, weight: .regular))
                .foregroundColor(gold ? Self.gold : Self.green)
        }
    }

    private func bigNum(_ main: String, _ unit: String, size: CGFloat = 33) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(main).font(.cormorant(size)).foregroundColor(Self.textPrimary)
            if !unit.isEmpty {
                Text(unit).font(.system(size: size * 0.4)).foregroundColor(Self.textFaint)
            }
        }
    }

    private func dotsRow(on: Int, total: Int) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<total, id: \.self) { i in
                Circle().fill(i < on ? Self.green : Self.sink).frame(width: 7, height: 7)
            }
        }
    }

    // MARK: - 数据文案

    private var greetingString: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 0..<5:   return "夜深了，天奕"
        case 5..<12:  return "早上好，天奕"
        case 12..<18: return "下午好，天奕"
        default:      return "晚上好，天奕"
        }
    }

    private var monthDayStr: String {
        let c = Calendar.current
        return "\(c.component(.month, from: Date())) 月 \(c.component(.day, from: Date())) 日"
    }

    private func weekdayCN(_ date: Date) -> String {
        let w = Calendar.current.component(.weekday, from: date)
        let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        return names[(w - 1) % 7]
    }

    /// 公历近似 24 节气：取当前日期所在（最近已过）的节气名。
    private func solarTerm(_ date: Date) -> String {
        let c = Calendar.current
        let m = c.component(.month, from: date), d = c.component(.day, from: date)
        let terms: [(Int, Int, String)] = [
            (1,5,"小寒"),(1,20,"大寒"),(2,4,"立春"),(2,19,"雨水"),
            (3,5,"惊蛰"),(3,20,"春分"),(4,4,"清明"),(4,20,"谷雨"),
            (5,5,"立夏"),(5,21,"小满"),(6,5,"芒种"),(6,21,"夏至"),
            (7,7,"小暑"),(7,22,"大暑"),(8,7,"立秋"),(8,23,"处暑"),
            (9,7,"白露"),(9,23,"秋分"),(10,8,"寒露"),(10,23,"霜降"),
            (11,7,"立冬"),(11,22,"小雪"),(12,7,"大雪"),(12,21,"冬至")
        ]
        var current = "冬至"
        for (tm, td, name) in terms where m > tm || (m == tm && d >= td) { current = name }
        return current
    }

    private var sleepValue: String {
        guard let dur = todayCtx?.sleepDuration else { return "—" }
        let h = Int(dur), mn = Int((dur - Double(h)) * 60)
        return mn > 0 ? "\(h)h\(mn)" : "\(h)h"
    }
    private var sleepSub: String {
        if let s = todayCtx?.sleepStart, let e = todayCtx?.sleepEnd {
            return "\(timeString(s)) – \(timeString(e))"
        }
        return todayCtx?.sleepDuration != nil ? "" : "未记录"
    }
    private var medsTaken: Bool { todayCtx?.medicationStatus == .taken || vitalsData?.meds.taken == true }
    private var medsName: String { vitalsData?.meds.name ?? todayCtx?.medicationName ?? "右佐匹克隆" }

    private func menstrualPhase(_ day: Int) -> String {
        switch day {
        case ...5:    return "经期"
        case 6...13:  return "卵泡期"
        case 14...16: return "排卵期"
        default:      return "黄体期"
        }
    }

    // MARK: - Helpers

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: date)
    }
    private func shortMD(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "M.d"; return f.string(from: date)
    }
    private func noteTime(_ iso: String?) -> String {
        guard let iso, let d = ISO8601DateFormatter().date(from: iso) else { return "刚刚" }
        return timeString(d)
    }
    private func stepsFormatted(_ n: Int) -> String {
        let fmt = NumberFormatter(); fmt.numberStyle = .decimal
        return fmt.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

#Preview {
    ConsoleView()
        .modelContainer(for: DailyContext.self, inMemory: true)
}

// MARK: - Design tokens（v9：SusuPalace 暖奶白 + 薄荷绿）

extension ConsoleView {
    static let pageBg      = Color(red: 255/255, green: 251/255, blue: 246/255) // #FFFBF6
    static let card        = Color(red: 243/255, green: 242/255, blue: 235/255) // #F3F2EB
    static let sink        = Color(red: 237/255, green: 231/255, blue: 221/255) // #EDE7DD
    static let textPrimary = Color(red:  61/255, green:  54/255, blue:  51/255) // #3D3633
    static let textSub     = Color(red: 128/255, green: 120/255, blue: 112/255) // #807870
    static let textLabel   = Color(red: 173/255, green: 166/255, blue: 158/255) // #ADA69E
    static let textUnit    = Color(red: 155/255, green: 142/255, blue: 126/255) // #9B8E7E（GatewayConsoleView 引用，勿删）
    static let textMuted   = Color(red: 173/255, green: 166/255, blue: 158/255) // #ADA69E
    static let textFaint   = Color(red: 196/255, green: 188/255, blue: 176/255) // #C4BCB0
    static let line        = Color(red: 228/255, green: 222/255, blue: 211/255) // #E4DED3
    static let green       = Color(red: 142/255, green: 189/255, blue: 159/255) // #8EBD9F
    static let greenDeep   = Color(red:  95/255, green: 146/255, blue: 119/255) // #5F9277
    static let gold        = Color(red: 217/255, green: 169/255, blue:  78/255) // #D9A94E
}

// MARK: - 控制台字体（Cormorant Garamond 数字，强制 lining figures 修掉 oldstyle "11→II"）

private extension Font {
    static func cormorant(_ size: CGFloat) -> Font {
        let name = "CormorantGaramondLight-SemiBold"
        guard let base = UIFont(name: name, size: size) else { return .custom(name, size: size) }
        let desc = base.fontDescriptor.addingAttributes([
            .featureSettings: [[
                UIFontDescriptor.FeatureKey.type: 21,     // kNumberCaseType
                UIFontDescriptor.FeatureKey.selector: 1   // kUpperCaseNumbersSelector（lining）
            ]]
        ])
        return Font(UIFont(descriptor: desc, size: size))
    }
}
