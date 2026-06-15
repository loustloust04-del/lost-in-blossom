# 群聊 V3 方案 · 严肃重写版

> 前两次群聊实现都失败了。这次按教程的正确做法来。

---

## 一、之前为什么失败

V1（Chatroom VPS编排器）：太重，依赖外部服务，延迟高。
V2（猫写的 GroupChatScheduler）：固定轮询，没有门控，没有串行，各说各的，两轮卡死。

**核心错误：每条消息强制所有角色回复。** 四个人同时说话像被围攻。

---

## 二、正确做法（三个关键词）

**门控**：每个角色先判断"我要不要说话"，YES 才说。
**串行**：一个说完下一个才开始想，后面的能接前面的话。
**标注**：每条消息标明是谁说的。

---

## 三、架构选择

全部在 App 本地完成。不走 VPS 编排器。

理由：
- 消息存 SwiftData 的 MessageNode，继承全部基建（分支树、搜索、记忆、世界书、导出）
- 不依赖网络连接和外部服务
- 每个角色可以用不同模型和 Preset

---

## 四、数据结构

### 4.1 复用已有字段

MessageNode 已有（猫之前加的）：
- `senderId: String?` — 角色ID
- `senderName: String?` — 角色显示名

Conversation 已有（猫之前加的）：
- `kind: String = "single"` — "single" 或 "group"
- `participantsData: Data?` — JSON 存 `[GroupParticipant]`

GroupParticipant 已有：
```swift
struct GroupParticipant: Codable, Identifiable {
    let id: String
    var name: String
    var characterCardID: String
    var model: String
    var presetId: String
    var colorHex: String
}
```

**不需要新建任何 @Model。Schema 已经就绪。**

### 4.2 消息格式

所有消息（用户和AI）统一标注：
```
MessageNode(
    role: "user",
    content: "消息内容",
    senderName: "兔兔"      // 用户
)
MessageNode(
    role: "assistant",
    content: "回复内容",
    senderName: "角色A"     // 哪个角色说的
)
```

---

## 五、核心流程

### 5.1 用户发消息后

```
用户消息存入 SwiftData（senderName = 用户名）
    ↓
遍历 participants（串行，一个一个来）：
    ↓
  ┌─ 角色A：门控判断 → YES/NO
  │   YES → 组装 prompt → 调 API → 流式显示 → 存入 SwiftData
  │   NO  → 跳过
  ↓
  ┌─ 角色B：门控判断（能看到角色A刚说的）→ YES/NO
  │   YES → 组装 prompt → 调 API → 流式显示 → 存入 SwiftData
  │   NO  → 跳过
  ↓
  └─ ...直到所有角色判断完毕
    ↓
等待用户下一条消息
```

### 5.2 门控判断

用最便宜的模型（DeepSeek）跑 YES/NO：

```
你是一个群聊中的角色"{{name}}"。
你的性格简述：{{角色卡的 description 前200字}}

最近的群聊记录：
{{最近5条消息，格式 [发言者]: 内容}}

最新消息：
[{{发言者}}]: {{内容}}

判断：你需要回复这条消息吗？
- 有人 @你的名字 → YES
- 话题跟你的性格/兴趣直接相关 → YES
- 已经有其他人充分回应了 → NO
- 你最近连续说了2条以上 → NO（克制一下）

只输出 YES 或 NO，不要其他内容。
```

成本：每个角色每轮 ~50 token（DeepSeek），四个角色 = 200 token ≈ 不到一分钱。

### 5.3 镜像 Prompt（给角色组装消息）

当前说话的角色看到的消息格式：
- **自己之前说的** → `role: "assistant"`（让模型觉得是自己说的）
- **其他所有人说的**（包括用户和其他角色）→ `role: "user"`，内容前加 `[发言者名]: `

```swift
func buildMessages(for speaker: GroupParticipant, history: [MessageNode]) -> [APIMessage] {
    history.map { node in
        if node.senderName == speaker.name {
            // 自己说的 → assistant
            APIMessage(role: "assistant", content: node.content)
        } else {
            // 别人说的 → user + 标注
            let prefix = "[\(node.senderName ?? "???")]: "
            APIMessage(role: "user", content: prefix + node.content)
        }
    }
}
```

### 5.4 每个角色独立的 Prompt 组装

```swift
// 每个角色用自己的角色卡 + preset
let card = CharacterCardManager.card(id: participant.characterCardID)
let preset = PresetManager.preset(id: participant.presetId)
let systemPrompt = card.systemPrompt + "\n" + preset.systemPromptContent

// 组装消息
let messages = buildMessages(for: participant, history: recentHistory)

// 调 API（每个角色可以用不同模型）
providerRouter.sendStreaming(
    model: participant.model,
    messages: messages,
    systemPrompt: systemPrompt,
    ...
)
```

---

## 六、渲染

### 6.1 气泡标注

CardFlowView 已经支持 senderName 标签显示（PR-4 刚做完）。
每个参与者用 colorHex 区分气泡颜色。

### 6.2 输入栏

群聊对话的输入栏左边显示"发送给群聊"或 "@角色名"。
默认发送给群聊（所有角色门控判断）；输入 @名字 只触发指定角色。

---

## 七、特殊场景：三人房间（兔兔 + CC + API）

这是群聊的一个特例：
- 参与者固定：CC Caelum + API Caelum
- CC 通过 CCBridgeProvider 走 hub
- API 通过 ProviderRouter 走网关
- 门控对 CC 特殊处理：CC 自己判断（它有完整的 CLAUDE.md），不用便宜模型门控

---

## 八、文件结构

```
MemoryPalace/
├── Services/
│   └── GroupChatScheduler.swift    ← 重写（门控+串行+镜像）
├── Views/
│   ├── CreateGroupChatView.swift   ← 重写（简化版）
│   └── CardFlowView.swift          ← 已有 senderName 标签
├── Models/
│   └── GroupParticipant.swift       ← 已有
```

---

## 九、不做的事

- 不做 VPS 编排（纯本地）
- 不做导演模型调度（太贵，留以后）
- 不做随机延迟动画（以后加）
- 不做群聊专用记忆（先用对话级别的，以后拆）
- 不新增 @Model（用现有字段）

