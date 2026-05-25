# Research: iOS 点进对话卡顿根因审计

> 日期: 2026-04-13
> 范围: 只读审计，不改代码
> 目标: 找出 iOS 在侧边栏点进对话时，为什么会有明显卡顿

## 结论先说

这次卡顿不是一个点，而是 **4 段成本叠在一次点击里同时发生**：

1. `MessageNode` 按 `conversationId` 取节点时，底层 SQLite **没有索引**，会全表扫描。
2. 一次点开对话会做 **两次** `conversationId == convId` 查询：后台一次，主线程再一次。
3. 点击当下主线程还会同步做几件额外工作：记忆衰减、`lastOpenedAt` 写入、侧边栏刷新和重排。
4. iOS 聊天页首屏渲染本身也不轻：assistant 气泡会逐条做 thinking 正则提取 + Markdown 渲染，且切页动画、blur overlay 同时在跑。

所以体感上会像是“点一下，页面有一点绊住，再滑进聊天页”。

---

## 1. P0: `MessageNode.conversationId` 没索引，打开对话必扫整张消息表

### 代码位置

- `ConversationViewModel.loadConversation()` 入口  
  `MemoryPalace/ViewModels/ConversationViewModel.swift:49-76`
- 后台取当前对话全部节点  
  `MemoryPalace/ViewModels/ConversationViewModel.swift:84-88`
- 主线程再次 re-fetch 当前对话全部节点  
  `MemoryPalace/ViewModels/ConversationViewModel.swift:212-218`

### 证据

实际 SQLite schema：

```sql
CREATE TABLE ZMESSAGENODE (
  ...
  ZCONVERSATIONID VARCHAR,
  ZID VARCHAR,
  ...
);

CREATE UNIQUE INDEX Z_MessageNode_UNIQUE_id
ON ZMESSAGENODE (ZID COLLATE BINARY ASC);
```

`ZMESSAGENODE` 只有 `id` 唯一索引，没有 `conversationId` 索引。

查询计划：

```sql
EXPLAIN QUERY PLAN
SELECT Z_PK FROM ZMESSAGENODE WHERE ZCONVERSATIONID='test';
```

结果：

```text
SCAN ZMESSAGENODE
```

这说明按 `conversationId` 查节点时，SQLite 不会走索引，而是扫整张 `ZMESSAGENODE`。

### 为什么这会直接影响“点进对话”

因为当前加载链路里，打开一个对话不是“按主键拿一条记录”，而是“把这个会话的全部消息节点找出来，再构树”。  
而当前实现每次都用：

```swift
FetchDescriptor<MessageNode>(
    predicate: #Predicate<MessageNode> { node in node.conversationId == convId }
)
```

这在没有索引的情况下，底层成本更接近：

- 扫完整张消息表
- 找出属于这个 conversation 的节点
- 再把匹配结果组装回 SwiftData 对象

### 当前本机数据上的量级

我直接查了当前活跃 profile store（`A84ADA26-E056-4827-AD2A-A51AAA75C371.store`）：

- `ZMESSAGENODE`: **14,873**
- `ZCONVERSATION`: **254**
- 单个对话最大节点数: **594**
- 平均每对话节点数: **58.56**

也就是说，即便按当前这份较小的 store 算，一次打开对话也会至少扫 **14,873 条消息记录**。  
而项目文档里长期目标数据量是 **20 万+ MessageNode**，到那个量级时这个问题会被进一步放大。

---

## 2. P0: 一次打开对话，会对同一批节点做“两轮加载”

### 代码位置

- 后台线程第一轮 fetch  
  `MemoryPalace/ViewModels/ConversationViewModel.swift:80-205`
- 主线程第二轮 re-fetch  
  `MemoryPalace/ViewModels/ConversationViewModel.swift:208-250`

### 发生了什么

当前链路是：

1. 后台 `buildTreeInBackground()`  
   先把这个 conversation 的节点全部 fetch 出来，转成轻量 `NodeInfo`，构树、找 root、算当前路径。
2. 回主线程 `applyTreeData()`  
   再次 fetch 同一个 conversation 的所有 `MessageNode`，因为 UI 最终要拿 SwiftData 对象显示。

### 为什么 iOS 上体感更差

`performLoad` 被挪去后台这件事本身是对的，避免了“整段树构建都卡主线程”。  
但现在的瓶颈变成了：

- 后台先扫一次 `ZMESSAGENODE`
- 主线程再扫一次 `ZMESSAGENODE`

也就是一次点击至少两次按 `conversationId` 的全表扫描。  
这在 macOS 上可能还能扛，在 iPhone 上 CPU、内存带宽和 SwiftUI 首帧预算都更紧，卡顿更容易露出来。

### 这里要特别说明

