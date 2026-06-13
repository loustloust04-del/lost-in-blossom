# Plan: SC-B4 全局预算协调器 — 地基批收官（剩余四刀）

> 2026-06-13 · 前序：刀3 世界书预算闸 ✅（wb_inject_budget）+ 刀4 PT1 死代码删 ✅（PromptPostProcessor 414 行+幽灵 UI），紧急冲刺已落地。
> 本 plan 覆盖剩余四刀：刀1 口径统一 / 刀2 申报制 / 刀5 S1 占比 / 刀6 多块断点。
> 输入：roadmap B4 段（三条新输入 ✅ 已吃）+ topology 拓扑打架点 B + OR 透传实验结论（✅ GO） + B27/B3/B2 复盘里的下游注意 + ChatService.swift 缓存段现状亲核。
> ⚠️ DON'T IMPLEMENT YET — 等粟粟批注。

---

## 一、现状三套估算器（亲核，差异实测）

| 估算器 | 位置 | CJK 乘数 | 英文策略 | "你好世界 hello world" |
|--------|------|---------|---------|----------------------|
| Memory.estimateTokens | Memory.swift:71 | ×2 | 空格计数 | **10** |
| TokenEstimator.estimate | PromptTokenEstimator.swift:8 | ×1.5 | ×0.25 per char | **9** |
| HeuristicEstimator | TokenEstimator.swift:11 | ×1.0 | ÷3.5 | **8** |

Memory 的 ×2 偏高、HeuristicEstimator 的 ×1.0 偏低——Anthropic 官方说中文"约 1-1.5 token/字"，TokenEstimator 的 ×1.5 居中最合理。但 HeuristicEstimator 走保险闸（预算充裕下偏低影响小），**真要统一的只有 Memory 和 TokenEstimator**。

### B3 的新约束（必须吃）

目录模式渲染行 token ≠ Memory.tokenCount（差 3-8 倍）——**申报层不能依赖模型对象字段，必须按实际渲染文本重算**。buildInjectionSplit 的 tryAppend 现在已在目录模式下按渲染行估（Memory.estimateTokens(line)），统一口径就是把 Memory.estimateTokens 换成 TokenEstimator.estimate。

## 二、刀序（4 刀，每刀独立 commit）

### 刀1 · 口径统一（唯一有默认行为变化的刀）

1. `Memory.estimateTokens` 改调 `TokenEstimator.estimate`（一行委托，Memory.swift:71 → PromptTokenEstimator.swift:8）。
2. **预算常数换算**：记忆预算默认 2000 是 ×2 口径的语义——换 ×1.5 后同样内容 token 变少，2000 预算装的条数会**变多**（注入变胖），体感突变。换算保持有效容量：2000 × (1.5/2.0) = **1500**。⧫ 批注点 1：mem_inject_budget 默认值改 1500（换算等容），还是保持 2000（让注入变胖，趁 B3 目录模式在手可以对冲）？
3. S1 前后对照验收（默认配置下注入段逐字一致——不会，token 数变了排名可能微调；但注入**条数**应近似不变，这才是等容的语义）。
4. HeuristicEstimator 保留不动（保险闸走宽松口径是故意的——偏低 = 少拦截 = 不误杀正常请求）。

### 刀2 · 申报制协调器（默认旁路，触面最广）

设计核心：**各源在组装阶段申报实际用量 → 超总预算按优先级裁剪**。

1. 新结构 `ContextBudget`（纯值类型，在 assembleTagged 开头创建）：
   ```
   totalBudget: Int          // 默认 Int.max = 无限 = 现状行为零退化
   spent: [SegmentSource: Int]  // 各源申报的 token
   func canSpend(_ source, _ tokens) -> Bool
   func spend(_ source, _ tokens)
   ```
2. **申报时机**——每段注入时改为先问 `budget.canSpend`：
   - 记忆注入（buildInjectionSplit 内部已有预算，改为 向 ContextBudget 申报实际用量）
   - 世界书（wb_inject_budget 闸已有，申报给 ContextBudget 后整体受控）
   - 文件库 hint（固定文本 ~50 token，直接申报）
   - 摘要 / 画像 / 时间轴（slot 渲染结果，申报 TokenEstimator.estimate(content)）
   - 对话历史（chatHistory 段，申报——历史是优先级最高的不裁剪，但要知道用了多少）
3. **裁剪顺序**（总预算超出时）：保历史 > 保记忆 > 保世界书 > 保文件库。实现：低优先级源在 canSpend 返回 false 时整段不注入，log 裁剪原因。
4. **开关化**：`context_total_budget`（UserDefaults，默认 0=Int.max=无限=现状）。⧫ 批注点 2：要不要进设置页 UI？建议**暂不**（和 wb_inject_budget 同款，defaults write 可调），等日用数据再定默认值和 UI 位置。
5. **与 B3 目录模式的交互**：申报量是**渲染后**的 token（刀1 统一口径后的 TokenEstimator），目录行 vs 全文行自然不同。

