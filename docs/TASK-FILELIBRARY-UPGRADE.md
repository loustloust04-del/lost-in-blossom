# 任务：文件库三波升级

> 参考：`/root/projects/SusuPalace` origin/master
> 分三波，每波独立可交付，按顺序做

---

## 第一波：存储层补强（30 分钟）

### 1a. FileLibraryStore 加 3 个函数

文件：`MemoryPalace/Services/FileLibraryStore.swift`

在 `delete` 函数后面加：

```swift
/// 文件末尾追加内容（日记/笔记用）。文件不存在时自动创建。
static func append(_ relPath: String, content: String, profileId: String) throws {
    guard let url = resolve(relPath, profileId: profileId) else { throw err("非法路径: \(relPath)") }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: url.path) {
        let handle = try FileHandle(forWritingTo: url)
        handle.seekToEndOfFile()
        handle.write(content.data(using: .utf8)!)
        handle.closeFile()
    } else {
        try content.data(using: .utf8)!.write(to: url, options: .atomic)
    }
}

/// 重命名或移动文件。目标已存在时报错。
static func rename(_ oldPath: String, to newPath: String, profileId: String) throws {
    guard let src = resolve(oldPath, profileId: profileId) else { throw err("非法路径: \(oldPath)") }
    guard let dst = resolve(newPath, profileId: profileId) else { throw err("非法路径: \(newPath)") }
    guard !FileManager.default.fileExists(atPath: dst.path) else { throw err("目标已存在: \(newPath)") }
    try FileManager.default.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.moveItem(at: src, to: dst)
}

/// 文件是否存在
static func exists(_ relPath: String, profileId: String) -> Bool {
    guard let url = resolve(relPath, profileId: profileId) else { return false }
    return FileManager.default.fileExists(atPath: url.path)
}
```

### 1b. FileLibraryTools 加 2 个工具

文件：`MemoryPalace/Services/FileLibraryTools.swift`

**enum Name 加两个 case**：
```swift
enum Name: String, CaseIterable {
    case list = "fs_list", read = "fs_read", search = "fs_search"
    case write = "fs_write", append = "fs_append", edit = "fs_edit"
    case rename = "fs_rename", delete = "fs_delete"
}
```

**specs 数组加两条**（在 `.write` 和 `.edit` 之间加 `.append`，在 `.delete` 前加 `.rename`）：
```swift
(.append, "在文件末尾追加内容；文件不存在时创建", 
    ["path": ["type": "string"], "content": ["type": "string"]], ["path", "content"]),
(.rename, "重命名或移动文件；目标已存在时失败", 
    ["old_path": ["type": "string"], "new_path": ["type": "string"]], ["old_path", "new_path"]),
```

**execute switch 加两个 case**：
```swift
case .append:
    try FileLibraryStore.append(str(args, "path"), content: str(args, "content"), profileId: profileId)
    return ok("已追加到 \(str(args, "path"))")
case .rename:
    try FileLibraryStore.rename(str(args, "old_path"), to: str(args, "new_path"), profileId: profileId)
    return ok("已重命名 \(str(args, "old_path")) → \(str(args, "new_path"))")
```

**注入模板更新**（`defaultInjectionTemplate`）：
```swift
static let defaultInjectionTemplate = """
你有一个持久的 markdown 文件库，可用 fs_list / fs_read / fs_search / fs_write / fs_append / fs_edit / fs_rename / fs_delete 工具读写。需要记住或查阅长期信息时主动使用。文件内容不会自动注入——需要看内容时用 fs_read 读取。

当前文件：
{{files}}{{fileContents}}
"""
```

### 验证
1. 编译通过
2. 让 Caelum 发"帮我记一下明天下午三点有会议" → 他应该调 fs_write 或 fs_append
3. 再让他发"帮我在刚才那个文件后面加一条：带笔记本" → 调 fs_append
4. Page 2 文件库里能看到新文件

---

## 第二波：心声系统 + 每日日记（灵魂功能）

### 2a. 记忆树只读映射

文件：`MemoryPalace/Services/FileLibraryStore.swift`

在文件末尾（`_selfCheck` 前）加记忆树支持：

```bash
# 参考粟粟的实现
cd /root/projects/SusuPalace
git show origin/master:MemoryPalace/Services/FileLibraryStore.swift | grep -A50 "MARK: - 记忆树"
```

