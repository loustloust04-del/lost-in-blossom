# Research: 竞品搜索实现分析 — QithMiao & Kelivo

对比两个同类项目的搜索功能实现，为记忆宫殿的搜索迭代提供参考。

---

## QithMiao（启思喵喵）

**项目**: ChatGPT 对话查看器，纯前端 SPA（Vanilla JS + IndexedDB）
**定位**: 导入 ChatGPT JSON，浏览/搜索/分析对话

### 搜索架构

**双模式搜索**：
- **当前对话搜索**: 只在当前打开的对话内搜索，`Array.filter()` + `includes()` 子串匹配
- **全局搜索**: 遍历所有对话的所有消息，同样是子串匹配，结果按对话分组

```
用户输入 → [当前对话] or [全部对话] 切换
         ↓
     substring includes (case-insensitive)
         ↓
     结果分组 + preview 生成 + 关键词高亮
```

### 亮点：关键词高亮

**纯文本高亮**: regex 替换为 `<span class="highlight">`

**HTML 内高亮**（值得学习）:
- 用 `TreeWalker` API 遍历 DOM 文本节点
- 只在文本节点内做替换，不破坏 HTML 标签
- 用 `<mark class="kw-highlight">` 包裹匹配词
- 这意味着 Markdown 渲染后的内容也能安全高亮

### 亮点：中文分词 + 词云

- 自带词典 `dict/words.json`
- **正向最大匹配**算法分词（Forward Maximum Matching）
- 停用词过滤（~140 个中文停用词）
- 词云支持多维筛选：对话/日期/角色/语言
- 用户可以手动拉黑特定词

### 搜索结果导航

- `flatSearchResults[]` 扁平数组 + 上一个/下一个按钮
- `scrollToMessage(msgId)` 滚动到目标消息 + 3 秒高亮闪烁
- 全局搜索 → 点击结果 → 打开对话 → 定位到消息 → 保持高亮关键词
- 分页支持：消息超过 2000 条时按需加载，搜索导航会预加载目标位置

### 我们能借鉴的

| 功能 | QithMiao 做法 | 记忆宫殿现状 | 建议 |
|------|-------------|------------|------|
| **关键词高亮** | TreeWalker DOM 高亮 | 只有预览文字，气泡内无高亮 | **Phase 1.5**: 在 MarkdownUI 渲染后加高亮层 |
| **搜索模式切换** | 当前对话 / 全局 | 只有全局 | 可加"当前对话内搜索" |
| **结果导航** | 上一个/下一个按钮 | 无 | 加导航条 |
| **中文分词** | 正向最大匹配 | 无 | 远期词云/语义搜索可用 |
| **消息高亮闪烁** | 3 秒 CSS 高亮 | 无 | scroll 到目标后闪烁一下 |

---

## Kelivo

**项目**: 跨平台 LLM 聊天客户端（Flutter/Dart，支持 iOS/Android/macOS/Windows/Linux/Web）
**定位**: 多 provider 聊天 + 内置 web 搜索 + 对话管理

### 搜索架构：两层

**Layer 1: 外部 Web 搜索（13 个 provider）**
- Tavily、Exa、Perplexity、Brave、DuckDuckGo、Bing、Jina、SearXNG、Zhipu、LinkUp、Metaso、Ollama、Bocha
- 通过 LLM function calling 调用（`search_web` tool）
- 抽象基类 `SearchService<T>` + provider 工厂
- 连接测试、超时配置、结果数量控制
- 高级筛选：域名过滤（Perplexity）、时效性过滤（Bocha: week/month）、国家/语言过滤

**Layer 2: 本地对话搜索**（`GlobalSessionSearchService`）

```
用户输入 → 分词（空格拆分）→ 遍历所有对话
                              ↓
                         标题匹配: +30 分/token
                         内容匹配: +10 分/token
                              ↓
                         按得分排序 → 取前 200 条
                              ↓
                         生成 snippet（110-180 字符）
                              ↓
                         token 高亮渲染
```

### 亮点：评分算法

