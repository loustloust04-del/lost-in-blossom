# 重复导入 / 叠加导入 Research

日期：2026-04-10

## 粟粟这次明确补充的目标语义

根据你补充的原始需求，这次要的不是“以新导出覆盖旧导出”，而是：

- 已导入的历史是一个 **本地全集**
- 新导出的 `conversation.json` 只是某个时点的 **官端快照**
- 官端快照里缺失的对话，不应在宫殿里被删除
- 同 id 的对话如果在新快照里变长了，宫殿里应该吸收这部分新增内容
- 导入后的结果应该是“本地已有全集 + 新快照新增/变长部分”的并集

用你给的例子翻成更精确的规则：

### 初始状态

- 1 月 1 日导入后，宫殿里有：`a b c`

### 之后发生的外部变化

- 官端里 `b` 被删了
- `a` 在官端继续聊了几句，变长了
- 新增了 `d`

### 1 月 15 日重新导出

官端导出的 `conversation.json` 变成：`a c d`

### 你期待的宫殿结果

重新导入后，宫殿应该变成：`a b c d`

其中：

- `b` 继续保留，因为它虽然不在新导出里，但它是宫殿本地已经有的历史
- `a` 应该更新成更长的新版本，而不是保留旧版本
- `c` 保持原样或按新快照刷新
- `d` 作为新增对话加入

### 这等价于什么产品语义

这不是：

- “和官端做严格同步”
- 也不是“新文件为准的镜像导入”

这实际上是：

- **append-preserving merge**
- 或者更口语一点：**保留本地全集的增量叠加导入**

### 由这个语义直接推出的关键约束

1. 新导出里缺失的对话不能删本地已有对话。
2. 对同 id 对话，不能只看“存在/不存在”，必须比较新旧版本谁更完整。
3. “更完整”至少要能覆盖你举的 `a` 继续聊了几句 这个场景。
4. 这种导入不是普通 append-only，因为它会更新已有对话。
5. 一旦会更新已有对话，导入历史的“撤回此次导入”语义就必须重新定义，不能再沿用现在的整批删除模型。

## 本轮范围

只研究 `MemoryPalace` 里现有的导入、重复导入、导入历史撤回语义，不做实现。

本轮深读的核心文件：

- `MemoryPalace/Models/Conversation.swift`
- `MemoryPalace/Models/Folder.swift`
- `MemoryPalace/Models/ImportRecord.swift`
- `MemoryPalace/Services/ConversationImporter.swift`
- `MemoryPalace/Services/ClaudeImporter.swift`
- `MemoryPalace/Views/ImportView.swift`
- `MemoryPalace/Views/ImportHistoryView.swift`
- `MemoryPalace/ViewModels/ConversationViewModel.swift`

另外，我用本机 `xcdocs` 核对了 Apple 的 SwiftData 文档：

- `/documentation/SwiftData/Maintaining-a-local-copy-of-server-data#Define-the-apps-data-model`
- `/documentation/SwiftData/Maintaining-a-local-copy-of-server-data#Insert-or-update-new-earthquake-data`

这两段文档确认了一个关键事实：`@Attribute(.unique)` 对应的不是“简单报重复”，而是 **insert + save 时按 unique 字段做 create-or-update**。这会直接改变我们对“普通重复导入”现状的判断。

## 结论先行

### 1. 现在的“普通导入”本身就已经是粗糙的 upsert

这不是一个“只有 Bitrig 新加的 merge mode 才会更新旧数据”的问题。

因为：

- `Conversation.id` 是 `@Attribute(.unique)`，见 `MemoryPalace/Models/Conversation.swift:5-24`
- `MessageNode.id` 也是 `@Attribute(.unique)`，见 `MemoryPalace/Models/Conversation.swift:36-68`
- `ConversationImporter.importFile` 每次都会重新 `insert` 同 id 的 `Conversation` / `MessageNode`，见 `MemoryPalace/Services/ConversationImporter.swift:20-118`
- `ClaudeImporter.importFile` 也是同样模式，见 `MemoryPalace/Services/ClaudeImporter.swift:22-145`

按 Apple 文档语义，这意味着：

- 首次导入：创建
- 再次导入同 id：更新现有对象的其它字段

所以，**现有系统已经允许“重复导入更新旧对象”发生，只是它没有被产品语义承认，也没有围绕这个行为做保护。**

### 2. 现在的导入历史撤回模型，和任何“更新已有对话”的导入语义都不兼容

当前撤回逻辑是：

