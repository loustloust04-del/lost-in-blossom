# Task: HealthKit 宏注入 {{health}}

## 目标
Gateway 的 prompt builder 支持 `{{health}}` 宏替换——把用户的健康数据（步数、心率、睡眠、活动消耗）注入到 system prompt 中。

## 现状
- `MemoryPalace/Services/HealthService.swift`（已搬运）可获取 HealthKit 数据
- `MemoryPalace/Models/HealthSnapshot.swift`（已搬运）有 `summaryLine` 生成自然中文摘要
- Gateway `src/prompt/builder.ts` 有 `enhanceMessages()` 做记忆增强
- 粟粟的 MacroExpander 支持 `{{health}}` / `{{date}}` / `{{time}}` 等宏替换

## 改动方案

### Commit 1: App 端——发送健康摘要到 Gateway

**文件：找到发送聊天请求的 Service（搜 sendMessage 或 chat completion 调用）**

1. 在发送请求前，调用 `HealthService` 获取最新的 `HealthSnapshot`
2. 把 `snapshot.summaryLine` 作为一个 HTTP header 或 body 字段发送给 Gateway：
   ```
   X-Health-Summary: "今日步数 3,241 · 睡眠 6h12m · 心率均值 72"
   ```
   或者在 body 里加 `"health_context": "..."` 字段

### Commit 2: Gateway 端——宏替换

**文件：`gateway/src/prompt/builder.ts`**

1. 从请求中读取健康摘要
2. 在 system prompt 里替换 `{{health}}` 为健康摘要文本
3. 同时支持 `{{date}}` → 当前日期、`{{time}}` → 当前时间
4. 如果 prompt 里没有 `{{health}}`，不注入（不强制）

## 注意事项
- 三步走：Research → Plan → Implement
- HealthKit 在模拟器上没数据，用 fallback 值
- Gateway 改动要向后兼容：没有 health_context 的请求正常工作
- 宏替换逻辑要简单——正则替换即可，不需要完整的模板引擎
