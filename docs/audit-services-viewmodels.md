# 审查报告：Services/ + ViewModels/

> 审查范围：`MemoryPalace/Services/*.swift`（约 95 个文件）+ `MemoryPalace/ViewModels/*.swift`（7 个文件）
> 审查日期：2026-08-12
> 审查原则：按「值不值得动」排序，不按「有多丑」排序

---

## P0 · 会咬人的

### 1. `try? context.save()` 遍地开花——静默丢数据

| 文件 | 行号 | 场景 |
|------|------|------|
| HealthSyncService.swift | 57 | pushLocal 后保存 gatewayId 绑定 |
| HealthSyncService.swift | 125 | pullRemote 后保存 intake log |
| HealthLogStore.swift | 86, 93, 109, 125, 143, 153 | 体重/吃药/亲密等 CRUD |
| HealthCycleStore.swift | 63, 74 | 经期打点 upsert/remove |
| IntimacySyncService.swift | 56 | pull 后保存亲密备注 |
| HealthLogIntentWriter.swift | 36, 175 | 聊天意向落库 |
| ConversationViewModel+Chat.swift | 680, 971, 1009, 1240 | 对话消息保存 |
| ConversationListStore.swift | 118, 139 | tag 删除/排序持久化 |

**问题**：`try? context.save()` 如果失败，调用方完全不知道。HealthSyncService 最严重——save 失败 = gatewayId 绑定丢失 = 下次 sync 重复推送；intake log save 失败 = 重复吃药记录。ConversationViewModel+Chat 的 save 失败 = 对话内容丢失。

**建议**：统一封装一个 `safeSave(context:caller:)` 方法，save 失败时至少写 BreadcrumbLog + 弹一次 transientNotice。最高优先级修 HealthSyncService 和 ConversationViewModel+Chat 的几处。

---

### 2. VitalsClient.merge() 捏造空药物数据

**文件**：VitalsClient.swift:48-54

**问题**：`merge()` 把本地 DailyContext 和远端 VitalsResponse 合并成一个新的 VitalsResponse，但为了凑 decoder 的结构，给 `.meds` 字段填了 `taken: false, name: "", lastUpdated: ""`。如果任何调用方读取 merge 结果的 `.meds`，会拿到假数据。

**建议**：确认 merge 结果的消费方是否读 `.meds`；如果不读，加注释标明 meds 字段是占位无效值；如果读，改成从 HealthSyncService 取真实数据。

---

### 3. VitalsClient.fetch() 双重 try? 吞掉网络+解码错误

**文件**：VitalsClient.swift:26-27

**问题**：`try? await URLSession.shared.data(for: req)` + `try? JSONDecoder().decode(...)` 连续两个 try?，网络超时、服务器 500、JSON 格式变了——全部静默返回 nil。调用方只看到"没数据"，无法区分"没连上"和"数据格式变了"。

**建议**：至少在 decode 失败时写一条 log（VitalsClient 不像 MedsClient 有 GatewayCache 兜底，失败就是纯黑洞）。

---

### 4. HealthBridgeClient 非 200 响应静默丢弃

**文件**：HealthBridgeClient.swift:48-51

**问题**：`try?` 吞网络错误，只在 200 时更新节流时间戳。服务器返回 500/403 等错误码时，数据没上报，也没 log，也没 retry。30 分钟节流意味着最快半小时后才重试。

**建议**：非 200 时不更新 lastReport 时间戳（当前已做到），但应加 log 记录错误码。可不改——半小时窗口内数据不会累积丢失，只是延迟。**可不改**

---

### 5. ChatService.swift fatalError 在 base class

**文件**：ChatService.swift:55-56, 115-116

**问题**：`sendStreaming()` 和 `processData()` 的 base class 实现是 `fatalError("Subclass must implement")`。虽然三个子类都 override 了，但如果将来有人直接实例化 BaseChatProvider 就会崩。