- 只看 `Conversation.importBatchId`
- 找到这个 batch 下的所有 conversation
- 删除这些 conversation 的所有节点
- 删除这些 conversation
- 删除这条 `ImportRecord`

代码在 `MemoryPalace/Views/ImportHistoryView.swift:69-125`。

这套模型只适用于一种情况：

- “某次导入只新增，不更新任何历史对话”

一旦某次导入更新了旧对话，不管是：

- 现有普通重复导入触发的 unique upsert
- 还是 Bitrig 那版显式 merge

只要 `importBatchId` 被写成新 batch，这条旧对话就会在“撤回本次导入”时被整条删掉，而不是恢复到更新前状态。

这意味着：

- **当前系统的 batch undo 语义和“重复导入更新旧数据”天然冲突**
- 不是 merge mode 才有这个问题
- 普通重复导入已经有这个问题，只是目前 UI 没把它暴露出来

### 3. Bitrig 那版 merge 没有解决根问题，只是把“更新已有对话”做成了显式开关

Bitrig 增加的改动主要是：

- `ImportView` 增加 `mergeMode` toggle，见 `MemoryPalace/Views/ImportView.swift:4-11, 73-75, 514-518, 560-594`
- ChatGPT / Claude importer 各自增加 `mergeImportFile`，见：
  - `MemoryPalace/Services/ConversationImporter.swift:133-305`
  - `MemoryPalace/Services/ClaudeImporter.swift:147-320`

它做的不是新范式，而是把原本隐形存在的“更新已有对话”显式化了。

但它没有补：

- 更新前快照
- 字段级保留策略
- 节点级本地状态迁移
- 更新型导入的可逆语义
- 导入历史对“新增 / 更新 / 跳过”的准确表达

所以它不是完整解法。

## 现状细读

### A. 普通导入路径的真实行为

#### ChatGPT 普通导入

`ConversationImporter.importFile` 当前做法：

1. 读完整个 JSON
2. 建 `ImportRecord`
3. 每条对话直接 new 一个 `Conversation`
4. 给 `conversation.importBatchId = batchId`
5. 每个 node 直接 new 一个 `MessageNode`
6. 每 200 条 `save()`

代码位置：`MemoryPalace/Services/ConversationImporter.swift:20-118`

关键点：

- 它**不会先查本地是否已存在**
- 它**不会先清理旧节点**
- 它**也不会区分新增 / 更新**

在 SwiftData unique 语义下，这会变成：

- 已有 `Conversation.id` -> 更新 conversation
- 已有 `MessageNode.id` -> 更新 node
- 新的 id -> 新建
- 旧 store 里存在、但这次 JSON 里已经没了的 node -> **不会删**

也就是说，普通重复导入不是“安全忽略重复”，而是：

- 部分字段被新对象覆盖
- 缺失节点不会清
- batch 归属被重写

#### Claude 普通导入

`ClaudeImporter.importFile` 同样是这个模式，只是数据结构是线性的，代码在 `MemoryPalace/Services/ClaudeImporter.swift:22-145`。

本质问题完全相同。

### B. 普通重复导入会破坏哪些本地状态

#### Conversation 级状态会被重置

`Conversation` 上除了导入文件自带字段，还有这些**本地状态**：

- `isFavorite`
- `folderId`
- `lastOpenedAt`
- `isDeleted`
- `deletedAt`
- `importBatchId`

定义在 `MemoryPalace/Models/Conversation.swift:5-24`。

普通导入重新 new `Conversation(...)` 时，只显式传了：

- `id`
- `title`
- `createTime`
- `updateTime`
- `currentNodeId`
- `provider`（Claude 路径）

剩下这些本地字段都会回到默认值，然后被 SwiftData upsert 语义写回旧对象。

这意味着普通重复导入**很可能**会导致：

- 收藏整条对话被清掉
- 文件夹归属丢失
- `lastOpenedAt` 丢失
- 已放进回收站的对话被“复活”
- `importBatchId` 被写成最新 batch

#### MessageNode 级状态会被重置

`MessageNode` 上本地状态有：

- `isFavorite`
- `isDeleted`
- `deletedAt`

定义在 `MemoryPalace/Models/Conversation.swift:37-49`。

普通导入 new `MessageNode(...)` 时没有传这些字段，所以重复导入时它们也会回到默认值。

这意味着：

- 已收藏的单条气泡会失去 `node.isFavorite`
- 单条软删除状态会被清掉

#### `FavoriteItem` 不会自动一起同步