这条不是说“后台线程没意义”。  
真正的问题是：**后台化之后，主线程仍然保留了一次重 fetch，而这次重 fetch 依旧是无索引扫描。**

---

## 3. P1: 点击当下，主线程还同步做了额外工作

### 代码位置

- `loadConversation()` 一进来就同步做：
  `MemoryPalace/ViewModels/ConversationViewModel.swift:49-64`
- 记忆衰减：
  `MemoryPalace/ViewModels/ConversationViewModel.swift:817-820`
- `applyDecay()`：
  `MemoryPalace/Services/MemoryService.swift:109-112`
- `listAll()`：
  `MemoryPalace/Services/MemoryService.swift:91-96`

### 具体有哪些同步动作

`loadConversation()` 不是一上来就扔后台，它先在主线程做了这些事：

1. `consolidateSessionMemories(profileId:context:)`
2. `selectedConversation = conversation`
3. `conversation.lastOpenedAt = Date()`
4. `sidebarRefreshTrigger += 1`
5. 清空 `currentPath` / `nodeMap` / `branchInfoMap`

其中第 1 条尤其值得警惕：

```swift
func consolidateSessionMemories(profileId: String, context: ModelContext) {
    guard !profileId.isEmpty else { return }
    try? memoryStore.applyDecay(profileId: profileId, context: context)
}
```

而 `applyDecay()` 会：

1. `listAll(profileId:)` 取该 profile 的全部 memory
2. 循环 apply decay
3. `context.save()`

也就是说，**每次只是“点开一个旧对话看看”时，主线程都会顺手做一次记忆系统的整批衰减和保存**。

### 为什么这条很像“点一下先顿一下”

因为这段工作发生在后台树构建启动之前。  
用户点击后，UI 线程先做一串同步 mutation / fetch / save，再开始真正的对话加载。  
这类阻塞在 iOS 上最容易表现成：

- 按下有反馈，但页面没立刻流畅切过去
- 动画开始了，但有轻微掉帧

---

## 4. P1: 侧边栏会因为这次点击立刻刷新、重排、重新查询

### 代码位置

- 点击会话行：
  `MemoryPalace/Views/SidebarView.swift:620-635`
- 监听 `sidebarRefreshTrigger`：
  `MemoryPalace/Views/SidebarView.swift:596-605`
- 刷新列表：
  `MemoryPalace/Views/SidebarView.swift:910-923`
- 默认排序：
  `MemoryPalace/Views/SidebarView.swift:993-1034`
- iOS 自动切到聊天页：
  `MemoryPalace/Views/ContentView.swift:193-197`

### 发生了什么

点击对话后：

1. `viewModel.loadConversation(...)`
2. `loadConversation()` 里把 `conversation.lastOpenedAt = Date()`
3. 同时 `sidebarRefreshTrigger += 1`
4. `SidebarView` 监听到 trigger，马上 `refreshList()`
5. `fetchPage(offset: 0)` 用 `lastOpenedAt DESC, updateTime DESC` 重取第一页

也就是说，一次点开会话，不只是聊天页在加载，**列表页自己也在立刻更新“最近打开”排序**。

### SQLite 证据

`ZCONVERSATION` 也只有 `id` 唯一索引，没有 `lastOpenedAt` 或 `updateTime` 索引。

查询计划：

```sql
EXPLAIN QUERY PLAN
SELECT Z_PK
FROM ZCONVERSATION
WHERE ZISDELETED=0
ORDER BY ZLASTOPENEDAT DESC, ZUPDATETIME DESC
LIMIT 100;
```

结果：

```text
SCAN ZCONVERSATION
USE TEMP B-TREE FOR ORDER BY
```

### 为什么 iOS 上更明显

iOS 这里不是 push 一个新页面，而是同一个 `TabView(.page)` 里：

- 第 0 页 `SidebarView` 仍然活着
- 第 1 页 `CardFlowView` 正在出现
- `selectedConversation` 一变，`ContentView` 还会 `withAnimation { iOSPage = 1 }`

所以一次点击里，至少有三件事并发发生：

- 列表刷新和重排
- 聊天页加载
- 页间动画

这会把原本“各自还行”的工作叠成一个明显的卡顿点。

---

## 5. P1: 聊天页首屏渲染本身就不轻，assistant 气泡尤其重

### 代码位置

- `BubbleView.body`
  `MemoryPalace/Views/CardFlowView.swift:557-650`
- 每个 bubble 里做清洗和 thinking 提取：
  `MemoryPalace/Views/CardFlowView.swift:574-576`
- `extractThinking()`：
  `MemoryPalace/Utils/ContentCleaner.swift:105-139`

### 这里的关键问题

assistant bubble 每次渲染都会做：

1. `ContentCleaner.clean(...)`
2. `ContentCleaner.extractThinking(...)`
3. `Markdown(displayText)`

其中 `extractThinking()` 当前实现是：

