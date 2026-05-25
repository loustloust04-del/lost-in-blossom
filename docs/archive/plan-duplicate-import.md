# 重复导入 / 叠加导入 Plan

日期：2026-04-10

对应 research：

- `docs/research-duplicate-import.md`

状态：已实施

## 目标

把“重复导入 / 叠加导入”收拢成一套明确、诚实、可撤回的产品语义。

这次要达成的是：

- 普通导入回到 **append-only**
- 叠加导入成为 **保留本地全集的增量叠加导入**
- 导入历史对“新增 / 更新 / 跳过 / 撤回”说真话

用你确认过的语义翻译成系统行为：

- 宫殿本地数据是历史全集
- 新导出的 `conversation.json` 只是某个时点的官端快照
- 新快照里缺失的对话，不删除宫殿本地已有对话
- 同 id 对话如果新快照更完整，宫殿吸收新增内容
- 新快照里的全新对话直接加入

## 范围

范围只包括：

- `ConversationImporter` / `ClaudeImporter` 的重复导入与叠加导入逻辑
- `ImportRecord` 及导入历史的撤回 truth source
- `ImportView` / `ImportHistoryView` 的模式文案、结果文案、撤回可用性

明确不包括：

- 官端双向同步
- “以官端为准”的镜像删除
- 搜索、侧边栏、对话浏览 UI 改版
- 旧历史记录的批量修复或补录快照

## 前置假设

这次先按下面这组假设落地，作为 truth source：

- 对话级别：官端新快照里缺失的 conversation，不视为删除指令
- 节点级别：叠加导入时也不把“新快照里缺失的旧 node”当成删除指令
- 撤回语义：撤回某次叠加导入，目标是“恢复到该次导入前状态”，不是和之后的手动编辑再做二次 merge

如果后面要支持“镜像同步”或“官端删除也删除本地”，那是另一条需求，不在这次 plan 里。

## 架构决策

### 1. 普通导入重新收回到 append-only

`importFile` 不再依赖 SwiftData 的 unique upsert 作为隐式行为。

这条路径改成：

- 本地不存在的 conversation：创建
- 本地已存在的 conversation：整条跳过
- 不覆盖任何已有 conversation / node 的本地状态

这样做的目的不是保守，而是把产品语义和代码行为重新对齐：

- 普通导入 = 新增
- 叠加导入 = 更新

### 2. 叠加导入是唯一允许“更新已有对话”的入口

只有显式打开“叠加导入”时，系统才允许：

- 更新已有 `Conversation`
- 更新已有 `MessageNode`
- 为已有对话补进新节点

普通导入不再偷偷更新旧对象。

### 3. 本地全集是 merge 的真相来源

叠加导入不做删除，只做：

- 新 conversation 插入
- 已有 conversation 的增量补充
- 同 id 节点的字段刷新

不会做：

- 因为新快照缺失就删除本地 conversation
- 因为新快照缺失就删除本地 node

### 4. 更新判断不能只看消息数

是否更新同 id 对话，不能继续只看 `nodeCount` / “可见消息数”。

新的判断要拆成两层：

- 第一层：conversation 级快速筛查
  - `updateTime`
  - `currentNodeId`
  - `nodeCount`
  - 标题
- 第二层：节点级精确比较
  - node id 集合
  - 同 id node 的关键字段是否变化
  - 结果树的 displayable 计数是否变化

只有这样才能覆盖：

- 消息数没变但内容变了
- 标题改了
- `currentNodeId` 变了
- 分支结构变了
- 新增节点但可见消息数刚好没变

### 5. 撤回不再以 `importBatchId` 为 truth source

`importBatchId` 不能继续承担“更新型导入撤回”的 truth source。

新的 truth source 应改成：

- `ImportRecord`
- `ImportConversationChange`（新模型）
- 每条变更对应的导入前快照

也就是说，撤回时要知道：

- 哪些 conversation 是这次新建的
- 哪些 conversation 是这次更新的
- 更新前长什么样

而不是只知道“现在谁身上挂着这个 batch id”。

### 6. 新导入和旧导入分开对待

旧记录没有 change log，系统并不知道它们是否真的可安全撤回。

所以这次要明确区分：

- 新格式记录：有完整 change log，可安全撤回
- 旧格式记录：保留展示，但不再假装“可安全撤回”

这一步的目标是诚实，不是假装兼容。

## 数据层计划

### 1. 扩展 `ImportRecord`

在现有 `ImportRecord` 基础上补齐导入模式和结果统计，至少包括：

- `mode`
  - `normal`
  - `merge`
- `supportsUndo`
- `addedConversationCount`
- `updatedConversationCount`
- `skippedConversationCount`

现有的：

- `conversationCount`
- `nodeCount`

继续保留，但要重新定义为“本次实际落库产生的结果统计”，不能再混用“已处理条数”。

