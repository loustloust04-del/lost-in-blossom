import SwiftUI

/// 纪念日管理页 — 控制台纪念日卡点开进入。
/// 数据直连网关 /api/anniversaries（与 Caelum 的 remember_anniversary 同一份）。
struct AnniversaryManageSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var items: [AnniversaryClient.Item] = []
    @State private var loading = true

    // 新增表单
    @State private var newName = ""
    @State private var newDate = Date()
    @State private var newIsCountdown = false
    @State private var saving = false

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    listSection
                    addSection
                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .background(ConsoleView.pageBg.ignoresSafeArea())
            .navigationTitle("纪念日")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundColor(ConsoleView.greenDeep)
                }
            }
        }
        .task { await reload() }
    }

    private func reload() async {
        loading = true
        items = await AnniversaryClient.fetch()
        loading = false
    }

    // MARK: - 列表

    private var listSection: some View {
        VStack(spacing: 9) {
            if loading {
                ProgressView().padding(.vertical, 30)
            } else if items.isEmpty {
                Text("还没有记录。也可以直接跟 Caelum 说\n「记一下我们 X 月 X 日相识」")
                    .font(.system(size: 13.5))
                    .foregroundColor(ConsoleView.textFaint)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 30)
            } else {
                ForEach(items) { item in
                    itemRow(item)
                }
            }
        }
    }

    private func itemRow(_ item: AnniversaryClient.Item) -> some View {
        let disp = AnniversaryClient.display(for: item)
        return HStack(spacing: 12) {
            Image(systemName: item.type == "countdown" ? "hourglass" : "heart")
                .font(.system(size: 15))
                .foregroundColor(disp?.highlight == true ? ConsoleView.gold : ConsoleView.green)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(ConsoleView.textPrimary)
                Text(item.date)
                    .font(.system(size: 11.5))
                    .foregroundColor(ConsoleView.textMuted)
            }
            Spacer()
            Text(disp?.text ?? "已过去")
                .font(.system(size: 13.5, weight: disp?.highlight == true ? .semibold : .regular))
                .foregroundColor(disp?.highlight == true ? ConsoleView.gold : ConsoleView.textSub)
            Button {
                Task {
                    _ = await AnniversaryClient.remove(id: item.id)
                    await reload()
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(ConsoleView.textFaint)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(ConsoleView.card))
    }

    // MARK: - 新增

    private var addSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ADD")
                .font(.system(size: 11.5, weight: .medium)).tracking(0.5)
                .foregroundColor(ConsoleView.textSub)
            TextField("名字（相识 / 生日 / 去日本…）", text: $newName)
                .font(.system(size: 15))
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(ConsoleView.sink))
            DatePicker("日期", selection: $newDate, displayedComponents: .date)
                .font(.system(size: 14))
                .tint(ConsoleView.greenDeep)
            Picker("类型", selection: $newIsCountdown) {
                Text("纪念日（每年）").tag(false)
                Text("倒计时（一次）").tag(true)
            }
            .pickerStyle(.segmented)
            Button {
                Task { await addNew() }
            } label: {
                HStack {
                    Spacer()
                    if saving { ProgressView().tint(.white) }
                    else { Text("记住这一天").font(.system(size: 15, weight: .semibold)) }
                    Spacer()
                }
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(
                    newName.trimmingCharacters(in: .whitespaces).isEmpty ? ConsoleView.textFaint : ConsoleView.greenDeep))
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || saving)
        }
        .padding(15)
        .background(RoundedRectangle(cornerRadius: 14).fill(ConsoleView.card))
    }

    private func addNew() async {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        saving = true
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        _ = await AnniversaryClient.add(name: name, date: f.string(from: newDate),
                                        type: newIsCountdown ? "countdown" : "anniversary")
        newName = ""
        saving = false
        await reload()
    }
}
