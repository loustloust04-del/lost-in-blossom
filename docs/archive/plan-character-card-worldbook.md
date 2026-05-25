# Plan: 角色卡导入 & 世界书（Phase 1）

> 基于：research-character-card-worldbook.md + 粟粟的架构决策文档 + 批注
> 日期：2026-04-13

---

## 目标

1. 新建楼层时可以导入 TavernCard（JSON 或 PNG），自动填充 Profile 字段 + 创建对话
2. 角色卡自带的世界书一并导入，在 PromptAssembler 中动态注入
3. 右栏新增世界书 tab，查看条目 + 开关

---

## Task Checklist

### 阶段 A：数据模型

- [ ] **A1** 新建 `Models/WorldBook.swift`
  - `WorldBook`：SwiftData `@Model`，字段：id, name, entries (JSON encoded [WorldBookEntry]), profileId, createdAt, updatedAt
  - `WorldBookEntry`：普通 Codable struct（不是 @Model，作为 WorldBook 的 JSON 字段存储），字段见架构文档第四节
  - 注意：entries 存为 JSON Data 而不是 SwiftData relationship，因为条目数量不大（通常 < 50），且避免 SwiftData 嵌套模型的复杂性

- [ ] **A2** Profile 加三个字段
  - `characterCardID: String?` — 来源角色卡标识（角色名，用于显示）
  - `linkedWorldBookIDs: [String]` — 绑定的世界书 UUID 列表
  - `coverImageData: Data?` — 封面图（PNG 卡的原图数据）
  - 修改 `init()` 加默认值，不影响现有楼层

- [ ] **A3** `project.yml` 加新文件引用（如果需要），xcodegen generate 验证编译

### 阶段 B：角色卡解析器

- [ ] **B1** 新建 `Services/TavernCardParser.swift` — `TavernCard` 中间模型
  - 纯数据 struct，不依赖 SwiftData
  - 字段清单：
    ```
    name: String
    description: String
    personality: String
    scenario: String
    firstMes: String
    alternateGreetings: [String]
    mesExample: String
    systemPrompt: String
    postHistoryInstructions: String
    creatorNotes: String
    characterBookName: String?
    characterBookEntries: [[String: Any]]   // 原始 JSON 字典数组，留给 WorldBookEntry(from:index:) 解析
    imageData: Data?                         // PNG 卡时保存原图
    ```

- [ ] **B2** `TavernCard.parseJSON(data: Data) throws -> TavernCard`
  - JSON 结构：顶层有 V2 字段 + `data` 对象有 V3 字段，内容相同
  - 解析策略：优先读 `data.*`，fallback 顶层（兼容纯 V2 卡没有 `data` 的情况）
  - `data.character_book.entries` → `characterBookEntries`
  - `data.character_book.name` → `characterBookName`
  - `data.alternate_greetings` → `alternateGreetings`（顶层没有这个字段）
  - `data.system_prompt` → `systemPrompt`（顶层没有）
  - `data.post_history_instructions` → `postHistoryInstructions`（顶层没有）
  - `data.creator_notes` → `creatorNotes`（顶层是 `creatorcomment`，两个都试）

- [ ] **B3** `TavernCard.parsePNG(data: Data) throws -> TavernCard`
  - PNG 二进制手动解析（不用第三方库）：
    1. 验证 8-byte PNG signature: `[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]`
    2. 从 offset 8 开始遍历 chunk：
       - 读 4 bytes → chunk data length (big-endian UInt32)
       - 读 4 bytes → chunk type (ASCII string)
       - 读 length bytes → chunk data
       - 跳 4 bytes CRC
    3. 找 tEXt chunk (type == "tEXt")：
       - data 格式：keyword (null-terminated) + text
       - 优先找 keyword == "ccv3"（V3），没有则找 "chara"（V2）
    4. text 部分 base64 decode → JSON data → 调用 `parseJSON()`
    5. 原始 PNG data 整体保存为 `imageData`

- [ ] **B4** `TavernCard.parseFile(url: URL) throws -> TavernCard`
  - 根据文件扩展名选择解析方式：
    - `.json` → `parseJSON()`
    - `.png` → `parsePNG()`
    - 其他 → throw 错误
  - 从 URL 读取 Data

- [ ] **B5** build 验证（xcodegen + xcodebuild）

### 阶段 C：角色卡导入流程