`FavoriteItem` 是独立模型，按 `conversationId` / `nodeId` 关联，定义在 `MemoryPalace/Models/Folder.swift:22-33`。

普通重复导入并不会清理它们。

所以会出现一种不一致：

- `FavoriteItem` 仍在
- 但对应 `MessageNode.isFavorite` 被重置为 `false`

也就是：

- 文件夹里的收藏项可能还在
- “节点自身是否已收藏”的状态却被导入覆盖掉了

#### 旧节点不会清理，树可能变脏

普通导入不会删掉 source 中已不存在的旧 node。

结果就是：

- 如果新导出比旧导出更完整：可能补进新节点
- 如果新导出比旧导出更短，或分支结构变了：旧节点会残留

这会让对话树逐步偏离导出源。

### C. Bitrig merge 路径的真实行为

#### ChatGPT merge

`ConversationImporter.mergeImportFile` 的逻辑是：

1. 全量取本地 `Conversation`
2. 用 `conversation.id -> nodeCount` 建索引
3. 新文件每条对话只算“可见消息数”
4. 若本地存在且 `newDisplayable > existingCount`
   - 删掉该 conversation 下全部旧 `MessageNode`
   - 更新 conversation 的少数字段
   - 重新插入新节点
5. 否则：
   - 同 id 且消息数不更多 -> skip
   - 不存在 -> 新建

代码位置：`MemoryPalace/Services/ConversationImporter.swift:133-305`

#### Claude merge

Claude 版本同理，代码在 `MemoryPalace/Services/ClaudeImporter.swift:147-320`。

### D. Bitrig merge 相比普通重复导入，改善了什么，新增了什么风险

#### 改善

它比普通重复导入好的地方，是它**不会把整个 `Conversation` 对象用默认值粗暴覆盖**。

因为它更新已有对话时，只手动改这些字段：

- `title`
- `updateTime`
- `currentNodeId`
- `nodeCount`
- `importBatchId`

见：

- `MemoryPalace/Services/ConversationImporter.swift:208-214`
- `MemoryPalace/Services/ClaudeImporter.swift:220-226`

所以 conversation 级本地状态：

- `isFavorite`
- `folderId`
- `lastOpenedAt`
- `isDeleted`
- `deletedAt`

**在 merge update 路径里反而更容易被保住。**

#### 新增风险 1：节点级本地状态还是会丢

因为它更新已有对话时会：

- 先删掉全部旧节点
- 再按导出文件重建全部节点

见：

- `MemoryPalace/Services/ConversationImporter.swift:200-235`
- `MemoryPalace/Services/ClaudeImporter.swift:211-250`

这意味着节点级本地状态依旧会丢：

- `isFavorite`
- `isDeleted`
- `deletedAt`

#### 新增风险 2：节点级字符串关联对象可能被悬挂

当前项目里与 node 的关联不是外键，而是字符串 id：

- `FavoriteItem.nodeId`
- `UserCard.attachedToNodeId`

定义在：

- `MemoryPalace/Models/Folder.swift:22-33`
- `MemoryPalace/Models/Conversation.swift:74-85`

merge update 删除全部旧节点再重建时：

- 如果新导出仍包含相同 node id，这些字符串引用还能重新对上
- 如果某个旧 node 在新导出里消失，这些字符串引用就会悬挂

所以 merge 路径相较普通重复导入，多了一个“**removed node 的关联悬挂**”风险。

#### 新增风险 3：比较规则太粗

merge 是否更新，当前只看：

- `displayableCount` 是否更大

见：

- `MemoryPalace/Services/ConversationImporter.swift:185-199`
- `MemoryPalace/Services/ClaudeImporter.swift:205-211`

这会漏掉很多真实更新：

- 消息数没变，但内容改了
- 标题改了
- 分支结构改了
- 系统/tool/thinking 节点变了
- 可见消息数相同，但 node id 集合不同

所以这条规则不是真正的“同步判断”，只是“消息数更多才替换”的启发式。

## 导入历史 / 撤回语义的系统性冲突

### 当前撤回模型是什么

当前 `undoImport` 的 truth source 只有：

- `ImportRecord.id`
- `Conversation.importBatchId`

流程见 `MemoryPalace/Views/ImportHistoryView.swift:69-125`。

它不关心：

- 这条 conversation 是不是这次新建的
- 还是这次只是更新了旧对象
- 更新前是什么样子

### 为什么这和重复导入冲突

不管是：

- 普通重复导入的 SwiftData upsert
- 还是 Bitrig merge 的显式 update