**建议**：改成 protocol + default extension，或至少把 BaseChatProvider 标记为 `open class` 不提供默认实现。**可不改**——当前无人直接用 base class。

---

### 6. SyncEngine.pump() 在后台线程创建 ModelContext 但回调不在同线程

**文件**：SyncEngine.swift:130-154

**问题**：`DispatchQueue.global(qos: .utility).async` 里创建 `ModelContext(container)` 做 import/export，完成后 `Task { @MainActor in ... }` 回主线程更新状态。ModelContext 不是 Sendable，跨线程使用在 Swift 6 strict concurrency 下会报错。当前 Swift 5 mode 下不崩，但升级时会。

**建议**：改成 `Task.detached { let context = ModelContext(container); ... }`，或用 ModelActor。迁 Swift 6 前必须修。**可不改**——当前运行正常，但标记为技术债。

---

## P1 · 拖慢的

### 7. VitalsClient.fetch() 无缓存

**文件**：VitalsClient.swift:24-28

**问题**：每次调用都发网络请求。MedsClient 和 PeriodClient 都用了 GatewayCache 做 stale-while-revalidate，VitalsClient 没有。弱网时控制台健康卡转圈等。

**建议**：加 GatewayCache，和 MedsClient 同款。

---

### 8. MemoryService.recordAccess() N+1 查询

**文件**：MemoryService.swift:141-149

**问题**：`recordAccess` 接收一组 memory ID，逐个 `fetch(descriptor)` 查询并更新 `lastAccessedAt`。10 条记忆 = 10 次 SwiftData fetch。

**建议**：改成一次 IN 查询取全部，再逐个更新。或者用 `#Predicate { ids.contains($0.id) }` 一把取。

---

### 9. ConversationViewModel+Group 每轮重建 Manager

**文件**：ConversationViewModel+Group.swift:28-29, 124-125

**问题**：`CharacterCardManager()` 和 `PresetManager()` 在群聊每一轮都重新实例化。如果它们的 init 从磁盘读数据（角色卡 JSON / 预设文件），群聊 5 轮 = 10 次磁盘读。

**建议**：确认是否真的从磁盘读；如果是，缓存实例复用。

---

### 10. CCBridgeWebSocketClient pingTimer 每 5 秒

**文件**：CCBridgeWebSocketClient.swift:798

**问题**：ping 每 5 秒一次，App 在前台时合理（keepalive），但 App 进后台后 Timer 应该停。

**建议**：确认是否在 `scenePhase == .background` 时停掉了。如果没有，加生命周期监听。**可不改**——iOS 后台 Timer 大概率被系统冻结，不会真的每 5 秒跑。

---

### 11. SearchService.searchPlacedStickers() 全表扫描

**文件**：SearchService.swift:483-488

**问题**：先查所有 PlacedSticker（`profileId == pid`），再内存 filter。贴纸多的时候（几百张）每次搜索都全表查。

**建议**：如果贴纸量大，考虑加 index 或 predicate 层面的 noteContent contains 过滤。**可不改**——贴纸量通常不大。

---

### 12. SearchService.searchMemories() 双重全量 fetch

**文件**：SearchService.swift:745-765

**问题**：先按 content keyword fetch 一次，然后再 fetch 该 profile 下的**全部** Memory 做 keywords 数组的二次过滤。两次全量查。

**建议**：合并为一次全量 fetch + 内存双重过滤，省掉第一次的 predicate fetch。或者直接全量 + filter，因为 Memory 总量通常不大。**可不改**——功能正确，量级有限。

---

### 13. ContextSummarizer 存 UserDefaults

**文件**：ContextSummarizer.swift:22-29

**问题**：每个对话的 ContextSummary（摘要，可能 2000 字）存在 UserDefaults 里，key 是 `ctxSummary_{conversationId}`。对话多了（几百个）UserDefaults 会变大，启动时全量加载。CrossWindowMemory 同理（60 条 × 800 字）。

**建议**：迁移到文件存储或 SwiftData。低优先级——当前对话量级下 UserDefaults 能撑住。**可不改**

