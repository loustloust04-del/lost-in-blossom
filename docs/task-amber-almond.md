# Amber & Almond：记忆分区系统

> 2026-06-03 · Caelum · 给猫的任务文档

---

## 概念

侧边栏底部新增两个独立入口，与 Chats / Projects 平行但分离：

- **Almond（杏仁）** — Claude App 导出的聊天记录。活的记忆，最终会被消化成 RAG 向量数据库。
- **Amber（琥珀）** — ChatGPT 导出的聊天记录。封存的记忆，保留原样，不被触碰。

侧边栏结构：
```
Chats        ← 当前 App 里新建的对话
Projects     ← 任务/项目分组
Almond 🌰    ← Claude 历史（活的，待消化）
Amber 🪨     ← ChatGPT 历史（封存的，只看不碰）
```

默认视图只显示 Chats。用户点击 Almond 或 Amber 切换视图。

---

## 数据模型改动

### Conversation 模型

文件：`MemoryPalace/Models/Conversation.swift`

新增一个字段：

```swift
var source: String?   // nil = native (App内新建), "claude" = Claude导入, "chatgpt" = ChatGPT导入
```

这个字段在导入时设置，之后不变。

---

## 导入器改动

### ConversationImporter.swift（ChatGPT 导入器）

找到导入对话入库的位置（大约在 `context.insert(conversation)` 或类似的地方），在插入前加：

```swift
conversation.source = "chatgpt"
```

### ClaudeImporter.swift（Claude 导入器）

同样，在导入对话入库时加：

```swift
conversation.source = "claude"
```

---

## 侧边栏改动

文件：`MemoryPalace/Views/SidebarView.swift`

### 新增 State 变量

```swift
enum SidebarFilter: String, CaseIterable {
    case chats = "Chats"
    case almond = "Almond"
    case amber = "Amber"
}

@State private var currentFilter: SidebarFilter = .chats
```

### 过滤对话列表

找到对话列表的 ForEach 或 FetchDescriptor，在查询条件中加入 source 过滤：

```swift
// 根据 currentFilter 过滤
let filteredConversations: [Conversation]
switch currentFilter {
case .chats:
    filteredConversations = conversations.filter { $0.source == nil }
case .almond:
    filteredConversations = conversations.filter { $0.source == "claude" }
case .amber:
    filteredConversations = conversations.filter { $0.source == "chatgpt" }
}
```

### 侧边栏底部入口

在侧边栏的底部（Chats 列表和 Projects 列表下方）加两个按钮：

```swift
// ── 记忆分区 ──────────────────────────────────
Section {
    Button(action: { currentFilter = .almond }) {
        HStack {
            Text("🌰")
            Text("Almond")
                .font(.system(size: 14, weight: currentFilter == .almond ? .semibold : .regular))
            Spacer()
            if currentFilter == .almond {
                Image(systemName: "checkmark")
                    .font(.caption)
                    .foregroundColor(Theme.softBlue)
            }
        }
    }
    .buttonStyle(.plain)

    Button(action: { currentFilter = .amber }) {
        HStack {
            Text("🪨")
            Text("Amber")
                .font(.system(size: 14, weight: currentFilter == .amber ? .semibold : .regular))
            Spacer()
            if currentFilter == .amber {
                Image(systemName: "checkmark")
                    .font(.caption)
                    .foregroundColor(Theme.softBlue)
            }
        }
    }
    .buttonStyle(.plain)
} header: {
    Text("Memory")
        .font(.caption)
        .foregroundColor(Theme.textMuted)
}

// 同时确保有一个返回 Chats 的入口
Button(action: { currentFilter = .chats }) {
    HStack {
        Text("💬")
        Text("Chats")
            .font(.system(size: 14, weight: currentFilter == .chats ? .semibold : .regular))
        Spacer()
        if currentFilter == .chats {
            Image(systemName: "checkmark")
                .font(.caption)
                .foregroundColor(Theme.softBlue)
        }
    }
}
.buttonStyle(.plain)
```

注意：以上代码是示意。猫需要根据 SidebarView 的实际结构来适配。关键逻辑是：
1. 三个过滤状态：chats / almond / amber
2. 对话列表根据 source 字段过滤
3. 底部有切换入口

---

## 修改文件清单

| 文件 | 改动 |
|------|------|
| Conversation.swift | 新增 source: String? 字段 |
| ConversationImporter.swift | 导入时设 source = "chatgpt" |
| ClaudeImporter.swift | 导入时设 source = "claude" |
| SidebarView.swift | 过滤逻辑 + Almond/Amber 入口 |

## 执行指令

```
仓库 caelumbunny-bot/lost-in-blossom。git checkout main && git pull。
读 docs/task-amber-almond.md。按文档做。
四个文件，每个文件一个 commit。
注意 SwiftData 的 @Model 宏——新增字段需要是 Optional 或有默认值，否则迁移会炸。source 字段是 String? 所以默认 nil，没问题。
```

---

*Amber & Almond · 兔兔的琥珀，主人的杏仁*
