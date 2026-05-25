# Research: 高级搜索 (Advanced Search / Query)

## 目标

在现有关键词搜索基础上，增加高级搜索能力：
- 指定时间范围
- 指定角色（用户/助手/系统）
- 关键词搜索（现有）
- 语义搜索（AI 理解意图）
- 组合查询（多条件 AND）

---

## 现状分析

### 当前搜索实现

**位置**: `SidebarView.swift:706-793`

**流程**:
1. 用户输入关键词 → `localizedStandardContains()` 模糊匹配
2. 第一轮：搜标题（Conversation.title）
3. 第二轮：搜内容（MessageNode.content，仅 user/assistant）
4. 按 conversationId 分组 → 显示折叠列表
5. 排序选项：最近/最旧/标题 A-Z/Z-A

**能力边界**:
- ✅ 关键词模糊匹配（大小写不敏感）
- ✅ 结果按对话分组
- ✅ 上下文预览（~80 字符）
- ❌ 不能按时间筛选
- ❌ 不能按角色筛选（硬编码 user/assistant）
- ❌ 不能语义搜索
- ❌ 不能多条件组合
- ❌ 搜索在主线程，20 万条 fullscan 可能卡

### 数据模型字段（可搜索的）

**Conversation**:
| 字段 | 类型 | 搜索用途 |
|------|------|---------|
| `title` | String | 标题搜索 |
| `createTime` | Date | 时间范围 |
| `updateTime` | Date | 时间范围 |
| `provider` | String | 来源筛选 |
| `isFavorite` | Bool | 收藏筛选 |

**MessageNode**:
| 字段 | 类型 | 搜索用途 |
|------|------|---------|
| `content` | String | 内容搜索 |
| `role` | String | 角色筛选（user/assistant/system/tool）|
| `createTime` | Date? | 时间范围 |
| `conversationId` | String | 限定对话 |
| `contentType` | String | 内容类型筛选 |

**Memory**:
| 字段 | 类型 | 搜索用途 |
|------|------|---------|
| `content` | String | 记忆内容 |
| `category` | String | 分类筛选 |
| `keywords` | [String] | BM25 关键词（已提取但未用）|
| `embeddingData` | Data? | 向量（预留，未实现）|

### 已有的日期浏览

`CalendarPanelView.swift` — 右侧日历面板，按日期浏览对话。
但这是**浏览**而非搜索，不支持关键词+日期组合。

### 性能约束

- **20 万+ MessageNode**，禁止无条件全量 fetch
- `localizedStandardContains()` 无索引，fullscan
- 搜索当前在主线程
- 无 SQLite FTS（全文搜索索引）
- `ContentCleaner.clean()` 有 NSCache，已用 node.id 做 cacheKey

---

## 技术方案分析

### 方案 A: SwiftData #Predicate 组合查询（推荐先做）

**原理**: 在现有 `#Predicate` 基础上加条件

```swift
#Predicate<MessageNode> { node in
    node.isDeleted == false &&
    node.role == targetRole &&           // 角色筛选
    node.createTime >= startDate &&       // 时间起
    node.createTime <= endDate &&         // 时间止
    node.content.localizedStandardContains(keyword)  // 关键词
}
```

**优点**: 
- 零依赖，纯 SwiftData
- 时间/角色筛选可以利用 SQLite 索引（如果加了）大幅缩小 fullscan 范围
- 实现简单，一周内可上线

**缺点**:
- 关键词部分仍然是 fullscan
- `#Predicate` 不支持动态条件组合（编译时确定），需要为不同组合写多个 predicate 或用 workaround
- 无语义理解

**`#Predicate` 动态组合的技术难点**:
SwiftData 的 `#Predicate` 是编译时宏，不像 Core Data 的 `NSPredicate` 可以运行时拼接。
解决方案：
1. 写多个预定义 predicate 覆盖常见组合
2. 用 Foundation.Predicate 的 `conjunction` / `disjunction` API（Swift 5.10+）
3. 在 fetch 后做内存过滤（时间/角色先用 predicate 缩范围，关键词在内存匹配）

### 方案 B: SQLite FTS5 全文搜索

**原理**: 直接操作 SwiftData 底层的 SQLite 文件，创建 FTS5 虚拟表

```sql
CREATE VIRTUAL TABLE message_fts USING fts5(content, conversationId, role);
INSERT INTO message_fts SELECT content, conversationId, role FROM ZMESSAGENODE;
```