- [ ] **C1** `ProfileEditorSheet` 加"导入角色卡"按钮
  - 位置：在现有"新建楼层" sheet 的表单顶部，加一个按钮
  - 按钮样式：带图标的 capsule，文字"导入角色卡"
  - 点击 → `fileImporter` 打开文件选择器
  - 允许格式：`.json` + `.png`（UTType: .json, .png）
  - 新增 `@State` 变量：
    - `importedCard: TavernCard?` — 解析成功的卡
    - `importError: String?` — 解析失败的错误信息
    - `showFileImporter: Bool`

- [ ] **C2** 文件选择回调 → 解析 + 自动填充表单
  - `fileImporter` 的 `onCompletion` 里：
    1. `url.startAccessingSecurityScopedResource()` （沙盒权限）
    2. `TavernCard.parseFile(url:)` 解析
    3. 解析成功 → 填充现有 `@State` 变量：
       ```
       name = card.name
       assistantName = card.name
       emoji = "🎭"（默认，用户可改）
       description = card.name + "的楼层"
       characterDescription ← 新增 @State，存 card.description
       characterPersonality ← 新增 @State，存 card.personality
       scenario ← 新增 @State，存 card.scenario
       chatExamples ← 新增 @State，存 card.mesExample
       systemPrompt = card.systemPrompt
       postInstructions ← 新增 @State，存 card.postHistoryInstructions
       ```
    4. 保存 `importedCard = card`（后续 save() 用）
    5. `url.stopAccessingSecurityScopedResource()`
  - 解析失败 → `importError = error.localizedDescription`，显示 alert

- [ ] **C3** 修改 `save()` 函数 — 创建 Profile 时带角色卡字段
  - 现有 `save()` 只传基础字段（name, emoji, description, userName, assistantName, systemPrompt, preferredModel）
  - 改为也传 `characterDescription`, `characterPersonality`, `scenario`, `chatExamples`, `postInstructions`
  - 如果有 `importedCard`：
    - `characterCardID = card.name`
    - `coverImageData = card.imageData`

- [ ] **C4** 导入后自动创建对话（在 save() 里，profile 创建完成后）
  - 需要拿到新楼层的 `ModelContainer` 来操作 SwiftData
  - `profileManager.addProfile()` 会 `switchTo()` 新楼层 → `container` 已切换
  - 用 `profileManager.container` 创建 `ModelContext`
  - first_mes → 创建 Conversation（title = card.name），插入 assistant MessageNode
  - alternate_greetings → 每条创建 Conversation（title = "card.name #N"），各插入 assistant MessageNode
  - 每个 Conversation 的 `currentNodeId` 指向该 assistant node
  - **注意**：这一步必须在 `profileManager.addProfile()` 之后，因为需要新楼层的 container

- [ ] **C5** 世界书随卡导入（在 C4 同一位置）
  - 如果 `importedCard.hasWorldBook`：
    1. 构造 `[WorldBookEntry]`：遍历 `card.characterBookEntries`，用 `WorldBookEntry(from:index:)`
    2. 创建 `WorldBook(name:profileId:entries:)`
    3. 用 `ModelContext` insert WorldBook
    4. 更新 profile：`linkedWorldBookIDs = [worldBook.id.uuidString]`
    5. `profileManager.updateProfile()`

- [ ] **C6** build 验证 + 用柚木凪.json 手动冒烟测试

### 阶段 D：世界书注入引擎

- [ ] **D1** 新建 `Services/WorldBookScanner.swift`
  - `struct ResolvedEntry`：命中的条目快照
    - `content: String` — 注入内容（已宏替换）
    - `position: WorldBookEntry.InsertionPosition`
    - `depth: Int`
    - `insertionOrder: Int`
    - `role: String` — 注入 role（默认 "system"）
  - `static func scan(worldBooks:recentMessages:profile:tokenBudget:) -> [ResolvedEntry]`
  - 逻辑步骤：
    1. 收集所有 worldBook 的 entries，过滤 `isEnabled == false`
    2. 分两组：constant（直接命中）+ keyword（需匹配）
    3. keyword 组：拼接 recentMessages 为 scanText，遍历条目做关键词匹配
       - 主关键词：任一出现在 scanText 中 → 主词命中
       - caseSensitive=false 时转 lowercased 比较
       - matchWholeWords 时用 `\b` word boundary 正则
       - 主词命中后检查 selectiveLogic + secondaryKeys
    4. probability 过滤：`Int.random(in: 1...100) <= entry.probability`
    5. 合并 constant + 命中的 keyword 条目，按 insertionOrder 排序
    6. token 预算控制（默认 2048）：按序累加 token，超预算截断
    7. 对每个命中条目的 content 做 `{{user}}` / `{{char}}` 宏替换
    8. 返回 `[ResolvedEntry]`

