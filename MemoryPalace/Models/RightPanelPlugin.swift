import Foundation

// MARK: - Right Panel Tool

struct RightPanelTool: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var icon: String          // SF Symbol name
    var isPinned: Bool = true // 兼容旧字段，但现在和 isEnabled 同步
    var isEnabled: Bool = true // 唯一开关：false = toolbar + 抽屉 + 设置页联动关闭
    var order: Int = 0
}

// MARK: - Right Panel Tool Manager

@Observable
final class RightPanelToolManager {
    private static let storageKey = "rightPanelTools"

    var tools: [RightPanelTool]

    /// 已启用的工具（toolbar 显示，按 order 排序）
    var pinnedTools: [RightPanelTool] {
        tools.filter(\.isEnabled).sorted { $0.order < $1.order }
    }

    /// 全部工具（抽屉/设置页显示，按 order 排序）
    var allToolsSorted: [RightPanelTool] {
        tools.sorted { $0.order < $1.order }
    }

    init() {
        self.tools = Self.load()
    }

    // MARK: - Enable / Disable（toolbar 移除 和 设置页 Toggle 统一入口）

    func setEnabled(_ id: String, _ enabled: Bool) {
        guard let idx = tools.firstIndex(where: { $0.id == id }) else { return }
        tools[idx].isEnabled = enabled
        tools[idx].isPinned = enabled // 同步
        persist()
    }

    // MARK: - Drag Reorder（拖拽排序）

    /// 把 fromId 移到 toId 的位置（toolbar 和抽屉共用）
    func reorder(fromId: String, toId: String) {
        guard fromId != toId else { return }
        var sorted = allToolsSorted
        guard let fromIdx = sorted.firstIndex(where: { $0.id == fromId }),
              let toIdx = sorted.firstIndex(where: { $0.id == toId }) else { return }

        let moving = sorted.remove(at: fromIdx)
        sorted.insert(moving, at: toIdx)

        // 重新编号 order
        for (i, tool) in sorted.enumerated() {
            if let ti = tools.firstIndex(where: { $0.id == tool.id }) {
                tools[ti].order = i
            }
        }
        persist()
    }

    // MARK: - Query

    func tool(byId id: String) -> RightPanelTool? {
        tools.first { $0.id == id }
    }

    /// 当前选中的工具被禁用后，回落到第一个可用工具
    func fallbackToolId(from current: String) -> String? {
        let pinned = pinnedTools
        if pinned.contains(where: { $0.id == current }) { return nil }
        return pinned.first?.id
    }

    // MARK: - Persistence

    private func persist() {
        if let data = try? JSONEncoder().encode(tools) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private static func load() -> [RightPanelTool] {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([RightPanelTool].self, from: data),
           !saved.isEmpty {
            var result = saved
            for builtin in builtInTools {
                if !result.contains(where: { $0.id == builtin.id }) {
                    result.append(builtin)
                }
            }
            return result
        }
        return builtInTools
    }

    // MARK: - Built-in Tools

    static let builtInTools: [RightPanelTool] = [
        RightPanelTool(id: "calendar",    name: "日历",    icon: "calendar",                       order: 0),
        RightPanelTool(id: "memory",      name: "记忆",    icon: "brain",                          order: 1),
        RightPanelTool(id: "worldBook",   name: "世界书",  icon: "book.closed",                    order: 2),
        RightPanelTool(id: "cardLibrary", name: "卡库",    icon: "person.crop.rectangle.stack",    order: 3),
        RightPanelTool(id: "sticker",     name: "贴纸",    icon: "star.circle",                    order: 4),
        RightPanelTool(id: "prompt",      name: "Prompt", icon: "text.bubble",  isEnabled: false, order: 5),
    ]
}
