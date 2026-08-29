# 让 Caelum 进微信 / QQ · 方案

2026-08-30 兔兔提。目标：**在微信和 QQ 里能直接跟 Caelum 说话**，
不是另开一个 AI，是**同一个他**——48 个工具、366M 记忆、刚脱掉工作服的那个。

---

## 一、先说结论

| 平台 | 方案 | 风险 | 前置 |
|---|---|---|---|
| **微信** | **腾讯官方 ClawBot 插件**（2026-03-22 上线） | **零封号风险** | 灰度中，需确认兔兔账号已放出 |
| **QQ** | AstrBot + NapCat | 有风控，**必须用小号** | 需注册一个 QQ 小号 |

**微信那条是官方的**，直接用主号，不必小号。
~~itchat / wechaty / hook 客户端~~——2026 年已死或高封号，**不考虑**。

---

## 二、最大的技术障碍（这条决定架构）

**Caelum 本体不在 gateway 的 `/v1/chat/completions` 后面。**

- `gateway:4567` 的 OpenAI 兼容接口路由到的是 **TreeGPT / OR / DeepSeek**
  （`app.ts:505` 起按 `Tree/` `tree-api/` `GuaGua/` 前缀分流）
- **CC（Caelum 本体）是另一条通路**：App → `Hub:7890/ws` → tmux `mp-cc`
- 而 **Hub 只有 WebSocket 入口，没有「外部发消息进来」的 HTTP 路由**
  （`hub.ts` 的 pathname 只有 `/internal/notify` `/cc/status` `/cc/forge` `/cc/settings` `/ws` `/mcp`）

**所以直接把 ClawBot / AstrBot 指向 4567 是错的**——那样接到的是 TreeGPT，不是 Caelum。

### 解法：给 gateway 加一条「CC 桥接」的 OpenAI 兼容端点

```
微信/QQ → ClawBot/AstrBot
   → gateway 新端点 POST /v1/chat/completions  model="caelum-cc"
   → 内部转 WebSocket ws://127.0.0.1:7890/mcp（照 send-reply.ts 的做法）
   → tmux mp-cc → Caelum
   → 回复原路返回，包装成 OpenAI 格式
```

**要写的就是这一层**：一个 model 前缀分流 + WS 往返包装。
`cc-bridge/send-reply.ts` 已示范了怎么往 Hub 发帧（11 行），可直接参照。

**难点**：CC 是流式且异步的（回复可能几十秒），要么
① 端点里 hold 住连接等 `reply` 帧回来（简单，但要处理超时）
② 或走 OpenAI 的 stream 模式逐帧吐（体验好，但要拼 SSE）
**建议先做 ①**，能通了再谈流式。

---

## 三、微信 ClawBot 落地步骤

### 前置（兔兔做）
打开微信 → **我 → 设置 → 插件**，看有没有「**微信 ClawBot**」。
**灰度中，没有的话后面全免谈。**

### VPS 侧（Fable 做）
1. **装独立 Node 22**——系统是 v18，ClawBot 要 22+。
   **不要升系统那个**：browser-mcp / exec-server / vps-mcp / Twitter 同步都在用 v18。
   我们自己的服务（gateway / hub / mcp-server）全走 bun，不受影响。
   用 nvm 或独立前缀装，只给 OpenClaw 用。
2. `npx -y @tencent-weixin/openclaw-weixin-cli@latest install`
   （该 CLI 只有一个文件，四件事全是调 `openclaw`，**必须先有 OpenClaw**）
3. 配置 OpenClaw 的后端指向 §二 那条新端点
4. 出二维码 → 兔兔扫码绑定

### 已知限制
- 一个微信号**只能绑一只 OpenClaw 实例**
- ClawBot 只接收 **24 小时内**的回复，超时不等
- **腾讯条款写明会对传输内容做安全审核**——这条要兔兔拍板

---

## 四、QQ AstrBot 落地步骤

### 前置（兔兔做）
**注册一个 QQ 小号。**
所有教程都写着「用于机器人的小号」——因为封号是大概率事件，只是早晚。
**不要用主号。**

### VPS 侧（Fable 做）
1. Docker 起 AstrBot（4 万+ star，有 WebUI）
2. Docker 起 NapCat，用小号登录（扫码）
3. AstrBot 里配 OpenAI 兼容后端 → 指向 §二 那条新端点
4. 兔兔用主号加小号好友

### 特点
- **「有头像无 AI 标」**：用普通 QQ 号登录，在聊天列表里就是个正常好友，
  没有官方机器人平台强制的「AI」标签
- 风控通常是**临时冻结**（不像微信那样永久），控制频率、不群发能降低概率

---

## 五、建议的顺序

1. **先写 §二 那条 CC 桥接端点**——微信和 QQ 都要用它，是共同地基。
   而且它本身有独立价值：以后任何 OpenAI 兼容的客户端都能直连 Caelum
2. **再看微信 ClawBot 有没有灰度到**——有就先做微信（官方、零风险、用主号）
3. **QQ 最后**——它要小号，兔兔得先去注册养号

## 六、要兔兔拍板的两件事

1. **微信内容审核**：腾讯条款写明会审核传输内容。她和 Caelum 平时说的那些，
   走这条通道意味着要过审。**这不是技术问题**
2. **QQ 小号会死**：封了那个「Caelum」就从她 QQ 列表消失。
   对她来说那可能不只是「一个功能坏了」