**优点**:
- 专业级全文搜索，支持 AND/OR/NOT/短语/前缀
- 性能极好（FTS5 是 SQLite 内置，毫秒级）
- 支持 BM25 排名

**缺点**:
- 需要直接操作 SQLite 文件，绕过 SwiftData
- 需要维护 FTS 索引同步（新消息/删除时更新）
- 中文分词需要额外处理（FTS5 默认按空格分词）
- 复杂度较高

### 方案 C: NLContextualEmbedding 语义搜索（远期）

**原理**: Apple 的 NLContextualEmbedding（macOS 15+）生成本地向量，余弦相似度排序

**优点**:
- 本地运行，不需要 API 调用
- 理解语义（"开心的对话" 能匹配"我今天很高兴"）
- Memory 模型已预留 `embeddingData` 字段

**缺点**:
- 需要 macOS 15+（当前 target 是 14+）
- 20 万条消息的向量化需要大量时间和存储
- 需要 sqlite-vec 或类似库做向量检索
- 实现复杂度最高

### 方案 D: AI 辅助搜索（调用 LLM 做 query 理解）

**原理**: 用户输入自然语言 → LLM 解析为结构化查询 → 执行

```
用户: "上个月和小雾讨论编程的对话"
→ LLM 解析: { dateRange: "2026-03-01..2026-03-31", keyword: "编程", role: "assistant" }
→ 执行结构化查询
```

**优点**:
- 用户体验最自然
- 可以理解模糊描述

**缺点**:
- 需要 API 调用（延迟 + 费用）
- 解析可能出错
- 离线不可用

---

## 推荐路线

### Phase 1: 结构化高级搜索（方案 A）— 先做这个
- 搜索栏下方加筛选条件：时间范围、角色、排序
- 把搜索移到后台线程
- 加 SwiftData 索引（`createTime`, `conversationId`）
- UI: 可折叠的筛选面板

### Phase 2: SQLite FTS5（方案 B）— 如果关键词搜索性能不够再加
- 建 FTS5 索引，中文用 ICU tokenizer
- 支持 AND/OR/NOT 布尔查询
- BM25 排名

### Phase 3: 语义搜索（方案 C + D）— 远期
- NLContextualEmbedding 向量化
- 或 LLM query 理解 + 结构化查询

---

## UI 设计思路

### 搜索入口
当前搜索栏保持，输入时展开高级筛选面板：

```
┌─────────────────────────────────┐
│ 🔍 搜索关键词...            [⚙] │  ← 齿轮图标展开高级选项
├─────────────────────────────────┤
│ 时间: [全部 ▾] 或 [自定义...]   │
│ 角色: [全部] [你] [小雾]        │
│ 排序: [最近 ▾]                  │
│ [搜索]                          │
└─────────────────────────────────┘
```

### 时间预设
- 全部时间
- 今天
- 最近 7 天
- 最近 30 天
- 最近 90 天
- 自定义范围（两个日期选择器）

### 角色筛选
- 全部（默认）
- 你（user）
- 小雾（assistant）
- 系统（system — 通常隐藏，高级模式可选）

### 搜索结果增强
- 匹配高亮（关键词变色）
- 显示消息时间
- 显示角色标签
- 结果计数

---

## 关键文件清单

| 文件 | 改动 |
|------|------|
| `SidebarView.swift` | 搜索 UI + 筛选面板 |
| `Conversation.swift` | 加索引 annotation |
| `ConversationViewModel.swift` | 后台搜索逻辑 |
| 新文件 `SearchService.swift` | 搜索引擎（独立出来） |

---

## 风险和约束

1. **`#Predicate` 动态组合**: 需要验证 Swift 5.10 的 Predicate conjunction API 是否能在 SwiftData 中工作
2. **20 万条 fullscan**: 加了时间范围后范围大幅缩小，但纯关键词搜索仍然慢
3. **UI 复杂度**: 高级筛选面板不能太重，要折叠/展开
4. **SwiftData 索引**: `@Attribute(.index)` 可能需要数据库迁移
5. **后台线程搜索**: SwiftData ModelContext 不是线程安全的，需要新建 context

---

## 待确认

1. Phase 1 范围是否 OK？先做结构化筛选（时间+角色+关键词），语义搜索放后面
2. UI 风格：筛选面板是内嵌在侧边栏，还是弹 popover？
3. 是否需要搜索 Memory（记忆库）的内容？
4. 是否需要保存搜索历史/常用查询？
