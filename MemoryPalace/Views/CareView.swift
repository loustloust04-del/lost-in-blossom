import SwiftUI
import SwiftData

/// Care · 护理仪表盘（控制台 CARE 区点开）。
/// 今日饮水/进食/药物/睡眠环形进度 + 经期周期环 + 近 7 天饮水/睡眠趋势。
/// 只读汇总视图，数据来自 DailyContext 历史 + 网关 vitals + 经期预测。
struct CareView: View {
    let contexts: [DailyContext]        // 倒序（最新在前）
    let vitals: VitalsResponse?
    let period: PeriodClient.Prediction?

    @Environment(\.dismiss) private var dismiss

    private var today: DailyContext? {
        contexts.first { Calendar.current.isDate($0.date, inSameDayAs: Date()) }
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    ringsCard
                    if let p = period, p.hasData { cycleCard(p) }
                    trendsCard
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .background(Theme.sidebarBg.ignoresSafeArea())
            .navigationTitle("护理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }.foregroundColor(ConsoleView.greenDeep)
                }
            }
        }
    }

    // MARK: - 今日环

    private var ringsCard: some View {
        let t = today
        let waterVal = Double(t?.waterCount ?? 0)
        let waterGoal = Double(vitals?.water.goal ?? 6)
        let foodVal = Double(vitals?.food.count ?? t?.meals.count ?? 0)
        let foodGoal = Double(vitals?.food.goal ?? 3)
        let medsTaken = t?.medicationStatus == .taken || vitals?.meds.taken == true
        let sleepVal = t?.sleepDuration ?? 0
        return VStack(alignment: .leading, spacing: 14) {
            Text("今日照顾")
                .font(.system(size: 13, weight: .semibold)).tracking(0.5)
                .foregroundColor(ConsoleView.textSub)
            HStack(spacing: 8) {
                ring("饮水", "\(t?.waterCount ?? 0)/\(Int(waterGoal))", waterVal / max(waterGoal, 1), ConsoleView.green, "drop.fill")
                ring("进食", "\(Int(foodVal))/\(Int(foodGoal))", foodVal / max(foodGoal, 1), ConsoleView.green, "fork.knife")
                ring("药物", medsTaken ? "已服" : "未服", medsTaken ? 1 : 0, medsTaken ? ConsoleView.green : ConsoleView.gold, "pills.fill")
                ring("睡眠", sleepText(sleepVal), min(sleepVal / 8, 1), ConsoleView.greenDeep, "moon.fill")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.mainBg))
    }

    private func ring(_ label: String, _ center: String, _ pct: Double, _ color: Color, _ icon: String) -> some View {
        VStack(spacing: 7) {
            ZStack {
                Circle().stroke(ConsoleView.sink, lineWidth: 6)
                Circle().trim(from: 0, to: max(0, min(1, pct)))
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: icon).font(.system(size: 14)).foregroundColor(color)
            }
            .frame(width: 54, height: 54)
            Text(center).font(.system(size: 11.5, weight: .semibold)).foregroundColor(ConsoleView.textPrimary)
            Text(label).font(.system(size: 10.5)).foregroundColor(ConsoleView.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 经期周期环

    private func cycleCard(_ p: PeriodClient.Prediction) -> some View {
        let day = p.currentCycleDay ?? 0
        let pct = p.avgCycle > 0 ? min(1, Double(day) / Double(p.avgCycle)) : 0
        return HStack(spacing: 16) {
            ZStack {
                Circle().stroke(ConsoleView.sink, lineWidth: 7)
                Circle().trim(from: 0, to: pct)
                    .stroke(ConsoleView.gold, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(day)").font(.system(size: 21, weight: .semibold)).foregroundColor(ConsoleView.textPrimary)
                    Text("天").font(.system(size: 10)).foregroundColor(ConsoleView.textMuted)
                }
            }
            .frame(width: 74, height: 74)
            VStack(alignment: .leading, spacing: 5) {
                Text("经期周期").font(.system(size: 14, weight: .medium)).foregroundColor(ConsoleView.textPrimary)
                Text(p.phase).font(.system(size: 12.5, weight: .medium)).foregroundColor(ConsoleView.greenDeep)
                if let du = p.daysUntil {
                    Text(du < 0 ? "已推迟 \(-du) 天" : (du == 0 ? "预计今天来潮" : "预计还有 \(du) 天来潮"))
                        .font(.system(size: 12)).foregroundColor(ConsoleView.textMuted)
                }
                Text("平均周期 \(p.avgCycle) 天").font(.system(size: 11)).foregroundColor(ConsoleView.textFaint)
            }
            Spacer()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.mainBg))
    }

    // MARK: - 近 7 天趋势

    private var trendsCard: some View {
        let last7 = Array(contexts.prefix(7).reversed())
        return VStack(alignment: .leading, spacing: 16) {
            Text("近 7 天")
                .font(.system(size: 13, weight: .semibold)).tracking(0.5)
                .foregroundColor(ConsoleView.textSub)
            trendBars("饮水（杯）", last7.map { Double($0.waterCount) }, last7.map { dayLabel($0.date) },
                      ConsoleView.green, goal: Double(vitals?.water.goal ?? 6))
            trendBars("睡眠（小时）", last7.map { $0.sleepDuration ?? 0 }, last7.map { dayLabel($0.date) },
                      ConsoleView.greenDeep, goal: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.mainBg))
    }

    private func trendBars(_ title: String, _ values: [Double], _ labels: [String], _ color: Color, goal: Double) -> some View {
        let maxV = max(values.max() ?? 1, goal, 1)
        return VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundColor(ConsoleView.textSub)
            if values.isEmpty {
                Text("暂无历史").font(.system(size: 12)).foregroundColor(ConsoleView.textFaint).padding(.vertical, 12)
            } else {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(values.indices, id: \.self) { i in
                        VStack(spacing: 4) {
                            Text(values[i] > 0 ? trimNum(values[i]) : " ")
                                .font(.system(size: 8.5)).foregroundColor(ConsoleView.textFaint)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color.opacity(values[i] > 0 ? 0.85 : 0.18))
                                .frame(height: CGFloat(values[i] / maxV) * 66 + 3)
                            Text(i < labels.count ? labels[i] : "").font(.system(size: 8.5)).foregroundColor(ConsoleView.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 96)
            }
        }
    }

    // MARK: - helpers

    private func sleepText(_ h: Double) -> String {
        guard h > 0 else { return "—" }
        let hh = Int(h), mm = Int((h - Double(hh)) * 60)
        return mm > 0 ? "\(hh)h\(mm)" : "\(hh)h"
    }
    private func dayLabel(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "M.d"; return f.string(from: d)
    }
    private func trimNum(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}