```dart
// 伪代码
score = 0
for token in queryTokens:
    titleMatchCount = title.countOccurrences(token)
    score += titleMatchCount * 30    // 标题权重高
    
    contentMatchCount = body.countOccurrences(token)
    score += contentMatchCount * 10  // 内容权重低

// 排序: 先按分数降序，同分按更新时间降序
results.sort(by: score DESC, updatedAt DESC)
```

比记忆宫殿的纯子串匹配好——标题匹配权重更高，多个关键词各自独立计分。

### 亮点：Snippet 生成

- 最小 110 字符，最大 180 字符
- 第一个匹配 token 定位在可见区域的 45% 位置（大约在 3 行 snippet 的第 2 行）
- 左右扩展到消息边界或字符上限
- 截断处加 `...`

比记忆宫殿的固定 80 字符 + 关键词前 30 字符更智能。

### 亮点：隐藏内容过滤

搜索前过滤掉 LLM 的思考过程：
- `<!-- gemini_thought_signatures:... -->` 
- `<think>...</think>`
- `<reasoning>...</reasoning>`

防止内部推理出现在搜索结果里。

### 亮点：版本感知

对话有多个消息版本（regenerate 产生的分支）时：
- 按 `groupId` 分组
- 尊重 `versionSelections` 选择用户选中的版本
- 未选择则取最新版本

这和记忆宫殿的分支系统类似，但 Kelivo 在搜索时主动处理了版本问题。

### 亮点：Desktop 搜索 UI

- 实时搜索（打字即搜，无需按 Enter）
- 结果数量标签："找到 X 个对话"
- hover 高亮（10% primary color）+ 选中高亮（16% primary color）
- Token 级别高亮（金色背景），标题和 snippet 都高亮
- Mobile 支持滑动切换搜索/浏览模式

### 我们能借鉴的

| 功能 | Kelivo 做法 | 记忆宫殿现状 | 建议 |
|------|-----------|------------|------|
| **评分排序** | 标题 30 分 + 内容 10 分 | 无评分，标题匹配优先但无分数 | **值得加**: 简单评分让结果更相关 |
| **实时搜索** | 打字即搜 | 按 Enter 触发 | 可选：debounce 300ms 实时搜 |
| **智能 snippet** | 110-180 字符，token 居中 45% | 固定 80 字符，关键词前 30 | **值得加**: 更好的预览体验 |
| **Token 高亮** | 标题+snippet 金色高亮 | 无高亮 | **值得加**: 至少 snippet 里高亮 |
| **隐藏内容过滤** | 过滤 think/reasoning 标签 | 无 | 如果接了会思考的模型需要加 |
| **版本/分支感知** | 搜索时选正确版本 | 搜索不管分支 | 中期：搜索结果标注是否在分支上 |
| **Web 搜索集成** | 13 个 provider + LLM tool | 无 | 远期考虑 |
| **连接测试** | 每个 provider 可测试 | 无 | API 管理 UI 重做时加 |

---

## 对记忆宫殿的建议优先级

### 近期（Phase 1.5，基于当前高级搜索）

1. **搜索结果 snippet 高亮** — 关键词用不同颜色标记，QithMiao 和 Kelivo 都做了
2. **目标气泡闪烁** — scroll 到位后闪烁 2-3 秒，QithMiao 的做法
3. **评分排序** — 标题匹配 +30，内容匹配 +10，比纯时间排序更有用
4. **更智能的 snippet** — 扩大到 120-180 字符，关键词居中

### 中期（Phase 2）

5. **当前对话内搜索** — QithMiao 的双模式，在聊天界面加搜索框
6. **过滤 think/reasoning 标签** — Kelivo 的做法，防止思考过程出现在结果里
7. **搜索结果上/下导航** — QithMiao 的 flatSearchResults + prev/next

### 远期（Phase 3）

8. **中文分词 + 词云** — QithMiao 的正向最大匹配，或 Apple 的 NLTokenizer
9. **MarkdownUI 内关键词高亮** — 需要在渲染后的 AttributedString 里注入高亮
10. **Web 搜索集成** — Kelivo 的 13 provider 架构，作为 MCP tool
