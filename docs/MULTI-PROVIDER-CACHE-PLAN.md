# 多 Provider 缓存优化方案（给粟儿）

> 目标：让 MemoryPalace 在 Anthropic / OpenAI / Gemini 三家 API 上都命中缓存，降低 50-90% 输入成本。
> 核心原则：三家都是前缀匹配，所以通用改动只有一件事——保持前缀稳定，动态内容放最后。

## 0. 三家机制对比

| | Anthropic | OpenAI | Gemini |
|---|---|---|---|
| 需要代码改动 | 手动加 cache_control 断点 | 不需要，全自动 | 隐式不需要，显式需要 |
| 缓存读折扣 | 90% off（0.1×） | 50% off（0.5×） | ~75% off |
| 缓存写成本 | 1.25×（5min）/ 2×（1h） | 免费 | 免费（但显式有存储费） |
| TTL | 5min 或 1h 可选 | ~5-10min 自动 | 隐式自动 / 显式自定义 |
| 最低 token 门槛 | 1024-4096（按模型） | 1024 | 按模型不同 |
| 命中判据 | usage.cache_read_input_tokens | usage.prompt_tokens_details.cached_tokens | usage_metadata.cached_content_token_count |

## 1. 通用改动（三家都受益，最高优先级）

### 1.1 修滑动窗口（最关键）

现状：`buildAPIMessages` 用 `relevant.suffix(maxMessages)` 取最近 N 条。
问题：每来一条新消息，窗口最旧的一条滑出去，历史前缀每轮变，缓存永远 miss。
修法：用压缩游标锚定窗口起点。

```swift
// 之前（滑动窗口，缓存杀手）
if relevant.count > maxMessages {
    return Array(relevant.suffix(maxMessages))
}

// 之后（锚定窗口）
// compressed_up_to 是 ContextSummarizer 已摘要覆盖到的最后一条消息
// 窗口从这里开始，只在压缩推进时才移动
let anchor = conversation.compressedUpTo ?? 0
let windowed = relevant.filter { $0.sequenceIndex > anchor }
let capped = windowed.suffix(120) // hard cap 防故障
return Array(capped)
```

### 1.2 动态内容移出前缀

所有每轮变化的内容（时间、日期、健康数据、记忆召回、摘要）只在构造 API payload 的运行时注入最后一条 user 消息。绝对不写进数据库。

```swift
// PromptAssembler 返回分层结构
struct AssembledPrompt {
    let stableCore: String      // 角色卡 + preset + 项目指令（永不变）
    let semiStable: String      // 记忆 + 世界书 + 上下文摘要（偶尔变）
    let volatile: String        // {{time}} {{date}} {{health}}（每轮变）
}
```

volatile 层永远放在所有缓存断点之后。

### 1.3 世界书/工具列表排序确定化

注入前按 id 排序。同一集合不同顺序 = 字节不同 = 缓存失效。

### 1.4 图片降级（网关层已有方案）

当轮保留原始图片让模型看，存入历史时转为自然语言描述。
工具调用结果同理，存为文字摘要而非结构化数据块。

### 1.5 覆盖式压缩

摘要必须每次从原始消息重新生成完整摘要，覆盖旧值，用 max_tokens 封顶。
不能追加式，否则摘要越滚越长，input 随对话总量线性上涨。

## 2. Anthropic 专属改动

### 2.1 system 改为 content block 数组 + 断点

```json
{
  "system": [
    { "type": "text", "text": "<stableCore>",
      "cache_control": {"type": "ephemeral"} },
    { "type": "text", "text": "<semiStable>",
      "cache_control": {"type": "ephemeral"} },
    { "type": "text", "text": "<volatile>" }
  ]
}
```

### 2.2 messages 断点打在倒数第二条 user turn

```swift
// 倒数第二条 user 消息的最后一个 content block 加断点
// 最后一条是本轮新输入，每次不同，挂上去等于没挂
```

### 2.3 metadata.user_id

走中转/网关时请求顶层带固定 user_id，保证路由粘性。

```json
{ "metadata": { "user_id": "session-xxx-固定" } }
```

### 2.4 usage 解析

```swift
// 流式：message_start 的 usage 里解析
struct TokenUsage {
    var inputTokens: Int
    var outputTokens: Int
    var cacheReadInputTokens: Int      // 新增
    var cacheCreationInputTokens: Int  // 新增
}
```

### 2.5 保活心跳（1h TTL 时）

距上次对话约 55 分钟时发一条前缀完全一样的请求，max_tokens=1，不写历史。
5min TTL 不做保活。

## 3. OpenAI 专属改动

OpenAI 缓存全自动，不需要加任何标记。只要做了第 1 节的通用改动就够了。

额外注意：
- 确认走的是 Chat Completions API（/v1/chat/completions）
- 看 `usage.prompt_tokens_details.cached_tokens` 确认命中
- OpenAI 缓存按 128 token 粒度增量，前缀变了一个字节从变化点开始重算

## 4. Gemini 专属改动

### 4.1 隐式缓存（推荐先用）

Gemini 2.5+ 默认开启，无需代码改动。做了第 1 节通用改动就自动受益。
看 `usage_metadata.cached_content_token_count` 确认命中。

### 4.2 显式缓存（大上下文高频场景）

适合：固定的大文档/视频反复查询。
不适合：普通聊天（存储费可能比省下的还多）。

```python
# 创建缓存
cache = client.caches.create(
    model="gemini-2.5-pro",
    contents=[{"role": "user", "parts": [大文档内容]}],
    ttl="3600s"
)
# 后续请求引用缓存
response = client.models.generate_content(
    model="gemini-2.5-pro",
    contents="基于文档回答问题",
    cached_content=cache.name
)
# 用完删除！否则按小时扣存储费
client.caches.delete(name=cache.name)
```

对于 MemoryPalace 的陪伴聊天场景，隐式缓存足够，不建议用显式。

## 5. 实现优先级

1. **通用改动**（锚定窗口 + 动态内容分层 + 排序确定化）— 三家都受益，最高优先级
2. **Anthropic 断点** — 省最多（90% off），粟儿的主力模型
3. **usage 解析** — 三家都加，用来验证命中
4. **探针验证** — 写测试脚本，冻结时间连发两次，确认 read > 0
5. **保活心跳** — Anthropic 1h TTL 场景，最后做

## 6. 验证方法

三家都适用的探针：
1. 冻结所有动态内容（时间写死）
2. 构造完全相同的请求连发两次
3. 第二次的缓存读取 token > 0 → 命中
4. 连续多轮 read 恒定不涨 → 历史没命中，查滑动窗口

read 是唯一判据。write 变小不代表命中。
