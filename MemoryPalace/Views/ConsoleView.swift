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
    @State private var showAddTodo: Bool = false
    @State private var newTodoText: String = ""
    @State private var todo = TodoManager.shared

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
            Button("添加") { todo.add(newTodoText); newTodoText = "" }
        }
        .sheet(isPresented: $showMemoBoard) { MemoBoardPlaceholder() }
    }

    private func ensureTodayContext() { DailyContextStore.ensureToday(context: modelContext) }
    private func loadVitals() {
        Task { let v = await VitalsClient.fetch(); await MainActor.run { vitalsData = v } }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text("CAELUM'S CONSOLE")
                    .font(.system(size: 10.5, weight: .semibold)).tracking(2.5)
                    .foregroundColor(Self.greenDeep)
                Text(greetingString)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Self.textPrimary)
                    .padding(.top, 6)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(monthDayStr).font(.system(size: 13)).foregroundColor(Self.textMuted)
                Text("\(weekdayCN(Date())) · \(solarTerm(Date()))")
                    .font(.system(size: 12)).foregroundColor(Self.textMuted)
            }
            .padding(.top, 4)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Grid

    private var grid: some View {
        VStack(spacing: 11) {
            HStack(spacing: 11) { waterWidget; foodWidget }
            todoWidget
            HStack(spacing: 11) { stepsWidget; sleepWidget }
            HStack(spacing: 11) { medsWidget; screenWidget }
            cycleWidget
            worldWidget
            caelumWidget
        }
    }

    // MARK: - 小 widget（饮水/进食/步数/睡眠/药物/屏幕）

    private var waterWidget: some View {
        let w = todayCtx?.waterCount ?? 0
        return smallWidget {
            VStack(alignment: .leading, spacing: 0) {
                widgetHead("饮水", icon: "drop")
                Spacer(minLength: 6)
                bigNum("\(w)", "/6")
                dotsRow(on: w, total: 6).padding(.top, 9)
            }
        }
    }

    private var foodWidget: some View {
        let count = todayCtx?.meals.count ?? vitalsData?.food.count ?? 0
        let goal = vitalsData?.food.goal ?? 3
        let note = vitalsData?.food.meals.last ?? todayCtx?.meals.last?.description ?? "未记录"
        return smallWidget {
            VStack(alignment: .leading, spacing: 0) {
                widgetHead("进食", icon: "fork.knife")
                Spacer(minLength: 6)
                bigNum("\(count)", "/\(goal)")
                Text(note).font(.system(size: 11)).foregroundColor(Self.greenDeep)
                    .lineLimit(1).padding(.top, 9)
            }
        }
    }

    private var stepsWidget: some View {
        smallWidget {
            VStack(alignment: .leading, spacing: 0) {
                widgetHead("步数", icon: "shoeprints.fill")
                Spacer(minLength: 6)
                bigNum(todayCtx?.steps.map(stepsFormatted) ?? "—", "")
                Text(todayCtx?.steps != nil ? "步 · 今日" : "未记录")
                    .font(.system(size: 11)).foregroundColor(Self.textMuted).padding(.top, 9)
            }
        }
    }

    private var sleepWidget: some View {
        smallWidget {
            VStack(alignment: .leading, spacing: 0) {
                widgetHead("睡眠", icon: "moon.stars")
                Spacer(minLength: 6)
                Text(sleepValue).font(.cormorant(33)).foregroundColor(Self.textPrimary)
                Text(sleepSub.isEmpty ? " " : sleepSub)
                    .font(.system(size: 11)).foregroundColor(Self.textMuted).lineLimit(1).padding(.top, 9)
            }
        }
    }

    private var medsWidget: some View {
        smallWidget {
            VStack(alignment: .leading, spacing: 0) {
                widgetHead("药物", icon: "pills", gold: !medsTaken)
                Spacer(minLength: 6)
                Text(medsTaken ? "已服" : "未报告")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(medsTaken ? Self.green : Self.gold)
                Text(medsName).font(.system(size: 11)).foregroundColor(Self.textMuted)
                    .lineLimit(1).padding(.top, 9)
            }
        }
    }

    private var screenWidget: some View {
        smallWidget {
            VStack(alignment: .leading, spacing: 0) {
                widgetHead("今日屏幕", icon: "hourglass")
                Spacer(minLength: 6)
                if let st = todayCtx?.screenTime {
                    bigNum(String(format: "%.1f", st), "h")
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Self.sink)
                            Capsule().fill(Self.green)
                                .frame(width: g.size.width * min(1, st / 8.0))
                        }
                    }
                    .frame(height: 4).padding(.top, 10)
                } else {
                    bigNum("—", "")
                    Text("Screen Time API 暂不可用")
                        .font(.system(size: 10.5)).foregroundColor(Self.textFaint)
                        .lineLimit(1).minimumScaleFactor(0.8).padding(.top, 8)
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

    // MARK: - 经期 wide

    private var cycleWidget: some View {
        wideWidget {
            if let day = todayCtx?.menstrualDay {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .bottom) {
                        bigNum("\(day)", "天", size: 36)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(menstrualPhase(day))
                                .font(.system(size: 15, weight: .semibold)).foregroundColor(Self.greenDeep)
                            if let next = todayCtx?.nextPeriodDate {
                                let d = max(0, Calendar.current.dateComponents([.day], from: Date(), to: next).day ?? 0)
                                Text("预计 \(d) 天后来潮").font(.system(size: 11.5)).foregroundColor(Self.textSub)
                            }
                        }
                    }
                    Rectangle().fill(Self.line).frame(height: 1).padding(.top, 14).padding(.bottom, 12)
                    HStack(spacing: 22) {
                        cycStat("29", "上次周期")
                        cycStat("5", "经期时长")
                        if let next = todayCtx?.nextPeriodDate { cycStat(shortMD(next), "预计来潮") }
                    }
                }
            } else {
                HStack {
                    Text("未记录经期").font(.system(size: 14)).foregroundColor(Self.textFaint)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func cycStat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(.cormorant(17)).foregroundColor(Self.textPrimary)
            Text(l).font(.system(size: 10.5)).foregroundColor(Self.textMuted)
        }
    }

    // MARK: - 给世界的（Twitter MCP）wide

    private var worldWidget: some View {
        wideWidget {
            HStack(spacing: 13) {
                Image(systemName: "globe").font(.system(size: 22, weight: .regular)).foregroundColor(Self.textMuted)
                VStack(alignment: .leading, spacing: 3) {
                    if let n = todayCtx?.tweetCount {
                        Text("今日 \(n) 条").font(.system(size: 15, weight: .semibold)).foregroundColor(Self.textPrimary)
                        if let s = todayCtx?.latestTweetSummary {
                            Text(s).font(.system(size: 11.5)).foregroundColor(Self.textMuted).lineLimit(1)
                        }
                    } else {
                        Text("给世界的").font(.system(size: 14, weight: .medium)).foregroundColor(Self.textSub)
                        Text("待接入 Twitter MCP").font(.system(size: 11)).foregroundColor(Self.textFaint)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundColor(Self.textFaint)
            }
        }
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

    private func smallWidget<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(EdgeInsets(top: 13, leading: 15, bottom: 13, trailing: 15))
            .frame(height: 120)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Self.card))
    }

    private func wideWidget<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Self.card))
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

// MARK: - 留言板 placeholder

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

// MARK: - Design tokens（v9：SusuPalace 暖奶白 + 薄荷绿）

extension ConsoleView {
    static let pageBg      = Color(red: 255/255, green: 251/255, blue: 246/255) // #FFFBF6
    static let card        = Color(red: 243/255, green: 242/255, blue: 235/255) // #F3F2EB
    static let sink        = Color(red: 237/255, green: 231/255, blue: 221/255) // #EDE7DD
    static let textPrimary = Color(red:  61/255, green:  54/255, blue:  51/255) // #3D3633
    static let textSub     = Color(red: 128/255, green: 120/255, blue: 112/255) // #807870
    static let textLabel   = Color(red: 173/255, green: 166/255, blue: 158/255) // #ADA69E
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
