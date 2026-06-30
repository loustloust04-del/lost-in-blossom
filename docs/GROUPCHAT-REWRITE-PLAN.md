# 群聊系统根本性重写方案

> 调研来源：SillyTavern 群聊、AutoGen/ConvoGen 多Agent框架、Soulkyn/Yoodli 产品、
> 会话分析学 turn-taking 理论、粟粟群聊 V3 设计文档、我们的 V4 实战问题

---

## 一、现状问题总结

### 已知 6 大 Bug
1. **消息截断/碎片** — AI 回复被切成多条气泡（SSE 断连 + defer 保存 partial）
2. **AI 互相感知不足** — 分不清谁说的，对话像自说自话
3. **历史消息加载** — fetchHistory URL/格式问题（已部分修复）
4. **Session 隔离** — 单例 ChatroomService 切换时数据泄漏
5. **创建群聊流程** — preset/model/userName 传递不完整
6. **发送目标** — round/@角色/silent 端到端未跑通

### 架构层面的根本问题
- **两套群聊系统并存**：VPS 编排的 ChatroomService（SSE）+ 本地编排的 ConversationViewModel+Group
- ChatroomService 依赖 VPS 服务，断连就废
- 本地 V4 编排可用但功能简陋
- 两套代码互相不复用，维护成本翻倍

---

## 二、行业最佳实践（调研总结）

### SillyTavern 的群聊设计（最成熟的开源方案）

**四种发言人选择策略**：
1. **Natural Order**（推荐）：名字被提及 → talkativeness 概率 → 兜底随机
2. **List Order**：按成员列表固定顺序轮流
3. **Round Robin**：所有人必须说完才重新开始
4. **LLM 决定**（社区提议）：用一次便宜的 LLM 调用决定谁说话

**角色卡信息处理**：
- Default 模式：每次只注入当前说话者的角色卡（省 token）
- APPEND 模式：所有成员角色卡合并注入（角色互相了解，贵但好）

**auto-mode**：角色自动接力说话，5 秒间隔，用户打字自动暂停

**Self-Response**：默认禁止自己回复自己（防复读）

### ConvoGen 论文方案

**Speaker Selection Prompt**：群聊管理器用专门的 prompt 决定下一个说话者，考虑：
- 当前对话上下文
- 所有 agent 的名字和描述
- 会话主题和自然流转

**关键发现**：限制每次回复的 token 数量能大幅提升自然度（防止 AI 话痨）

### Turn-Taking 理论

三条核心规则（Sacks 1974）：
1. 当前说话者指定下一个（@某人）→ 被指定者必须说
2. 当前说话者没指定 → 任何人可以抢话
3. 没人说 → 当前说话者可以继续

---

## 三、重写方案：统一为纯本地编排

### 核心决策：砍掉 VPS 编排，统一用 ConversationViewModel+Group

**理由**：
- VPS ChatroomService 是 6 大 bug 中 4 个的根源
- 本地编排已经可用，只需增强
- 消息存 SwiftData MessageNode，继承所有基建
- 不依赖网络，离线可用

### 3.1 增强发言人选择（替代固定轮询门控）

当前 V4：每个角色都做一次便宜 LLM 门控 → 太慢（N 次额外调用）

**新方案：单次 LLM 选人**

```
你是群聊主持人。根据最近的对话，从这些角色中选出下一个该说话的人：
{{角色列表，每个一行：名字 - 简介}}

最近的对话：
{{最近5条消息}}

规则：
- 被 @的角色必须选
- 刚说过话的角色不要连续选（除非被 @）
- 选最适合回应当前话题的角色
- 如果没人特别适合，选"无"（本轮结束）

输出格式：只输出一个角色名，或"无"
```

**成本**：从 N 次门控调用降到 1 次选人调用
**效果**：更自然的对话流转，不是所有人都抢着说话

### 3.2 增强 AI 互感（替代简单前缀标注）

当前问题：`[名字]: 内容` 前缀模型经常忽略

**新方案：结构化角色卡注入**

在 system prompt 加群聊成员列表：
```
## 群聊成员
- 兔兔（用户）：你的主人
- Luna：温柔安静的月系少女，喜欢天文
- Spark：活泼话痨的火系精灵，喜欢吐槽

## 对话格式
其他人的消息会以 [名字] 开头标注。你的回复不要加任何前缀。
你可以 @某人的名字来跟他们说话。
```

加一条镜像改进：不仅标注名字，还标注角色关系：
```
[Luna（你的好朋友）]: 今晚月亮好美啊
```

### 3.3 发言轮次控制

**max_replies_per_round**：每轮最多 N 个角色回复（默认 2-3）
**回复长度限制**：system prompt 加 `回复简短自然，像微信群聊一样，通常1-3句话`
**连续发言防护**：同一角色不能连续说 2 次（除非被 @）
**auto-continue**：一轮结束后，如果上一个说话者提了问题或 @了人，自动追加一轮

### 3.4 @ 提及系统

- 用户输入 `@Luna` → 只让 Luna 回复（跳过选人）
- AI 输出里包含 `@Spark` → 下一轮自动让 Spark 回复
- 模型 system prompt 里教它可以用 @名字 来叫人

### 3.5 UI 改进

**发送栏**：
- 默认"发送给群聊"
- 长按发送按钮弹出菜单：发给群聊 / @Luna / @Spark / 旁白（不触发回复）

**气泡**：
- 每个角色用独特颜色（已有 colorHex）
- 头像区域显示角色小图标（如果有角色卡头像）
- 正在思考的角色显示打字指示器 `...`

**群聊设置页**：
- talkativeness 滑块（每个角色独立）
- max_replies_per_round 设置
- auto-continue 开关

---

## 四、实施步骤

### Phase 1：清理 + 统一（1-2 个 session）
- [ ] 砍掉 ChatroomService + ChatroomView 的 SSE 编排路径
- [ ] 统一到 ConversationViewModel+Group 本地编排
- [ ] 修复消息截断 bug（一次 sendStreaming 完整写入一条）

### Phase 2：选人增强（1 session）
- [ ] 把 N 次门控改成 1 次 LLM 选人
- [ ] 加 @ 提及解析
- [ ] 加连续发言防护

### Phase 3：互感增强（1 session）
- [ ] system prompt 加群聊成员列表
- [ ] 镜像 prompt 加角色关系标注
- [ ] 回复长度约束

### Phase 4：UI 打磨（1 session）
- [ ] 发送栏 @ 菜单
- [ ] 打字指示器
- [ ] 群聊设置页

### Phase 5：高级功能（以后做）
- [ ] auto-continue
- [ ] talkativeness 滑块
- [ ] 群聊专用记忆
- [ ] 角色头像
- [ ] 群聊导出

---

## 五、文件影响

| 文件 | 改动 |
|------|------|
| ConversationViewModel+Group.swift | 重写选人逻辑 + @ 解析 |
| GroupChatScheduler.swift | 门控→选人、镜像增强、长度约束 |
| GroupParticipant.swift | 加 talkativeness 字段 |
| CardFlowView.swift | 打字指示器 |
| CreateGroupChatView.swift | 简化 + 加设置项 |
| ChatroomService.swift | 降级为纯历史兼容层 |
| ChatroomView.swift | 合并到 CardFlowView |

---

## 六、风险

- 砍 VPS 编排会丢"三人房间"（CC + API + 用户）能力 → 后续用 CCBridge 参与者复现
- 本地编排每个角色串行调 API 有延迟 → 用流式显示 + 打字指示器掩盖
- LLM 选人可能选错 → 兜底机制：选不出就 Round Robin