- 每次调用时创建 `NSRegularExpression`
- 对整段文本跑一遍 regex
- 找到所有 `[thinking]...[/thinking]`
- 再把正文复制一遍，删掉 thinking block

也就是说，它不是“偶尔做一次预处理”，而是 **放在 SwiftUI `body` 里，每个 assistant bubble 渲染都做一次**。

### 当前 store 的直接证据

我查了当前活跃 profile store：

- `assistant` 消息总数: **7,454**
- 含 `[thinking]` 的 assistant 消息: **7,289**

这说明 thinking block 在当前数据里不是边角情况，而是主流情况。  
因此这段 regex 成本并不是“小概率命中”，而是会覆盖绝大多数 assistant 消息。

### 为什么这会拖慢“点进对话”

虽然 `CardFlowView` 用了 `LazyVStack`，不会一次把 500 多条都真正画出来，这点是好的。  
但首屏能看到的那 8~20 条 bubble 里，只要 assistant 比例高，就会在首帧附近叠加：

- 文本清洗
- thinking regex
- Markdown 解析
- selectable text

这部分会让“加载完成后的第一帧”更重。

---

## 6. P2: iOS 页切换和 blur / glass 效果会放大卡顿观感

### 代码位置

- 自动切页：
  `MemoryPalace/Views/ContentView.swift:193-197`
- iOS 三页布局：
  `MemoryPalace/Views/ContentView.swift:119-205`
- 顶部 blur overlay：
  `MemoryPalace/Views/CardFlowView.swift:103-109`
- 底部输入条 blur 背景：
  `MemoryPalace/Views/CardFlowView.swift:130-136`

### 判断

这条我不认为是根因，但它会放大体感：

- `TabView(.page)` 切页本身有动画
- 顶部 `VariableBlurView`
- 底部输入栏 blur 背景
- 顶部按钮 `glassEffect`

如果 CPU 这时正忙着做数据库扫描、主线程同步工作和 bubble 首屏解析，那么 GPU/合成层这些效果就更容易表现成“切页不跟手”。

所以它更像是 **放大器**，不是起火点。

---

## 7. 这次审计里，哪些不是主要嫌疑

- `performLoad` 全部跑主线程  
  这条在旧版本是大问题，但当前代码已经把 fetch + 树计算拆到后台，不能再把这次卡顿主责甩给它。

- `LazyVStack` 不懒加载  
  当前 `CardFlowView` 确实用了 `LazyVStack`，不是“一次性创建所有 bubble”的问题。

- `chaseMissingAncestors` 全量 fetch 20 万节点  
  旧问题已修，现在是按缺失 ID 逐个查，不是这次的主因。

---

## 最终排序

### 最像根因的顺序

1. **`MessageNode.conversationId` 无索引，且一次打开对话会扫两遍消息表**
2. **点击当下主线程同步做记忆衰减 / save / 状态重置**
3. **侧边栏同步刷新、按最近打开重排，与聊天页切换动画叠在一起**
4. **assistant bubble 首屏 regex + Markdown 渲染过重**
5. **blur / glass / TabView page 动画放大了掉帧观感**

---

## 一句话判断

如果只问“为什么 iOS 点进对话卡”，我会给出的最短答案是：

**因为这次点击不是单纯导航，而是同时触发了无索引消息查询、二次节点加载、主线程记忆衰减、侧边栏重排和聊天页首屏 Markdown/regex 渲染。iOS 设备把这些重活叠在同一个交互瞬间，所以卡。**

---

## 附：本次只读核对过的关键文件

- `MemoryPalace/ViewModels/ConversationViewModel.swift`
- `MemoryPalace/Views/SidebarView.swift`
- `MemoryPalace/Views/ContentView.swift`
- `MemoryPalace/Views/CardFlowView.swift`
- `MemoryPalace/Utils/ContentCleaner.swift`
- `MemoryPalace/Services/MemoryService.swift`
- `MemoryPalace/Models/Conversation.swift`
- `project.yml`

## 附：`xcdocs` 交叉核对

用户补充了本机 `xcdocs` 路径：`/opt/homebrew/Cellar/xcdocs/0.1.0/bin/xcdocs`。  
我用它核对了 SwiftData 文档条目 `Preserving your app’s model data across launches: Customize the persistence behavior of model attributes`。

这个核对的意义不是“证明 conversationId 一定该有索引”，而是确认：

- SwiftData 属性行为需要显式声明
- `@Attribute(.unique)` 只明确表达唯一约束
- 结合本地 SQLite schema 实测，当前 `Conversation` / `MessageNode` 的查询字段确实没有落成数据库索引

所以这次关于“`conversationId` / `lastOpenedAt` 查询未命中索引”的结论，主要仍以 **本地 schema + query plan** 为准，`xcdocs` 只是补充语义，不是主证据。
