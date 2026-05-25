# Plan: Claude conversation.json 分段导入 + 交错渲染

**Research**: `docs/research-claude-conversation-blocks.md`（已批）
**分支**: `codex/theme-kelivo-settings`
**适用 provider**: 仅 `claude`（ChatGPT 本次不动）

---

## 粟粟拍板的 7 点设定（plan 按此实施）

1. `flag` kind **保留英文原文**（`self_harm_risk`），不翻译。
2. `tool_result` 默认展示 **2000 字**，带「展开全部」按钮。
3. `attachment[]` / `files[]` 暂时塞 **消息末尾** 作为独立段（不做专门的顶部附件区）。
4. ChatGPT importer **本次不改**，新字段对旧数据 nil → 走老渲染路径。
5. 搜索用的「扁平化 content」**继续维护**（搜索逻辑不动，importer 负责把 segments 压扁写入 `node.content`）。
6. 解析 `parent_message_uuid` 用作 `parentId`，**本次一并修**。
7. 搜索「是否匹配思考文字」做 **可筛选 toggle**（默认 ON —— 粟粟说经常靠小雾当时在想什么定位对话）。

### 5 的细节（之前没讲清）

`MessageNode.content: String` 是 SwiftData 里每条消息的「可搜索正文」，`SearchService` 的 SQL predicate 直接扫它。改 A2 结构化后，真正的显示数据走 `segmentsData`，但 `content` 继续装一份「扁平化文本」用于搜索、导出、API 回传。规则：

- text 段 → 原文追加
- thinking 段 → 原文追加（**可被第 7 点的 toggle 跳过搜索命中**，见下）
- tool_use 段 → `🔧 {name}` + input JSON 扁平（方便搜 tool 名）
- tool_result 段 → 结果纯文本
- flag / attachment / file → 可辨识的一行标签

第 7 点的实现：搜索 UI 多加一个「搜索思考内容」开关，OFF 时 predicate 用 regex / 标记位跳过 thinking 段。具体做法在 Phase 6 细化。

---

## 总体策略

**分 6 个 Phase，每个 Phase 收尾 build + push + 粟粟确认。** 每个 Phase 都能独立回滚。

- P1：数据模型（加字段，不动任何逻辑）
- P2：Importer v2（写 parse，不接入入口）
- P3：渲染（segments 走新 View，旧数据走老 View）
- P4：切换入口 + parent_message_uuid + 搜索扁平化
- P5：清数据 + 重导 + 肉眼验证
- P6：搜索 thinking 筛选 toggle

---

## Phase 1 — 数据模型（纯加字段，零风险）

**目标**：`MessageNode` 新增 `segmentsData: Data?`，不影响任何现有逻辑。

### Tasks
- [ ] P1.1 在 `Models/Conversation.swift` 的 `MessageNode` 加 `var segmentsData: Data?`（可选 → SwiftData 自动 migration，不用手工 plan）
- [ ] P1.2 新建 `Models/MessageSegment.swift`：
  ```swift
  enum MessageSegment: Codable, Hashable {
      case text(String)
      case thinking(String, signature: String?)
      case toolUse(id: String, name: String, inputJSON: String,
                   integrationName: String?, iconName: String?)
      case toolResult(toolUseId: String, text: String, isError: Bool,
                      integrationName: String?)
      case flag(kind: String, helplineName: String?,
                helplinePhone: String?, helplineUrl: String?)
      case attachment(name: String, type: String?, extractedContent: String?)
      case file(name: String, uuid: String)
  }
  ```
- [ ] P1.3 `MessageNode` 加 computed property：
  ```swift
  var segments: [MessageSegment]? {
      guard let d = segmentsData else { return nil }
      return try? JSONDecoder().decode([MessageSegment].self, from: d)
  }
  func setSegments(_ segs: [MessageSegment]) {
      self.segmentsData = try? JSONEncoder().encode(segs)
  }
  ```
- [ ] P1.4 `UnifiedContainerMigration.swift` 里**不需要手写 migration**（新可选字段 SwiftData auto）；但要确认其它 Schema 版本描述是否包含新字段。
- [ ] P1.5 `xcodegen generate && xcodebuild -scheme MemoryPalace build` 通过

**验收**：build 绿。app 启动不崩，老数据能正常打开（因为所有 `segmentsData == nil`，现有 UI 完全不受影响）。

---

## Phase 2 — Claude Importer v2（仅解析，不接入入口）

**目标**：写新的 parser，把 `ClaudeContentBlock[]` 转成 `[MessageSegment]`。完全独立函数，不替换现有 `extractContent`。