- [ ] **D2** 修改 `PromptAssembler.assemble()` 接入世界书
  - 函数签名加 `worldBooks: [WorldBook] = []`（不影响现有调用）
  - 在 slot for 循环结束后，调用 `WorldBookScanner.scan()`
    - recentMessages = trimmedHistory.map { $0.content }
    - profile = profile
  - 当前 systemParts 是平铺数组，没有标记哪个是 charDescription —— 需要改造：
    - 改为用 tagged 数组 `[(tag: String, content: String)]` 追踪每个 part 的来源 slot id
    - 世界书 beforeCharDef → 插到 charDescriptionId 之前
    - 世界书 afterCharDef → 插到 charDescriptionId 之后
    - 世界书 beforeExamples/afterExamples → 插到 preHistoryMessages 的对话示例前/后
    - 世界书 atDepth → 加入 postHistoryInjections
    - 世界书 authorNoteTop/Bot → 插到 jailbreakId 之前/之后
  - 最后 tagged 数组 `.map { $0.content }` 拼接成 systemPrompt

- [ ] **D3** 修改 ChatService 调用链传入 worldBooks
  - 找到所有调用 `PromptAssembler.assemble()` 的地方
  - 从 SwiftData `ModelContext` 查询当前 profile 的 WorldBook
    - `FetchDescriptor<WorldBook>` where `profileId == profile.id`
  - 传入 assemble()
  - 同时修改 `PromptAssembler.preview()` 也接收 worldBooks

- [ ] **D4** build 验证

### 阶段 E：右栏世界书 Tab

- [ ] **E1** `RightPanelTab` 枚举加 `.worldBook`
  - `MemoryPanelView.swift` 的 `RightPanelTab` enum 加 `.worldBook` case
  - tab 按钮栏加"世界书"按钮（icon: "book.closed"）
  - `panelContent` switch 加 `.worldBook` → `WorldBookPanelView(profileId:)`
  - `profileId` 从 `viewModel` 或 environment 取

- [ ] **E2** 新建 `Views/WorldBookPanelView.swift`
  - 接收 `profileId: String`
  - 用 `@Query` 查询 `WorldBook` where `profileId == profileId`
    - 注意：@Query 不支持动态 predicate，改用 `@Environment(\.modelContext)` + 手动 fetch
  - 没有世界书 → 空状态：icon + "此楼层没有世界书" 文字
  - 有世界书 → 显示：
    - 顶部：世界书名称 + 条目数统计
    - 条目列表（ScrollView + LazyVStack）：
      - 每行：Toggle 开关 + 条目 comment/关键词摘要
      - constant 条目显示"常驻"capsule 标签
      - 点击展开 → 显示完整 content（只读 Text）
      - keys 用 HStack + capsule 小标签展示
  - Toggle 改动 → 更新 WorldBook.entries → save context
  - 样式跟 MemoryPanelView 保持一致（字体、间距、颜色）

- [ ] **E3** build 验证

### 阶段 F：验证

- [ ] **F1** 代码审查：检查所有改动文件的一致性
  - Profile 新字段有默认值，不影响现有楼层
  - WorldBook schema 已注册
  - PromptAssembler 的 worldBooks 参数有默认值，不影响现有调用
  - 世界书 Tab 在右栏可见
  - 导入按钮只在"新建楼层"模式出现

- [ ] **F2** build + commit + push

---

## 不做（Phase 1 明确排除）

- 角色卡库独立浏览界面
- 世界书库独立管理界面
- 世界书条目编辑（改关键词/内容/位置）
- 全局世界书
- 正则关键词匹配（use_regex）
- 正则脚本（regex_scripts）
- sticky/cooldown/delay
- group 互斥逻辑
- PNG 封面图在侧边栏展示（只存储，暂不展示）

---

## 文件变更清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `Models/WorldBook.swift` | 新建 | WorldBook @Model + WorldBookEntry Codable |
| `Services/TavernCardParser.swift` | 新建 | JSON/PNG 解析器 |
| `Services/WorldBookScanner.swift` | 新建 | 关键词扫描 + 注入位置解析 |
| `Views/WorldBookPanelView.swift` | 新建 | 右栏世界书 tab UI |
| `MemoryPalaceApp.swift` | 修改 | Profile 加字段 + ProfileEditorSheet 加导入按钮 |
| `Services/PromptAssembler.swift` | 修改 | assemble() 加 worldBooks 参数 + 注入逻辑 |
| `Views/MemoryPanelView.swift` | 修改 | RightPanelTab 加 .worldBook |
| `project.yml` | 修改 | 如需加新文件引用 |
| 调用 assemble() 的地方 | 修改 | 传入 worldBooks 参数 |