### 2. 新增 `ImportConversationChange`

新增一张按 conversation 粒度记录的变更表，用来支撑撤回。

建议字段：

- `id`
- `recordId`
- `conversationId`
- `changeKind`
  - `created`
  - `updated`
- `beforeConversationData`
- `beforeNodesData`

设计原则：

- 只给 `created` / `updated` 记变更
- `skipped` 只记统计，不逐条落 change 记录
- `before*` 只对 `updated` 存快照

### 3. 新增快照结构体

在 model 之外增加可 `Codable` 的 snapshot struct，用来编码 / 解码导入前状态。

至少需要：

- `ConversationSnapshot`
- `MessageNodeSnapshot`

快照字段只保留“恢复导入前状态”真正需要的内容，不把整个 SwiftData model 原样塞进去。

重点要覆盖的字段：

- `Conversation`
  - `title`
  - `createTime`
  - `updateTime`
  - `currentNodeId`
  - `provider`
  - `nodeCount`
  - `isFavorite`
  - `folderId`
  - `lastOpenedAt`
  - `isDeleted`
  - `deletedAt`
  - `importBatchId`
- `MessageNode`
  - `id`
  - `role`
  - `content`
  - `contentType`
  - `createTime`
  - `parentId`
  - `childrenIds`
  - `conversationId`
  - `isFavorite`
  - `isDeleted`
  - `deletedAt`

## 实施步骤

### 1. 先把普通导入从“隐式 upsert”改成真正的 append-only

这一部分先做，是为了堵住现有系统已经存在的隐性风险。

`ConversationImporter.importFile` 和 `ClaudeImporter.importFile` 统一改成：

- 预取本地已有 conversation id 集合
- 文件里遇到重复 id 直接跳过
- 只为真正新建的 conversation / node 落库
- `importedCount` 从“处理数”改成“新增数”，另起 `processedCount`

影响：

- 普通重复导入不再重置 `folderId` / `isFavorite` / `isDeleted`
- 普通导入的 batch undo 再次成立

### 2. 给两种 importer 补“导入摘要”与“比较器”

不要把 ChatGPT / Claude 抽成大而泛的统一框架，但两边要对齐同一套判断语义。

每个 importer 内各自补两个小层次：

- `ImportedConversationSummary`
- `shouldMerge(existing:incoming:)`

比较规则按下面的顺序判断：

1. 本地不存在：`created`
2. 本地存在，但 incoming 明显带来新 node / 新内容 / 新 metadata：`updated`
3. incoming 不比本地更完整，也没有新信息：`skipped`

具体比较信号至少包含：

- `updateTime`
- `currentNodeId`
- `title`
- total node id 集合
- displayable node id / count
- 同 id node 的关键字段差异

注意：

- 任何节点比较都必须按 `conversationId` 定向 fetch
- 不允许为了比较而全量 fetch `MessageNode`

### 3. 叠加导入改成“增量 merge”，不再删光旧节点重建

对 `updated` conversation，新的 merge 行为应改成：

- 先抓该 conversation 的导入前快照
- 再按 node id 做增量处理

规则是：

- 同 id node：更新字段，但保留本地状态字段
- 新 node：插入
- 本地独有旧 node：保留，不删除
- 最终 `Conversation.nodeCount` 用合并后的结果重新计算

conversation 级字段更新时，也要区分：

- 来自导出文件的字段：可以刷新
- 本地状态字段：保留导入前值

这一步的目标是同时解决：

- 节点级收藏 / 软删除丢失
- conversation 级本地状态被覆盖
- 新快照更短时的历史丢失

### 4. 在导入时同步写 change log

无论普通导入还是叠加导入，新格式记录都统一走 change log。

规则建议是：

- 普通导入
  - 新建 conversation：写 `created`
  - 跳过：只记统计
- 叠加导入
  - 新建 conversation：写 `created`
  - 更新 conversation：写 `updated + before snapshot`
  - 跳过：只记统计

这样可以把“新增型撤回”和“更新型撤回”统一到同一套 undo 流程里，避免一半靠 `importBatchId`、一半靠 snapshot。

### 5. 重写 `ImportHistoryView` 的撤回逻辑

撤回逻辑改成按 `ImportConversationChange` 回放，而不是按 `importBatchId` 粗删。

目标行为：

- `created`
  - 删除这次新建的 conversation
  - 删除该 conversation 的 node
  - 清理相关 `FavoriteItem`
  - 清理附着在这些 node 上的 `UserCard`
- `updated`
  - 恢复导入前的 conversation snapshot
  - 恢复导入前的 node 集合
  - 清理这次导入才出现、但快照里不存在的 node
  - 清理因此失效的 `FavoriteItem` / `UserCard`

这一步的语义要明说：

- 新格式撤回 = 回到“这次导入前”
- 旧格式记录 = 只展示，不提供“安全撤回”

