# Research: 角色卡导入 & 世界书

> 研究目标：搞清楚怎么在记忆宫殿里实现 TavernCard 导入和世界书注入
> 基于：粟粟的架构决策文档 + 实例卡（柚木凪.json）+ SillyTavern 源码 + 现有代码
> 日期：2026-04-13

---

## 一、实例卡分析（柚木凪.json）

实际拿到的卡是 `chara_card_v3`（spec_version: "3.0"），不是 V2。但数据结构向下兼容——顶层字段和 `data` 内部字段重复存在（V2 读顶层，V3 读 `data`），我们统一读 `data`。

### 卡的实际内容

| 字段 | 内容 |
|------|------|
| `name` | "柚木凪"（3 chars） |
| `description` | 3917 chars，包含完整角色设定（XML 结构化） |
| `personality` | **空** |
| `scenario` | **空** |
| `first_mes` | 566 chars，含作者信息 + catbox 图片链接 + 角色简介 |
| `mes_example` | **空** |
| `system_prompt` | **空** |
| `post_history_instructions` | **空** |
| `creator_notes` | **空** |
| `alternate_greetings` | **10 条**替代开场白 |
| `extensions.world` | "宝宝就是宝宝呀，宝宝只需要被宠爱"（世界书名称） |
| `extensions.regex_scripts` | 1 个正则脚本（状态栏 HTML 渲染）——**本阶段不实现** |
| `character_book` | 内嵌世界书，8 个条目 |

**关键发现**：很多卡把所有内容塞进 `description`，其他字段留空。`personality`/`scenario`/`mes_example` 为空是常见情况，不能假设这些字段一定有值。

### 世界书条目实际结构

```
Entry 完整字段：
├── id: Int（序号，0-based）
├── keys: [String]                    # 主关键词
├── secondary_keys: [String]          # 次关键词
├── comment: String                   # 条目备注
├── content: String                   # 注入内容
├── constant: Bool                    # 常驻注入（跳过关键词匹配）
├── selective: Bool                   # 是否使用次关键词逻辑
├── insertion_order: Int              # 排序权重
├── enabled: Bool
├── position: String                  # 遗留字段："before_char" / "after_char"
├── use_regex: Bool                   # 关键词是否用正则（本阶段不实现）
└── extensions:
    ├── position: Int                 # 实际位置（覆盖 position 字符串）
    ├── depth: Int                    # atDepth 时的深度
    ├── selectiveLogic: Int           # 次关键词逻辑
    ├── probability: Int              # 触发概率 0-100
    ├── useProbability: Bool
    ├── scan_depth: Int?              # 扫描深度（nil=全局默认）
    ├── match_whole_words: Bool?      # 全词匹配
    ├── case_sensitive: Bool?         # 大小写敏感
    ├── group: String                 # 分组
    ├── group_weight: Int             # 分组权重
    ├── role: Int                     # 0=system, 1=user, 2=assistant
    ├── sticky: Int                   # 粘滞（触发后保持N轮）
    ├── cooldown: Int                 # 冷却（触发后N轮不再触发）
    ├── delay: Int                    # 延迟（匹配后等N轮才触发）
    └── ...其他（vectorized, automation_id 等，不实现）
```

### 位置映射（酒馆 → 记忆宫殿）

酒馆的 `extensions.position` 数值含义：

| 数值 | 酒馆常量 | 含义 | 记忆宫殿对应 |
|------|---------|------|-------------|
| 0 | before | 角色描述之前 | `beforeCharDef` |
| 1 | after | 角色描述之后 | `afterCharDef` |
| 2 | ANTop | Author's Note 区块顶部 | `authorNote`（顶部） |
| 3 | ANBottom | Author's Note 区块底部 | `authorNote`（底部） |
| 4 | atDepth | 对话历史中指定深度 | `atDepth` + `depth` 字段 |
| 5 | EMTop | 对话示例之前 | `beforeExamples` |
| 6 | EMBottom | 对话示例之后 | `afterExamples` |

