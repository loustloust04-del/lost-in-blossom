# Anthropic Prompt Caching 接入方案（PROMPT-CACHE-PLAN）

> 目标：用 `cache_control` 断点把每轮重复发送的 system prompt + 对话历史缓存起来，
> 缓存读只收 0.1× 输入价，长对话可省 ~90% 输入成本，同时显著降低首 token 延迟。

## 0. 缓存机制速记（Anthropic API）

- **前缀匹配**：缓存 key 是渲染后 prompt 的字节前缀，顺序固定为 `tools → system → messages`。
  前缀中**任何一个字节**变化，其后所有断点全部失效。
- 断点写法：content block 上加 `"cache_control": {"type": "ephemeral"}`（默认 5 分钟 TTL，
  可选 `"ttl": "1h"` 但写入价从 1.25× 涨到 2×）。
- 每个请求最多 **4 个断点**。
- 最低可缓存前缀与模型相关：Sonnet 4.5 为 1024 token，Fable 5 / Sonnet 4.6 为 2048，
  Opus 4.6+ / Haiku 4.5 为 4096。低于门槛时静默不缓存（无报错，
  `cache_creation_input_tokens` 为 0）。
- 价格：缓存读 ~0.1×，缓存写 1.25×（5 分钟 TTL）。第二次请求即回本。
- 验证字段：响应 `usage.cache_read_input_tokens` / `usage.cache_creation_input_tokens`。
  连续请求 read 恒为 0 = 有隐形失效源。
- 缓存按模型隔离：换模型（记忆提取用 cheap model）不共享缓存，互不影响。

## 1. 现状盘点（为什么现在 0 缓存收益）

请求构建链路：`ConversationViewModel.assemblePrompt`（ConversationViewModel.swift:1122-1153）
→ `PromptAssembler.assemble` → `AnthropicProvider.sendStreaming`（ChatService.swift:456-535）。

| 问题 | 位置 | 影响 |
|---|---|---|
| `system` 是纯字符串，全链路无任何 `cache_control` | ChatService.swift:493-495 | 完全没启用缓存 |
| `{{date}}` / `{{time}}` / `{{health}}` 宏展开后**插值进 system prompt** | ConversationViewModel.swift:1133-1151 | `{{time}}` 精确到分钟——每分钟整个 system + messages 前缀全部失效，是头号缓存杀手 |
| 世界书按**关键词扫描最近消息**决定注入哪些条目 | PromptAssembler 世界书注入段 | 每轮注入集合可能不同 → system 中段抖动 |
| AUDN 记忆每轮对话后提取/更新，记忆块拼进 system | MemoryService + PromptAssembler | 记忆变动 → system 抖动（但频率低于 date/time） |
| 上下文摘要注入 system | PromptAssembler:149-151 | 摘要更新时抖动（低频，可接受） |
| usage 只解析 `input_tokens` / `output_tokens` | ChatService.swift:592-597 + message_start 处理 | 无法验证缓存命中，预算扣费也会把缓存读当全价输入算 |

结论：即使现在直接加断点，`{{time}}` 也会让缓存每分钟失效一次，先要做**稳定性分层**。

## 2. 缓存策略：按稳定性分三层

把 system 从单字符串改成 **text block 数组**，按"几乎不变 → 低频变 → 每轮变"排序，
断点打在每层末尾：

```
system: [
  // ── 层 1：稳定核心（preset 插槽 + 角色卡 persona + 项目指令）──
  // 整个会话期间字节不变。
  { "type": "text", "text": <stableCore>,
    "cache_control": {"type": "ephemeral"} },          // 断点 1

  // ── 层 2：半稳定（记忆块 + 世界书命中条目 + 上下文摘要）──
  // 每隔几轮才变。变了只重写层 2 之后的缓存，层 1 仍命中。
  { "type": "text", "text": <semiStable>,
    "cache_control": {"type": "ephemeral"} },          // 断点 2

  // ── 层 3：易变尾巴（{{date}}/{{time}}/{{health}} 展开结果）──
  // 在最后一个 system 断点之后，怎么变都不影响前面的缓存。
  { "type": "text", "text": <volatileTail> }           // 无断点
]
```

messages 部分（多轮增量缓存）：

```
messages: [
  ...历史轮次（字节与上一请求完全一致，天然命中）...,
  { "role": "user", "content": [
      { "type": "text", "text": <本轮用户输入>,
        "cache_control": {"type": "ephemeral"} }       // 断点 3
  ]}
]
```

每轮把断点 3 挪到最新 user turn 的最后一个 block 上；上一轮的断点位置仍是有效的
缓存读取点，所以历史会随对话增长**增量命中**（只为新增轮次付全价）。

断点预算：3 个已用，留 1 个备用（未来加 tools 时打在 tools 末尾）。

### 关键迁移点