只要 `Conversation.importBatchId` 被改成最新 batch，这条旧 conversation 就会在“撤回此次导入”时被整条删掉。

这和产品文案“支持按批次撤回”并不一致。

当前产品文档里的承诺是：

- `记忆宫殿-这才是真的总设计文档！.md:116`

这里写的是：

- `ChatGPT/Claude 导入 | 后台线程导入，进度条，导入历史管理，支持按批次撤回`

这个承诺默认隐含的是“撤回后应回到导入前状态”，而不是“把曾经已有的数据也删掉”。

## UI / 文案层面的不一致

### 1. merge 开关描述过于乐观

当前 toggle 文案：

- `保留本地独有对话，相同对话取消息更多的版本`

见 `MemoryPalace/Views/ImportView.swift:514-518`

这句只描述了理想策略，没有暴露：

- 更新型导入会改写 batch 归属
- 撤回会误删旧对话
- 节点本地状态会丢
- 判断规则只看消息数

### 2. 完成态数字不准确

当前完成页直接展示：

- `已导入 X 条对话`

见：

- iOS: `MemoryPalace/Views/ImportView.swift:318-337`
- macOS: `MemoryPalace/Views/ImportView.swift:501-512`

但 `currentImportedCount` 实际取的是 importer 的 `importedCount`，而 importer 在 merge 模式里更新的是：

- `已处理 done / total`

见：

- `MemoryPalace/Services/ConversationImporter.swift:280-285`
- `MemoryPalace/Services/ClaudeImporter.swift:302-307`

所以 merge 完成后：

- UI 说“已导入 X 条”
- 实际这个 X 只是“输入文件里扫描了多少条”

这会误导用户。

## 第一性原理下，这个系统真正缺的是什么

如果一个导入系统要支持“重复导入 / 同步更新”，它必须先回答一个基础问题：

> 导入是 append-only，还是 sync/update？

现在代码同时踩了两条船：

- 普通导入的底层行为已经会 update
- 导入历史 / 撤回语义却还是 append-only 的设计
- Bitrig merge 又把 update 做得更显式，但没有把 undo / local state / 比较规则补齐

所以根本问题不是“要不要加 mergeMode”，而是：

### 真正的 truth source 应该先定成其中一种

#### 方向 A：导入只允许新增，不允许更新旧对象

那就必须：

- 明确阻止重复导入更新已有 conversation
- 或者把重复项直接 skip
- 保证 `importBatchId` 永远只属于“本次新增的 conversation”

这条路的优点是：

- 撤回模型天然成立
- 逻辑简单

缺点是：

- 不能拿新导出补老数据

#### 方向 B：导入支持同步更新

那就必须承认：

- `ImportRecord` 不能再只记录“这次有哪些 conversation 属于我”
- 还要记录“哪些是新建、哪些是更新、更新前是什么”

否则“撤回此次导入”在语义上永远是假的。

这条路需要至少补：

- created / updated / skipped 三类记录
- updated conversation 的 pre-import snapshot 或 patch
- 节点级本地状态迁移规则
- removed node 的关联清理或迁移规则

## 本轮研究后的判断

### 现在不适合直接收 Bitrig 那版 merge

不是因为它方向完全错，而是因为它只补了最表面的“比较并更新”，没有把 surrounding system 一起修好。

它至少还缺：

- update 型导入的可逆设计
- 节点本地状态迁移
- removed node 关联清理
- 更可靠的相等 / 新旧判断标准
- UI 文案与计数校正

### 甚至在写 plan 前，也要先承认一件事

**普通重复导入本身就已经不安全。**

所以后续 plan 不能只修 merge mode，而要把问题拆成两层：

1. 现有普通导入的重复导入语义到底要不要继续存在
2. 如果要支持“更新已有对话”，那导入历史和撤回要怎么重建

## 研究阶段建议的下一步（不是实现）

下一阶段 plan 应该先做决策，而不是直接写代码：

1. 先定产品语义：重复导入到底是 `skip duplicates` 还是 `sync existing conversations`
2. 如果选 `skip duplicates`：plan 要以“让撤回语义继续成立”为核心
3. 如果选 `sync existing conversations`：plan 要先设计 `ImportRecord` / rollback model，而不是先修 importer

当前阶段不建议：

- 直接把 Bitrig merge patch 原样收进来
- 或者只修一两个 bug 就上线

因为那样只会把“重复导入更新旧对象”这件事暴露得更明显，但不会让它真的安全。