### 6. 收紧 UI 文案和统计

`ImportView` 和 `ImportHistoryView` 都要把文案收紧，避免继续误导。

具体要改：

- `mergeMode` 文案从“消息更多的版本”改成“保留本地全集的叠加导入”
- 结果页不再只显示“已导入 X 条”
- 改成分别展示：
  - 新增多少
  - 更新多少
  - 跳过多少
- 进度文案区分：
  - `processedCount`
  - `addedCount`
  - `updatedCount`
  - `skippedCount`
- 导入历史行内文案明确是：
  - 普通导入
  - 叠加导入
  - 是否支持撤回

### 7. 处理旧记录的兼容呈现

现有数据库里已经存在旧 `ImportRecord`。

这次不做历史数据修复，但要保证 UI 不再撒谎：

- 旧记录继续显示
- 旧记录默认视为 `supportsUndo == false`
- 行内给出轻量说明，例如“旧记录，无法安全撤回”

这样可以避免用户继续点到一个语义上已经不成立的“撤回”。

### 8. 验证

#### Build

- `xcodegen generate && xcodebuild -scheme MemoryPalace build`

#### 手动场景

至少验证下面几组场景：

1. 普通重复导入同一份文件两次
   - 第二次应全部 `skipped`
   - 本地文件夹 / 收藏 / 软删除状态不变

2. 叠加导入 `abc` 后，再导入 `acd`
   - 结果应为 `abcd`
   - `a` 吸收新增内容
   - `b` 保留
   - `d` 新增

3. 同 id 对话消息数不变，但标题 / 内容 / `currentNodeId` 有变化
   - 应判定为 `updated`

4. 对已有 conversation 的某个 node 先做本地收藏或软删除，再做叠加导入
   - 该 node 的本地状态应保住

5. 撤回一条“只新增”的新格式记录
   - 只删除该次新增的数据

6. 撤回一条“含 updated”的叠加记录
   - 结果应回到导入前状态
   - 不应把更早就存在的 conversation 整条删掉

## 风险检查

- 不能出现任何无 predicate 的 `FetchDescriptor<MessageNode>()`
- 不能再让普通导入通过 SwiftData unique upsert 偷偷覆盖本地状态
- 不能让叠加导入继续用“删光节点再重建”的方式破坏 node 级本地状态
- 不能继续让“已处理数”伪装成“已导入数”
- 不能继续让旧记录显示一个语义上不成立的“撤回”

## 影响文件

- `MemoryPalace/Models/ImportRecord.swift`
- 新增一个 import change model 文件（建议放 `MemoryPalace/Models/`）
- `MemoryPalace/Services/ConversationImporter.swift`
- `MemoryPalace/Services/ClaudeImporter.swift`
- `MemoryPalace/Views/ImportView.swift`
- `MemoryPalace/Views/ImportHistoryView.swift`

## Todo

- [x] 把普通导入改成真正的 append-only，停止隐式 upsert
- [x] 扩展 `ImportRecord`，补齐 mode / supportsUndo / added / updated / skipped 统计
- [x] 新增 `ImportConversationChange` 和快照结构体
- [x] 给 ChatGPT importer 加 conversation summary / merge comparator
- [x] 给 Claude importer 加 conversation summary / merge comparator
- [x] 把叠加导入改成按 node id 增量 merge，而不是删光重建
- [x] 导入时统一写入 change log
- [x] 重写 `ImportHistoryView` 撤回逻辑
- [x] 收紧 `ImportView` / `ImportHistoryView` 文案与统计
- [x] 给旧记录加“不可安全撤回”的兼容呈现
- [x] 跑 build 和主线路径验证

## 完成情况

- 普通导入已改成 append-only；重复导入只跳过，不再通过 SwiftData unique upsert 覆盖本地状态。
- 叠加导入已改成“保留本地全集”的增量 merge；同 id conversation 走 change log + snapshot，不再删光旧节点重建。
- 导入历史已切到 `ImportConversationChange` 作为撤回 truth source；新记录可回到导入前状态，旧记录不再显示误导性的安全撤回。
- 导入界面和历史界面的文案 / 统计已改成新增 / 更新 / 跳过三类，不再把已处理数伪装成已导入数。

## 验证结果

- `xcodegen generate`：通过
- `xcodebuild -scheme MemoryPalace build`：`BUILD SUCCEEDED`
- `/tmp/verify-imports`：`verification-passed`

脚本化验证覆盖了主线路径：

- `abc` 首次普通导入成功
- 同一文件重复普通导入后，`conversation.isFavorite` / `folderId` / `node.isFavorite` 保持不变
- 叠加导入 `acd` 后结果为 `abcd`
- `a` 吸收新增节点，`b` 保留，`d` 新增
- 叠加导入不会冲掉旧 node 的收藏状态
- 撤回该次叠加导入后，数据恢复为 `abc`