**柚木凪这张卡的 8 个条目**：
- 2 个 `constant: true`（常驻注入，跳过关键词）：position 0 和 1
- 5 个普通条目：position 1（after_char），关键词触发
- 1 个常驻 `insertion_order: 9999`（状态栏输出指导），position 0

### selectiveLogic 映射

| 数值 | 酒馆常量 | 含义 |
|------|---------|------|
| 0 | AND_ANY | 主词命中 AND 至少一个次词命中 |
| 1 | NOT_ALL | 主词命中 AND 非全部次词命中 |
| 2 | NOT_ANY | 主词命中 AND 无次词命中 |
| 3 | AND_ALL | 主词命中 AND 全部次词命中 |

---

## 二、现有代码基础

### 已经有的（直接可用）

1. **Profile 的角色卡字段**：`characterDescription`、`characterPersonality`、`scenario`、`chatExamples`、`postInstructions`、`userPersona`、`systemPrompt` —— 和 TavernCard 字段**一一对应**

2. **PromptAssembler 的 marker slot 系统**：
   - `charDescriptionId` → description + personality
   - `scenarioId` → scenario
   - `dialogueExamplesId` → mes_example
   - `jailbreakId` → post_history_instructions
   - `mainId` → system_prompt
   - 宏替换 `{{user}}` / `{{char}}` 已实现

3. **Settings > Prompt tab**：已有 "simple" 模式展示角色卡字段的编辑表单

4. **SillyTavern JSON 预设导入/导出**：`Preset.swift` 里已有（不过这是预设导入，不是角色卡导入）

5. **右侧面板**：`MemoryPanelView.swift` 已有 `.calendar` 和 `.memory` tab，加 `.worldBook` tab 是自然扩展

### 需要新建的

1. **TavernCard 解析器**：
   - JSON 解析（本例是 .json 文件，直接 parse）
   - PNG 解析（从 tEXt chunk 提取 base64 JSON，key="chara" 或 "ccv3"）
   - V2/V3 兼容：优先读 `data.*`，fallback 读顶层

2. **WorldBook + WorldBookEntry 数据模型**：SwiftData `@Model`，架构文档第四节已定义

3. **世界书注入逻辑**：在 PromptAssembler 里加关键词扫描 + 内容注入

4. **世界书 UI**：右栏新 tab，条目列表 + 编辑器

5. **新建楼层流程改造**：加"从角色卡导入"选项

---

## 三、角色卡字段 → Profile 字段映射

```
TavernCard data.*          →  Profile 字段                →  PromptSlot marker
─────────────────────────────────────────────────────────────────────────────
name                       →  profile.name / assistantName  →  (楼层名 + AI名)
description                →  profile.characterDescription  →  charDescriptionId
personality                →  profile.characterPersonality  →  charPersonalityId（合并到描述末尾）
scenario                   →  profile.scenario              →  scenarioId
first_mes                  →  对话的第一条 assistant 消息    →  不进 prompt
alternate_greetings        →  选择器（用户选一条作为 first_mes）→ 不进 prompt
mes_example                →  profile.chatExamples          →  dialogueExamplesId
system_prompt              →  profile.systemPrompt          →  mainId
post_history_instructions  →  profile.postInstructions      →  jailbreakId
creator_notes              →  UI 显示，不进 prompt
character_book             →  WorldBook 实例，绑定到楼层
extensions.world           →  世界书名称（用于关联）
```

**已有字段完全够用**，不需要在 Profile 上加新字段。只需加：
- `characterCardID: UUID?` — 记录来源卡（可选）
- `linkedWorldBookIDs: [UUID]` — 绑定的世界书
- `coverImagePath: String?` — 封面图（PNG 卡的原图）

---

## 四、世界书注入点分析

### 现有 PromptAssembler 流程

```
1. contextDepth 截断 chatHistory
2. 过滤 + 排序 slots（by injectionOrder）
3. 遍历 slots → resolveSlotContent()
   ├── marker slot → 从 profile 取值，宏替换
   ├── static slot → 直接用 content
   └── chatHistoryId → skip
4. injectionDepth > 0 的 slot → 插入 messages 对应深度
5. 拼接 systemPrompt + messages
```