### Tasks
- [ ] P2.1 `ClaudeImporter.swift` 里新增私有方法 `extractSegments(from msg: ClaudeRawMessage) -> [MessageSegment]`：
  - 若 `msg.content` 非空 / 非 nil → 按 block 顺序映射（text/thinking/tool_use/tool_result/flag）
  - `msg.content` 为空/nil 时 fallback：若 `msg.text` 非空 → `[.text(msg.text)]`
  - 末尾追加 `attachments[]` → `.attachment(…)`
  - 末尾追加 `files[]` → `.file(…)`
- [ ] P2.2 扩展 `ClaudeContentBlock` 的 Codable 以读取新字段：
  - thinking：`signature`
  - tool_use：`integration_name`, `icon_name`
  - tool_result：`is_error`, `integration_name`
  - flag：`flag`, `helpline` 对象（独立 sub-struct）
- [ ] P2.3 新增 `flattenSegmentsForSearch(_ segs: [MessageSegment]) -> String`：
  - text → 原文
  - thinking → `<<<THINK>>>{text}<<</THINK>>>`（方便 P6 筛选 toggle 用 regex 剔除）
  - tool_use → `🔧 {name} {inputJSON}`
  - tool_result → 结果文本
  - flag → `⚠️ flag:{kind}`
  - attachment → `📎 {name}`
  - file → `🖼 {name}`
  - 用 `\n\n` 连接
- [ ] P2.4 单元 smoke：临时加一个 `#if DEBUG` 的命令行入口 / 临时按钮，parse 一条样本（比如 Notion 搜索那条），打印 segments + flattened，肉眼对比对不对。验完删掉。
- [ ] P2.5 build 通过

**验收**：build 绿。smoke 打印的 segments 顺序 == 原 json 顺序；flattened 文本无重复；thinking 签名保留。

---

## Phase 3 — 分段渲染 View（旧数据不变）

**目标**：assistant node 有 segments 时走新 View；无 segments 时走老路径。

### Tasks
- [ ] P3.1 新建 `Views/MessageSegmentsView.swift`：输入 `[MessageSegment]`，`ForEach` 渲染：
  - `.text` → `Markdown(text)` + theme
  - `.thinking` → 独立 `DisclosureGroup("思考")`（小字灰色，与现有样式一致，每段一个）
  - `.toolUse` + 紧邻的 `.toolResult`（预处理成 pair）→ 可展开 ToolCallCard（未展开：`🔧 {name}`；展开：input JSON + result 截断 2000 字 + 「展开全部」）
  - `.flag` → warning 小卡（`⚠️ {kind}` + 热线名 + 电话 + web chat url）
  - `.attachment` → `📎 {name}` + extracted_content 可展开
  - `.file` → `🖼 {name}`
- [ ] P3.2 ToolCall pairing：遍历 segments 时看到 `.toolUse` 就往后找最近一个 `tool_use_id` 匹配的 `.toolResult`；匹配上合并为一张卡；匹配不上各自独立显示（防御）。
- [ ] P3.3 `CardFlowView.swift` L1097 左右，在原有 `let thinkingResult = …` 之前加分支：
  ```swift
  if !isUser, let segs = node.segments, !segs.isEmpty {
      MessageSegmentsView(segments: segs, ...)
  } else {
      // 现有老逻辑（thinkingResult + Markdown）
  }
  ```
- [ ] P3.4 样式细节（对齐现有 UI）：
  - 思考块：`DisclosureGroup("思考")` 用当前 11pt muted 灰
  - 工具卡：圆角 8pt，背景 `Theme.mainBg.opacity(0.5)`，行高 22
  - flag 卡：warning amber（不用黄色主题，参考 CLAUDE.md —— **改用当前 muted 灰 + ⚠️ emoji**，不引入新色）
- [ ] P3.5 build 通过；用户消息和无 segments 的 assistant 消息外观**完全不变**
- [ ] P3.6 粟粟肉眼验证（P3 先不重导真数据，用 P2.4 smoke 里塞一条 segments 的假 node 看效果）

**验收**：build 绿。假的 segments node 能看到交错折叠；老对话一切如旧；无回归。

---

## Phase 4 — 切换 Claude 导入入口（会改变新导入的数据形态）

**目标**：`ClaudeImporter` 默认走 v2；新导入的 Claude 对话全部带 segments + 扁平化 content；parent_message_uuid 接入。

### Tasks
- [ ] P4.1 `ClaudeImporter.makePayload(from:)` 改写：
  - `nodes` 不再调用旧 `extractContent`，改调 `extractSegments` → segments
  - 通过 `flattenSegmentsForSearch` 生成 `content` 字符串（用于搜索）
  - `contentType = "segmented"`（新类型 tag，方便 migration 后未来判断）
