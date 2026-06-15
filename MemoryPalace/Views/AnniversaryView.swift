import SwiftUI

// MARK: - 纪念日数据

struct Anniversary: Codable, Identifiable {
    let id: String
    var name: String
    var date: Date
    var emoji: String
    
    init(name: String, date: Date, emoji: String = "❤️") {
        self.id = UUID().uuidString
        self.name = name
        self.date = date
        self.emoji = emoji
    }
    
    var daysFromNow: Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: date)).day ?? 0
    }
    
    /// 如果是过去的日期，算"已经过了多少天"
    var daysSince: Int { -daysFromNow }
    
    /// 下一个周年纪念距今天数
    var daysUntilNext: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var comps = cal.dateComponents([.month, .day], from: date)
        comps.year = cal.component(.year, from: today)
        guard let thisYear = cal.date(from: comps) else { return 0 }
        if thisYear >= today { return cal.dateComponents([.day], from: today, to: thisYear).day ?? 0 }
        comps.year = cal.component(.year, from: today) + 1
        guard let nextYear = cal.date(from: comps) else { return 0 }
        return cal.dateComponents([.day], from: today, to: nextYear).day ?? 0
    }
}

// MARK: - 存储

enum AnniversaryStore {
    static let key = "anniversaries"
    
    static func load() -> [Anniversary] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Anniversary].self, from: data)) ?? []
    }
    
    static func save(_ items: [Anniversary]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - 纪念日列表页

struct AnniversaryView: View {
    @State private var items: [Anniversary] = AnniversaryStore.load()
    @State private var showAdd = false
    
    var body: some View {
        List {
            if items.isEmpty {
                VStack(spacing: 12) {
                    Text("还没有纪念日")
                        .font(.system(size: 15))
                        .foregroundColor(Color(hex: "8B7355"))
                    Text("点右上角 + 添加第一个")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "8B7355").opacity(0.6))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowBackground(Color.clear)
            }
            
            ForEach(items.sorted(by: { $0.daysUntilNext < $1.daysUntilNext })) { item in
                anniversaryRow(item)
            }
            .onDelete(perform: delete)
        }
        .listStyle(.insetGrouped)
        .navigationTitle("纪念日")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showAdd = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddAnniversarySheet { newItem in
                items.append(newItem)
                AnniversaryStore.save(items)
            }
        }
    }
    
    private func anniversaryRow(_ item: Anniversary) -> some View {
        HStack(spacing: 12) {
            Text(item.emoji)
                .font(.system(size: 28))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.system(size: 15, weight: .medium))
                
                let formatter = DateFormatter()
                let _ = formatter.dateFormat = "yyyy.MM.dd"
                Text(formatter.string(from: item.date))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                if item.daysFromNow == 0 {
                    Text("今天！")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.orange)
                } else if item.daysFromNow > 0 {
                    Text("还有")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("\(item.daysFromNow)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "8B7355"))
                    Text("天")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    Text("已经")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("\(item.daysSince)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "8B7355"))
                    Text("天")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func delete(at offsets: IndexSet) {
        let sorted = items.sorted(by: { $0.daysUntilNext < $1.daysUntilNext })
        let toRemove = offsets.map { sorted[$0].id }
        items.removeAll { toRemove.contains($0.id) }
        AnniversaryStore.save(items)
    }
}

// MARK: - 添加纪念日

struct AddAnniversarySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var date = Date()
    @State private var emoji = "❤️"
    var onSave: (Anniversary) -> Void
    
    private let emojis = ["❤️", "🌸", "🎂", "💍", "🏠", "✈️", "🎓", "🐰", "🌙", "⭐️", "🔥", "💜"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("比如：在一起的日子", text: $name)
                }
                
                Section("日期") {
                    DatePicker("选择日期", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                }
                
                Section("图标") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(emojis, id: \.self) { e in
                            Button(action: { emoji = e }) {
                                Text(e)
                                    .font(.system(size: 28))
                                    .padding(6)
                                    .background(emoji == e ? Color(hex: "8B7355").opacity(0.2) : Color.clear)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("添加纪念日")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let item = Anniversary(name: name, date: date, emoji: emoji)
                        onSave(item)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Color hex helper (如果项目里还没有)

private extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r, g, b: Double
        if h.count == 6 {
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8) & 0xFF) / 255
            b = Double(int & 0xFF) / 255
        } else { r = 0; g = 0; b = 0 }
        self.init(red: r, green: g, blue: b)
    }
}