---

## P2 · 屎山本身

### 14. ConversationViewModel+Chat.swift 1619 行

**文件**：ConversationViewModel+Chat.swift

**问题**：`sendMessage` 一个函数 400+ 行，混合了 prompt assembly、budget check、streaming setup、tool calling、memory extraction。

**建议**：拆成 sendMessage -> assemblePipeline -> executeStream -> postProcess 几步。最值得动的拆法：budget 检查独立、memory extraction 独立。

---

### 15. CCBridgeWebSocketClient.swift 815 行

**文件**：CCBridgeWebSocketClient.swift

**问题**：连接管理、消息路由、terminal streaming、push notification 注册、reply handler 管理、去重逻辑全在一个类。

**建议**：至少把 push notification 相关逻辑拆出去。功能正确，代码组织问题。**可不改**

---

### 16. MemoryService.swift 785 行

**文件**：MemoryService.swift

**问题**：MemoryStore protocol + SwiftDataMemoryStore + DecayEngine + MemoryFlags + 4 个 retriever + MemoryInjector + MemoryExtractor 全在一个文件。

**建议**：DecayEngine 和 MemoryExtractor 可以各拆一个文件。功能正确。**可不改**

---

### 17. HealthLogStore.swift 混合多个不相关 domain

**文件**：HealthLogStore.swift (341 行)

**问题**：体重 CRUD、药物 CRUD、亲密 CRUD、注射摘要、fetch helpers 都在一个 enum 里。

**建议**：按 domain 拆成 WeightStore、MedLogStore、IntimacyStore。低优先级。**可不改**

---

### 18. ConversationListStore.swift predicate 组合爆炸

**文件**：ConversationListStore.swift:176-400

**问题**：`normalPredicate` 和 `trashPredicate` 用 4 个 if-else 分支处理 keyword × dateRange × favoritesOnly 的组合。SwiftData `#Predicate` 不支持运行时动态组合，所以只能这样写。代码丑但功能正确。

**建议**：无好办法。SwiftData 的限制。**可不改**

---

### 19. 重复的 gateway 鉴权模式

多个 Client（VitalsClient、PeriodClient、MedsClient、IntimacySyncService、BoardClient、AnniversaryClient、WishClient、TweetsClient）都各自重复实现 `baseURL + token + request builder` 模式。

**建议**：抽一个 `GatewayRequest` helper。低优先级——每个 Client 都能跑。**可不改**

---

## 值得动的排序（从高到低）

1. **HealthSyncService try? context.save()**（P0）——save 失败 = 药物重复推送 / intake 重复记录，直接影响用药安全
2. **ConversationViewModel+Chat try? context.save()**（P0）——save 失败 = 对话丢失
3. **VitalsClient.merge() 捏造空 meds**（P0）——确认消费方后决定是否改
4. **VitalsClient.fetch() 无缓存**（P1）——弱网体验差，GatewayCache 是现成的
5. **MemoryService.recordAccess() N+1**（P1）——batch fetch 改动小收益大
6. **VitalsClient.fetch() 双重 try?**（P0）——至少加 log

---

## 全局观察

### 做得好的
- GatewayCache stale-while-revalidate 模式统一且正确
- ToolCallLoop maxRounds=5 安全阀
- CCBridgeWebSocketClient 去重机制（seenReplyIds + 600 rolling window + UserDefaults 持久化）
- ConversationViewModel profile switch race defense 设计严谨
- PromptAssembler 的分层缓存设计（stable/semi-stable/volatile）
- AnthropicProvider 的 prompt caching breakpoint 策略
- ContextSummarizer 滞回裁剪设计（high/low water mark）

### 模式性问题
- `try? context.save()` 是全仓最大的系统性风险，建议统一治理
- Gateway Client 鉴权模式重复但不是紧急的
- UserDefaults 存大文本（ContextSummary、CrossWindowMemory）是定时炸弹，对话量增长后会爆