- [ ] P4.2 `ImportedNodePayload` 结构增加 `segmentsData: Data?` 字段；`makeImportedNode` 写入到 `MessageNode.segmentsData`
- [ ] P4.3 parent_message_uuid：
  - `ClaudeRawMessage` Codable 加 `parent_message_uuid: String?`
  - nodes 构造时：`parentId = msg.parent_message_uuid` （为 null 时才用旧 index-1 fallback）
  - childrenIds：反向重建（遍历一遍 msgs，给每个 parent 的 childrenIds 追加 child.uuid）
- [ ] P4.4 `mergeImportFile` 分支同步走新路径
- [ ] P4.5 build 通过

**验收**：build 绿。不重导时老数据不动。

---

## Phase 5 — 清数据 + 重导 + 肉眼验证

**目标**：把粟粟本地 Claude provider 的对话删干净，重新导入，肉眼确认渲染 & 搜索都正常。

### Tasks
- [ ] P5.1 在设置页 / 导入历史里已有「按 importRecord 撤销」—— 逐条撤销所有 claude provider 的导入记录；**不够就** 手工 SQL：`DELETE FROM Conversation WHERE provider='claude' AND profileId=?` + 相应 MessageNode。先 dry-run 看 count。
- [ ] P5.2 粟粟执行清除（她亲手确认，不让我代替）
- [ ] P5.3 粟粟执行重导入（用 `/Users/susu/Downloads/.../conversations.json`）
- [ ] P5.4 抽查 10 条：
  - 必含至少 2 条 interleaved thinking（多段思考 + 多 tool call）
  - 必含至少 1 条带 `self_harm_risk` flag
  - 必含至少 1 条带 attachment `extracted_content`
  - 肉眼确认：**思考不重复**、**每段思考独立折叠**、**工具卡配对正确**、**flag 显示**
- [ ] P5.5 搜索抽查：
  - 搜一个在 thinking 里的词 → 能命中
  - 搜一个工具名（比如 `notion-search`）→ 能命中
  - 搜一个 text 里的词 → 能命中
- [ ] P5.6 commit & push

**验收**：粟粟点头，bug 主诉（重复思考 / 只有首段折叠）消失。

---

## Phase 6 — 搜索思考筛选 toggle（收尾）

**目标**：搜索 UI 多一个开关「搜索思考过程」。

### Tasks
- [ ] P6.1 `SearchService.swift` 的 fetch predicate 增加参数 `includeThinking: Bool`：
  - true：predicate 不变
  - false：改为 regex predicate 或先 fetch 再在内存里用 `<<<THINK>>>...<<</THINK>>>` 正则剔除后再判断命中（SwiftData predicate regex 能力有限，可能需要内存二次过滤，性能 ok 因为搜索 hit 本身数量不会太大）
- [ ] P6.2 搜索界面加 `Toggle("搜索思考", isOn: $includeThinking)`，默认 ON
- [ ] P6.3 搜索结果高亮时要跳过 `<<<THINK>>>` 标记字符本身
- [ ] P6.4 build + 粟粟体感

**验收**：toggle 生效；关掉后搜「粟粟」等常用词时命中数明显减少（因为思考里常提她的名字）。

---

## 注意事项 / 粟粟留意

- **UI 变动敏感**：P3 是唯一一次会明显改 assistant 消息长相的，前后对比先看假数据；**真导入前先让粟粟过一轮视觉**。
- **P5 删数据不可逆**（即使 supportsUndo，也建议先 commit / tag 一次）。
- **P6 可延后**：不影响主诉修复；如果 P5 验完粟粟累了，P6 下次单独做。
- **build 指令**：`xcodegen generate && xcodebuild -scheme MemoryPalace build`
- **每个 Phase 结束后 commit**：commit msg 按现有风格，例如 `feat(claude-import): P1 — MessageNode 加 segmentsData 字段`。

---

## 未覆盖的场景（明确不做）

- ChatGPT importer 同步改造 → **不做**
- `redacted_thinking` 类型 → 当前数据未出现（粟粟没 redacted 的），但 parser 里 default case 保留可扩展；渲染可下阶段加
- `server_tool_use` / `web_search_tool_result` 等 API server-side tool → 当前数据未出现
- tool 卡的 input JSON 语法高亮 / 折叠子树 → C3 的事，本次不做
- flag 的 amber/red 自定义配色 → 按 CLAUDE.md 不引入新色
- 搜索结果上下文预览里剔除 thinking → 本次只改命中判断，预览保持原状

---

## 请粟粟批注

- Phase 划分 OK？要不要合并 / 拆分？
- P3 样式细节（特别是 flag 卡样式、tool 卡配色）接受吗？
- P5 清除方式：走现有撤销 vs 直连 SQL DELETE，你倾向哪种？
- P6 是跟 P1-P5 一起做完，还是下次单独做？