### 刀5 · S1 占比可视化

S1 组装 tab 现有总 token 数（PersonaSettingsTab:1263），改为：
1. 逐段（source 分组）token 统计 → 水平堆叠条：历史(占比%) | 记忆(%) | 世界书(%) | 摘要(%) | 画像(%) | 文件库(%) | 其他(%)
2. 配色用各源既有色系（memory=金 / worldBook=灰 / chatHistory=主色 / summary=薄荷 / 等）
3. 总数标注在条上方。
4. ⧫ 批注点 3：占比条的视觉形态——水平堆叠色条 OK？还是你更想要别的展示形式？

### 刀6 · 多块缓存断点（OR 透传实验已 GO）

**实验结论**（2026-06-13 实测）：OR→Anthropic 官方三块 system 各挂断点完全透传；重发 99.96% read；只改第三块前两块保命中（省 63%）。

**改造对象**：ChatService.swift 的 system 段构造。现状 system 是一段 string → 需要变成 **block 数组**：

1. PromptAssembler.assembleTagged 的返回值增加**分段标记信息**（哪些段属于哪个缓存组），不改结构本身：
   - 段已经有 `SegmentSource`——按 source 分组到缓存块：
   - **块 A（BP1）**：人设 main + 角色描述 + 背景设定 + 画像 + 时间轴 → 几乎不变
   - **块 B（BP2）**：记忆常驻层 + 世界书常驻条目 → 天级稳定（衰减/提取不影响常驻层）
   - **块 C（BP3）**：上下文摘要 → 压缩触发时才变
   - 剩余（对话历史/动态上下文/文件库 hint）不进 system 段的缓存块（cacheFriendly 已下沉到 messages）
2. ChatService.buildRequestBody：cacheFriendly 模式下，system 从 `"content": string` 改为 `"content": [{type:text, text:块A, cache_control:...}, {type:text, text:块B, cache_control:...}, {type:text, text:块C, cache_control:...}]`——OAI 格式走 system message content array，Anthropic 格式走 system array。
3. **最大收益场景**：摘要更新（每 N 轮一次）只 miss 块 C，块 A+B 保命中；画像做梦（每天一次）只 miss 块 A+B，块 C 保。
4. ⧫ 批注点 4：分块方案 A+B+C 这样切 OK？还是你有不同的分法？BP4（末 assistant）保持现状不动。

## 三、不退化保证

- 刀1：换算常数保等容（条数近似不变），S1 前后对照
- 刀2：默认无限预算 = 全路径现状，设了值才裁剪
- 刀5：纯 UI 新增不动逻辑
- 刀6：system block 数组 vs 单 string 在 API 层等价（Anthropic 和 OAI 都支持 content array）；cacheFriendly 关时仍走单 string 路径

## 四、验收清单

- [ ] build 双端 + 测试全绿
- [ ] S1 对照：默认配置下注入条数与改前近似一致（刀1 等容验证）
- [ ] S1 占比条：各源 token 百分比可视化
- [ ] 设 context_total_budget → 超预算场景低优先级源被裁 + CacheDiagLog 可见裁剪原因
- [ ] cacheFriendly 实聊一轮 → OR 日志 cached_read > 0 且多块分段命中（改摘要后前块仍缓存）
- [ ] cacheFriendly 关 → 行为与改前完全一致

## 五、Task Checklist

- [ ] 刀1 口径统一（Memory 委托 + 预算换算 + S1 对照）
- [ ] 刀2 ContextBudget 申报制（默认无限 + 裁剪 + CacheDiagLog）
- [ ] 刀5 S1 占比条（水平堆叠 + 配色 + 总数）
- [ ] 刀6 多块断点（assembleTagged 分组标记 + ChatService system block 数组 + OR/Anthropic 双格式）
- [ ] build 双端 + 推 Air + review-B4.md + roadmap 勾

预估：净 ~300 行，2-2.5 天。

---

⧫ 批注区（等粟粟）：
1. **预算换算**：mem_inject_budget 默认改 1500（等容换算）还是保 2000（让注入变胖，目录模式对冲）？
2. **总预算 UI**：context_total_budget 暂不进设置页（defaults write 可调），等日用定默认值再做 UI？
3. **占比条形态**：水平堆叠色条 OK？
4. **分块方案**：块 A（人设画像时间轴）/ 块 B（记忆常驻+世界书常驻）/ 块 C（摘要）OK？
