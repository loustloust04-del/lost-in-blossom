import Foundation
import Observation

/// 控制台待办。G1：本地 UserDefaults；G2 会加网关同步，让 Caelum(CC/API) 也能写。
struct TodoItem: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var text: String
    var done: Bool = false
    /// 可选：由 Caelum 写入时标记来源，UI 显示小标
    var source: String? = nil
    var createdAt: Date = Date()
}

@MainActor
@Observable
final class TodoManager {
    static let shared = TodoManager()
    private static let key = "consoleTodoItems_v1"

    private(set) var items: [TodoItem]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([TodoItem].self, from: data) {
            items = decoded
        } else {
            items = []
        }
    }

    var remaining: Int { items.filter { !$0.done }.count }

    /// 未完成在前、已完成沉底；各自按创建时间
    var sorted: [TodoItem] {
        items.sorted { a, b in
            if a.done != b.done { return !a.done }
            return a.createdAt < b.createdAt
        }
    }

    func add(_ text: String, source: String? = nil) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        items.append(TodoItem(text: t, source: source))
        save()
    }

    func toggle(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].done.toggle()
        save()
    }

    func delete(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    /// 清掉已完成的
    func clearDone() {
        items.removeAll { $0.done }
        save()
    }

    private func save() {
        if let d = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(d, forKey: Self.key)
        }
    }
}