### 世界书注入应该插在第 3 步和第 4 步之间

```
3.5 世界书注入：
    a. 收集激活的世界书（全局 + 当前楼层绑定的）
    b. 取最近 N 条消息文本（scanDepth，默认 10）
    c. 遍历所有 enabled 条目：
       - constant=true → 直接命中
       - 否则 → 关键词匹配（主词 + selectiveLogic + 次词）
    d. 命中条目按 insertion_order 排序
    e. 按 position 插入：
       - beforeCharDef/afterCharDef → 插入 system prompt 的角色描述前/后
       - beforeExamples/afterExamples → 插入对话示例前/后
       - atDepth → 插入 messages 指定深度
       - authorNote → 和 jailbreak 同位置
    f. Token 预算控制（默认 2048）
```

这和记忆注入（`memoryInjectionId` marker slot）是平级的，但世界书更复杂——它不是固定位置注入，而是按条目各自的 position 分散注入。

---

## 五、PNG 解析方案

PNG 格式的角色卡需要特殊解析：

```
PNG 文件结构：
├── 8-byte signature: 89 50 4E 47 0D 0A 1A 0A
├── IHDR chunk
├── ...
├── tEXt chunk (keyword="chara", data=base64 JSON)  ← V2
├── tEXt chunk (keyword="ccv3", data=base64 JSON)   ← V3 (优先)
├── ...
└── IEND chunk
```

Swift 实现要点：
- 手动解析 PNG chunk（不需要第三方库，PNG chunk 格式简单）
- 每个 chunk：4 bytes length + 4 bytes type + data + 4 bytes CRC
- 找到 tEXt chunk → 读 keyword（null-terminated）→ 取 data → base64 decode → JSON parse
- 优先找 "ccv3" key，没有则 fallback "chara"
- PNG 图片本身保存为楼层封面

---

## 六、实现范围（Phase 1）

### 做

- [x] TavernCard V2/V3 JSON 解析
- [x] TavernCard PNG 解析（tEXt chunk 提取）
- [x] 角色卡字段 → Profile 字段映射 + 填充
- [x] first_mes + alternate_greetings → 新对话首条消息（选择器）
- [x] WorldBook + WorldBookEntry SwiftData 模型
- [x] 世界书关键词扫描 + PromptAssembler 注入
- [x] 世界书 token 预算控制
- [x] 右栏世界书 tab（条目列表 + 开关 + 简单编辑）
- [x] 新建楼层时选择"从角色卡导入"
- [x] `{{user}}` / `{{char}}` 宏替换（已有，确保世界书内容也替换）
- [x] Profile 加 linkedWorldBookIDs、characterCardID、coverImagePath

### 不做

- 角色卡库（Phase 1 先支持直接导入到楼层，不做独立库浏览）
- 世界书库独立管理界面（Phase 1 世界书跟随角色卡导入，右栏可查看编辑）
- 正则脚本（regex_scripts）
- 世界书条目的 sticky/cooldown/delay
- 世界书条目的 group 互斥逻辑
- 世界书条目的 use_regex（正则关键词匹配）
- 全局世界书（Phase 1 只有楼层绑定的世界书）
- 角色卡在线市场

---

## 七、待确认

1. **新建楼层入口**：现在新建楼层的 UI 长什么样？是在侧边栏还是设置里？我需要看一下才能决定在哪加"从角色卡导入"按钮。【在设置里。楼层管理UI还没做】

2. **右栏 tab 设计**：右栏现在有 calendar 和 memory，加 worldBook tab 后的 tab 排列？世界书 tab 里条目列表的交互（展开/折叠？搜索？）【反正在日历记忆边上，世界书交互先完全学习酒馆】

3. **alternate_greetings 选择器**：导入角色卡新建楼层时，10 条开场白怎么选？弹窗选择？还是默认用 first_mes，后续可切换？【开场白变成10个已有对话框放在左栏对话历史里，】

4. **世界书条目编辑的深度**：Phase 1 要支持到什么程度？只读查看 + 开关？还是完整编辑（改关键词、改内容、改位置）？【先最简单的来】