核心：
```swift
// MARK: - 记忆树（只读）

static let memoryVirtualPrefix = "memory/"

static func memoryRoot(profileId: String) -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let dir = base.appendingPathComponent("MemoryPalace/memory/\(profileId)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

static func memoryList(profileId: String) -> [FileMeta] {
    // 类似 list()，扫描 memoryRoot 下所有 .md 文件，路径加 memory/ 前缀
}

static func memoryRead(_ virtualPath: String, profileId: String) throws -> String {
    // virtualPath 以 "memory/" 开头，映射到 memoryRoot
}
```

**FileLibraryTools.execute 加只读保护**：
```swift
// 在 execute 开头检查：memory/ 路径只许读，写一律拒
let pathArgs = ["path", "old_path", "new_path"].compactMap { args[$0] as? String }
if pathArgs.contains(where: { $0.hasPrefix("memory/") }) {
    if name != Name.read.rawValue && name != Name.list.rawValue && name != Name.search.rawValue {
        return Result(text: "memory/ 目录只读，不可修改", isError: true)
    }
}
```

**fs_list 输出也包含 memory/ 文件**：
```swift
case .list:
    var items = FileLibraryStore.list(profileId: profileId)
    items += FileLibraryStore.memoryList(profileId: profileId)
    return ok(items.isEmpty ? "（空文件库）" : items.map { ... }.joined(separator: "\n"))
```

### 2b. InnerVoice 心声系统

```bash
# 从粟粟复制
cp /root/projects/SusuPalace/MemoryPalace/Services/InnerVoice.swift \
   /root/projects/BunnyPalace/MemoryPalace/Services/
```

适配要点：
- InnerVoice 用了 `ToolDefinition`（Toolbase Phase 0 的类型）。如果我们有就直接用，没有就把工具定义改成跟 FileLibraryTools 一样的 dict 格式
- `MemoryFlags.masterEnabled` 如果我们没有，改成 `true` 或用 UserDefaults 开关
- 心声存到 `memory/heartvoice/{date}-{HHmm}.md`，走 `FileLibraryStore.memoryRoot`

**ToolCallLoop 注册心声工具**：
```swift
if call.name == InnerVoice.toolName {
    // 心声不返回数据给主对话，而是触发第二跳（reflection mode）
    // 简化版：直接生成心声文本存文件
    await InnerVoice.execute(reason: args["reason"] ?? "", profileId: profileId, context: context)
    outcomes.append(ToolOutcome(id: call.id, name: call.name, text: "（心声已记录）", isError: false))
    continue
}
```

**system prompt 注入心声工具**：在 PromptAssembler 里加 InnerVoice 的工具定义。

### 2c. HeartvoiceCardView 心声气泡

```bash
cp /root/projects/SusuPalace/MemoryPalace/Views/HeartvoiceCardView.swift \
   /root/projects/BunnyPalace/MemoryPalace/Views/
```

在 CardFlowView 的气泡渲染里，检查 node.contentType == "heartvoice"：
```swift
} else if node.contentType == "heartvoice" || node.content.hasPrefix("💭 心声\n\n") {
    HeartvoiceCardView(node: node)
}
```

### 2d. DailyFileStore 每日日记（可选，第二波做不完可以推后）

```bash
# 从粟粟复制 TimelineConsolidator 的日记部分
```

参考：
```bash
cd /root/projects/SusuPalace
git show origin/master:MemoryPalace/Services/TimelineConsolidator.swift | head -80
```

每天凌晨（或对话结束时）自动汇总当天对话生成日记 → 存到 `memory/daily/yyyy-MM-dd.md`。

---

## 第三波：文件库 UI 升级（参考粟粟 1544 行 PanelView）

这波改动大，建议看粟粟的 FileLibraryPanelView 然后增量改我们的 267 行版本：

```bash
cd /root/projects/SusuPalace
git show origin/master:MemoryPalace/Views/FileLibraryPanelView.swift | head -100
```

主要加：
1. **三种浏览模式**：列表（现有）/ 网格纸张卡片 / 树形目录
2. **内置 markdown 编辑器**：点击文件进入编辑态
3. **心声/日记专区 tab**：文件库顶部加 tab 切换「文件 | 日记 | 心声」
4. **新建文件按钮**
5. **上下文菜单**：重命名/删除/复制路径

---

## 通用红线

1. **不要碰 CLAUDE.md**
2. 第一波是存储层纯函数改动，零 UI 风险
3. 第二波的 InnerVoice 可能有依赖我们没有的类型，遇到就适配
4. 第三波 UI 改动最好先做个 branch
5. commit message：`feat(filelib): ...` / `feat(heartvoice): ...`