1. **宏移出缓存前缀**（最高优先级）：`assemblePrompt` 不再把宏展开结果混进整个
   system 字符串，而是返回 `(stable: String, semiStable: String, volatile: String)`
   三段。宏只允许出现在 volatile 段（preset 里若有人把 `{{time}}` 写进角色卡正文，
   展开后会落在层 1——可在设置页提示，也可第一版先接受该用户自损缓存）。
2. **PromptAssembler 分层输出**：systemParts 已带 tag（slot id / "wb" /
   "contextSummary" / "projectInstructions"），按 tag 归类即可：
   - 层 1：preset 插槽（含 persona、jailbreak 等）+ projectInstructions
   - 层 2：记忆 marker、wb、contextSummary
   分层内保持现有 injectionOrder 排序，保证同输入字节序确定。
3. **世界书命中集合排序确定化**：注入前按条目 id 排序（同一集合不同序 = 字节不同 =
   失效）。命中集合本身轮间抖动无法避免，但它在层 2,只损失层 2 之后的缓存。
4. **历史不可变**：检查重发/编辑分支路径（regenerate / edit）——它们改写了历史前缀,
   该轮自然全额重写缓存,属预期行为,无需特判。

## 3. AnthropicProvider 改动（ChatService.swift）

```swift
// sendStreaming 入参从 systemPrompt: String? 扩展为分层结构（或保留旧参数 + 新参数并存）
if !systemBlocks.isEmpty {
    body["system"] = systemBlocks   // [[String: Any]]，见上文结构
}
// messages：最后一条 user 的 content 转 block 数组并打断点
```

- 多模态分支（content 已是 block 数组,ChatService.swift:477-480）：直接在最后一个
  block 上加 `cache_control`,与文本路径统一。
- 非 Anthropic provider（OpenAI 兼容网关）不动——`cache_control` 是 Anthropic 专有字段。
- `sendNonStreaming`（记忆提取/摘要用）：prompt 每次都不同、且常低于最低缓存门槛,
  **不加断点**（加了只付 1.25× 写入价、永远没有读）。

## 4. usage 解析 + 预算扣费

1. `TokenUsage` 增加 `cacheReadInputTokens` / `cacheCreationInputTokens` 字段。
2. 流式：`message_start` 的 `usage` 里解析这两个字段（ChatService.swift:631-638）；
   注意 `input_tokens` 此后只是**未缓存余量**,总输入 = input + cache_read + cache_creation。
3. 非流式：同样解析（ChatService.swift:592-597）。
4. `commitBudgetSpend` / PricingCatalog：缓存读按 0.1× 输入价计,缓存写按 1.25× 计,
   否则预算会把命中缓存的轮次按全价超额扣费。

## 5. 验证清单

- [ ] 同一会话连发两条消息（间隔 < 5 分钟）,第二条 `cache_read_input_tokens` > 0
- [ ] 第二条的 `input_tokens` 约等于"新增轮次 + volatile 尾巴"的 token 量
- [ ] 等待 2 分钟再发（跨分钟,`{{time}}` 变化）→ 层 1/层 2 仍命中（read > 0）
- [ ] 触发记忆更新后下一轮：层 1 命中,层 2 重写（creation > 0 且 read > 0）
- [ ] 切换模型再切回：首轮全额重写（缓存按模型隔离,预期行为）
- [ ] 短 persona 会话（system < 1024 token）：不报错,只是不缓存
- [ ] DEBUG log 打印三个 usage 字段,肉眼核对

## 6. 风险与边界

- **TTL 5 分钟**：聊天间隔超过 5 分钟,下一条全额重写（1.25×）。重写成本仅比不缓存
  多 25%,而活跃对话每轮省 ~90%,净收益明显。不建议 1h TTL（写入 2×,聊天场景回本慢）。
- **第三方 Anthropic 兼容网关**：部分网关会剥离/不透传 `cache_control`。字段不识别时
  API 静默忽略,无害；但要在设置页文档里注明"缓存仅官方 API 生效"。
- **20-block 回看窗口**：断点只向前回看 20 个 content block 找上次缓存。当前每轮
  1-2 个 block,远低于阈值,无需处理；未来若引入工具调用长链需复查。
- **历史截断（contextDepth）**：滑动窗口截掉最老轮次时,messages 前缀变化 →
  历史缓存全部重写。可接受；若想优化,截断步长改成一次砍 N 轮（减少重写频率）。

## 7. 实施顺序

1. `TokenUsage` + usage 解析扩展（独立、零风险,先上,用于摸底现状）
2. `assemblePrompt` 三层拆分 + 宏移出缓存前缀
3. `AnthropicProvider` system block 数组 + 断点 1/2
4. messages 末尾断点 3（多轮增量）
5. 预算扣费按缓存价计
6. 按第 5 节清单验证,DEBUG log 观察一周命中率
