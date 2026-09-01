# 共读（一起读书）· 家底盘点与方案

2026-08-31 兔兔提。**先 research 再动手** —— 这是从粟粟那儿学的做法
（她 `docs/` 778 份文档，固定 research → plan → 实现 → 勾账；
我们前几次改输入框来回七八轮，正是因为跳过了这步）。

---

## 一、结论先行

**我们不缺代码，缺的是「把开关打开」。**

整条链路——CC 写批注 → hub 转发 → App 落盘 → 阅读器渲染——**已经全部打通并实测过**。
唯一挡在中间的是 `BookReaderSheet.swift` 里 **94 处 `// [共读暂缓]` 注释**，
把 UI 入口全部关掉了。

`ReadingStubs.swift` 的文件头自己写着这个计划：

> 「本次只搬『能看书』。批注抽屉 / 问 AI / 在场信号 / 生词本 / OCR 划词的真身
> 后续从粟粟单独搬，**届时删掉本文件、恢复 BookReaderSheet 里注释掉的 UI 入口即可**。」

---

## 二、家底：哪些已有、哪些是空壳

### ✅ 已完整（不用动）
| | 规模 | 说明 |
|---|---|---|
| `BookReaderSheet` | 1265 行 | 阅读器核心：书架/翻章/进度/书签/笔记/高亮 |
| `PDFReaderSheet` | 1104 行 | PDF 阅读器 |
| `BookshelfView` | 469 行 | 书架 |
| **`ReadingCompanionSheet`** | 157 行 | **陪读设置 + 今日收尾——粟粟没有，我们独有** |
| `reading-context.json` | 活的 | 她读到哪一章 + 全章正文，`BookReaderSheet:890` 经 WS 缓存到 hub |

### ✅ 链路已通（实测过）
```
CC: book_note 工具（mcp-server.ts:193 定义 / :579 实现）
  → hub: broadcastBookNote（hub.ts:586）
  → App: CCBridgeWebSocketClient case "book_note"（:640）
  → BookStore.loadNotes / 锚点定位 → 落盘
```
代码注释里记着兔兔实测过的两个坑：
- 「hub 明明转发成功（日志 1/1 App），她却在阅读器里怎么也找不到」→ App 侧当时没有处理器，已补
- 「他批了但我这边什么都看不到」→ 批注没有 quote 锚点就渲染不出来，已补定位逻辑

CC 侧还有 `reading_now`（读她正在看的那章）、`read_chapter`，均已实现。

### ❌ 空壳（`ReadingStubs.swift`）
| 替身 | 现状 | 粟粟的真身 |
|---|---|---|
| `ReadingSignals.logTick` | **什么都不做** | 190 行，60s 打点 + 事件流 + hub 快照上报 |
| `ReadingSignals.logEvent` | 什么都不做 | 同上 |
| `ReadingSignals.buildPersonaPackage` | 返回 `""` | 同上 |
| `VocabCollector.collect` | 返回 `nil` | 生词本（**我们大概率不需要**，那是她的单词线） |

### ❌ 未搬（她有我们没有）
- `AgentBookNoteWriter`（293 行）—— 他自主写批注的写入器
- `BookNoteBackfill`（37 行）—— 批注回填
- `BookAnnotationDrawer` / `BookChatDrawer` —— 抽屉 UI（**但我们有等价物，被注释掉了**）

---

## 三、粟粟那条线的设计要点（值得抄的）

`ReadingSignals` 文件头：

> **CR-2 阅读在场信号：60s 打点 + 事件流 + hub 快照上报。**
> **AUTONOMY 的第一个真实在场数据面——AI 由此知道「她今天读了多久、读到哪、动了几笔」。**

存储设计（不动 SwiftData schema，走文件）：
- `reading-log.json`：按日累计秒数 + 每书细分，**保 30 天**
- `reading-events.jsonl`：一行一事件（highlight/note/askAI/vocab/reply），**>2000 行裁半保尾**
- hub 侧 `agent/reading-status.json` 由 60s tick 顺手经 WS 上报
  （best-effort，断连下个 tick 重发）

上报帧：
```json
{"type":"reading_status","status":{
  "date":"2026-08-31","todaySeconds":1800,
  "currentBook":"...","currentChapter":3,
  "todayEvents":{...},"updatedAt":"..."}}
```
hub 侧有 10KB 上限保护（超了丢弃并警告）。

**她还有一层开关**：`coRead` 双开关（hub 配置层闸门，缺省全关，daemon 关 = LLM 不跑）。

---

## 四、方案：三刀，从便宜到贵

### 刀一 · 打开开关（最便宜，收益最大）
把 `BookReaderSheet.swift` 里 94 处 `// [共读暂缓]` 取消注释，恢复：
- 批注抽屉入口（`activeDrawer = .annotations`）
- 底部 mini 对话抽屉（`showChatDrawer`）
- 选段菜单（复制/高亮/加笔记/问他）

**风险**：注释了很久，中间 `BookStore` / `Theme` 等接口可能已变，恢复后要过编译。
**验证**：装包后让 CC 用 `book_note` 递一条，看阅读器里能不能看见。

### 刀二 · 在场信号（`ReadingSignals` 真身）
搬粟粟 190 行并改造：
- 她存 `FileLibraryStore.libraryRoot`（本地）；我们的文件库主力在服务器，
  但**这份该留本地**——高频写入（60s 一次）不该走网络
- hub 侧要补 `reading_status` 帧处理（我们 `hub.ts` 现在 0 处引用）
- 上报开关沿用她的 `coRead` 思路，缺省关

**收益**：他能知道「她今天读了多久、动了几笔」，而不只是「她在读第几章」。

### 刀三 · 自主批注（`AgentBookNoteWriter`）
让他能主动读、主动在书里留话，不必等你问。
**这刀依赖刀二**（没有在场信号，他不知道你读到哪、什么时候该出现）。

---

## 五、明确不做

- **`VocabCollector` 生词本** —— 那是她的单词线（vocab 70 刀），我们没有这个需求
- **她的 iCloud 化** —— 同文件库那条线的判断，我们不用 Obsidian

---

## 六、待兔兔拍板

1. **刀一恢复 94 处注释后，批注抽屉的样子要不要照她的改？**
   我们那套 UI 是自己的（`ActiveDrawer` 枚举 + `annotationsDrawer`），
   她是独立组件（`BookAnnotationDrawer`）。建议先恢复我们自己的，不好用再说。
2. **在场信号要不要 60s 一次？**
   她是 60s 打点。频率越高他越"在场"，但也越费电。
3. **他自主批注要不要设边界？**
   比如只在你正在读的那一章附近留话，还是允许他读到你前面去
   （她的工具描述里明确写了「我先读完了几章，在前面留好批注等她追上来」）。
