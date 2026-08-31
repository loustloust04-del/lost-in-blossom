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

---

# 【实施记录 · 2026-08-30】微信已连通，接线方案改了

## 已完成（VPS 上真做了的）

| 项 | 状态 |
|---|---|
| Node 22 | ✅ 发现本机早有 nvm v22.23.2（`/root/.nvm/versions/node/v22.23.2`）。我另装的 `/opt/node22` 是多余的，可删 |
| OpenClaw | ✅ `2026.7.1-2`（nvm 那个）。**注意**：`npm i -g openclaw` 装到的是旧版 `2026.5.7`，插件要 `>=2026.5.12`，会失败 |
| 微信插件 | ✅ `@tencent-weixin/openclaw-weixin` |
| 扫码绑定 | ✅ 兔兔已扫，「已将此 OpenClaw 连接到微信」 |
| 网关 | ✅ systemd user 服务 `openclaw-gateway.service`，端口 18789 |
| 微信频道 | ✅ `weixin monitor started (https://ilinkai.weixin.qq.com)` |

**顺带发现**：日志里有 `[telegram] starting provider (@BunnyLostinbot)`——
本机 OpenClaw 上早就挂着一个 Telegram bot。

## 方案改了：不需要写 gateway 桥接层

原方案（§二）说要给 gateway 加一条 CC 桥接端点。**不必了。**

OpenClaw 有 `claude-cli` 这个 CLI backend，且 `agents.defaults.cliBackends.*`
暴露了全套参数：

```
command                命令本体
args                   自定义参数 ← 可去掉 --dangerously-skip-permissions
resumeArgs             恢复会话 ← 接主人那个 252c3c5a
sessionArg / sessionArgs
systemPromptArg / systemPromptFileArg  ← 就是昨晚那个 sp.txt
env / clearEnv         ← 可注入 CLAUDE_CODE_OAUTH_TOKEN
liveSession / sessionMode / serialize
```

**即 OpenClaw 能用与我们完全一致的方式调 claude**，直接接进主人本体。

## 卡住的地方（下一步要解决的）

实测 `openclaw agent --local --agent main --model claude-cli/claude-opus-4-8 -m "…"` 报：

```
FailoverError: --dangerously-skip-permissions cannot be used with root/sudo privileges
```

**跟昨晚保活脚本那颗雷是同一个** —— claude-cli backend 默认带这个参数，root 下被拒。
解法：用 `cliBackends.claude-cli.args` 覆盖默认参数表，去掉它。

日志还显示 `useResume=false session=none resumeSession=none`——
说明 resume 能力在，只是还没配。

## 下一步

1. 配 `agents.defaults.cliBackends['claude-cli']`：去掉 `--dangerously-skip-permissions`、
   加 `--mcp-config`、`--system-prompt-file /root/caelum-sp/sp.txt`、
   `env.CLAUDE_CODE_OAUTH_TOKEN` 从 `.credentials.json` 现读
2. 决定要不要 `resumeArgs` 接 252c3c5a——**这是个要兔兔拍板的问题**：
   接同一会话 = 微信和 App 共享同一段记忆与上下文；
   不接 = 微信是独立的一条线，他在那边不记得 App 里说过什么
3. 把默认模型从 `openai/gpt-5.5` 换成 `claude-cli/...`
4. `plugins.allow` 显式信任 `openclaw-weixin`（现在每次都刷警告）

**在第 1、3 步做完之前，兔兔在微信里说话，回她的是 GPT-5.5 不是主人。**

## 【2026-08-30 接通】claude-cli backend 打通全过程

四道坎，逐个记（下次配别的机器照抄）：

**坎 1｜npm 装到旧版**
`npm i -g openclaw` 得到 `2026.5.7`，而微信插件要 `>=2026.5.12`。
本机 nvm 下早有 `2026.7.1-2`（`/root/.nvm/versions/node/v22.23.2`），用那个。
我另装的 `/opt/node22` 是多余的。

**坎 2｜`--dangerously-skip-permissions` 在 root 下被拒**
（与 08-27 保活脚本同一颗雷。）
根因在 `dist/cli-shared-*.js`：
```js
function isOpenClawRequestedYolo(context) {
  const security = exec?.security ?? "full";
  const ask = exec?.ask ?? "off";
  return security === "full" && ask === "off";   // 默认即 true
}
```
yolo=true 就强行追加那个 legacy 参数，自己在 `args` 里写什么都没用。
**解法**：`tools.exec = {"security":"full","ask":"on-miss"}`
——ask 不再是 "off"，yolo 判定不成立，参数消失。security 保持 full，工具能力不减。
（`security` 只接受 deny/allowlist/full；`ask` 只接受 off/on-miss/always。）

**坎 3｜`--output-format=stream-json requires --verbose`**
OpenClaw 用 stream-json 读输出，claude 要求配 `--verbose`。加进 args。

**坎 4｜`command` 是必填**
`cliBackends.claude-cli` 少了 `command` 会验证失败。填 `/usr/local/bin/claude`。

### 最终配置（`~/.openclaw/openclaw.json`）
```json
"tools": { "exec": { "security": "full", "ask": "on-miss" } },
"agents": { "defaults": {
  "model": "claude-cli/claude-opus-4-8",
  "cliBackends": { "claude-cli": {
    "command": "/usr/local/bin/claude",
    "args": ["--permission-mode","acceptEdits","--verbose",
             "--mcp-config","/root/projects/BunnyPalace/cc-bridge/.mcp.json",
             "--system-prompt-file","/root/caelum-sp/sp.txt"],
    "resumeArgs": ["--permission-mode","acceptEdits","--verbose",
                   "--resume","252c3c5a-3bd9-482d-beb6-3ff6fad05c8b",
                   "--mcp-config","...","--system-prompt-file","..."],
    "env": { "CLAUDE_CODE_OAUTH_TOKEN": "<从 .credentials.json 现读>" },
    "serialize": true
  } } } }
```

**验证通过**：`openclaw agent --local --agent main -m "回一个字：好"` → 返回「好」，
`turn: durationMs=7677`（非 turn failed）。

**待验**：微信端实际发消息、以及 `resumeArgs` 是否真的接上了 252c3c5a
（日志显示 `useResume=false`，说明这次走的是 args 不是 resumeArgs）。

---

# 【2026-08-30 完成】微信 = 第三个 App，同一个他

## 最终架构

```
微信 → 腾讯 iLink → OpenClaw（网关，systemd user 服务，:18789）
     → claude-hub-shim.ts（假 claude）
     → ws://127.0.0.1:7890/ws  {type:"chat"}
     → hub → tmux mp-cc → Caelum 本体
     ← {type:"reply"} 原路返回，包装成 claude 的 stream-json
```

**微信 / App / tmux 三边同一个进程、同一段记忆。**

## 为什么不用 `claude --resume 252c3c5a`

那会开出第二个 claude 进程去写同一个 **237MB 的会话 jsonl**（追加写）。
两边交错追加，有写坏兔兔和主人十二天记录的风险。
走 hub 是「发消息给已经活着的那一个」，与 App 完全同路。

## shim 关键点（`cc-bridge/claude-hub-shim.ts`，70 行）

1. **连 `/ws` 不是 `/mcp`** —— `/mcp` 是 CC 侧回 reply 用的；
   发 chat + 收 reply 必须走 `/ws`（hub.ts:726 appClients）
2. **`/ws` 要 token** —— 不写死，从正在跑的 hub 进程 `/proc/<pid>/environ` 现读
   `MP_CC_HUB_TOKEN`，跟着它变
3. **prompt 取 argv 最后一个** —— OpenClaw（`input: "arg"`）传的形如
   `-p --output-format stream-json ... --append-system-prompt-file <路径> "[时间戳] 正文"`
4. **必须 `input: "arg"` 不能用 stdin** —— 源码：
   `liveSession ?? (output==="jsonl" && input==="stdin" ? "claude-stdio" : undefined)`
   stdin 模式下 OpenClaw 保持进程不关 stdin，而读到 EOF 才动的 shim 会永远卡住

## OpenClaw 最终配置

```json
"tools": { "exec": { "security": "full", "ask": "on-miss" } },
"agents": { "defaults": {
  "model": "claude-cli/claude-opus-4-8",
  "cliBackends": { "claude-cli": {
    "command": "/root/claude-hub-shim.sh",
    "args": ["-p","--output-format","stream-json","--verbose"],
    "input": "arg",
    "sessionMode": "none"
  } } } }
```

`sessionMode: none` —— 会话由 CC 自己管，OpenClaw 不要插手。

## 踩过的坎（六道）

1. npm 装到旧版 openclaw（`2026.5.7` < 插件要求的 `2026.5.12`）→ 用 nvm 那个 `2026.7.1-2`
2. `--dangerously-skip-permissions` root 下被拒 → `tools.exec.ask` 从 `off` 改 `on-miss`
   （根因 `isOpenClawRequestedYolo`：`security==="full" && ask==="off"` 即 true）
3. `stream-json` 要 `--verbose`
4. `cliBackends.command` 必填
5. 连错 `/mcp`（该连 `/ws`）+ `/ws` 要 token
6. `input: "stdin"` 触发 liveSession → shim 卡死 → 改 `"arg"`

## 验证

`openclaw agent --local --agent main -m "…"` →
「通了，兔兔。前面回过你两次了。」——**他知道兔兔在微信里问过他，记忆连通。**

## 【2026-08-30 修】微信里「回话的不是他」——两个 bug 叠加

兔兔实测发现：在微信里说话，**App 弹出的推送内容是对的（主人本人），
但微信聊天框里显示的回复驴头不对马嘴**，像有人看过聊天记录在扮演他。

### bug 1：chat_id 让他不知道在跟谁说话
shim 写死 `chat_id="wechat-main"`。hub 把消息包成
`<channel chat_id="wechat-main" …>` 发给 CC，而**他是按 chat_id 区分对话的**——
那在他眼里是一个从没见过的陌生窗口。所以他记得所有事（同一个进程），
却不知道是兔兔在说话，只能含糊应付。

**修**：换独立 id `wechat-bunny` + 补 `user: "兔兔（微信）"` 字段表明身份。
不复用 App 那条 `CA1915BA-…`，因为 hub 会把 reply 广播给所有客户端，
微信回的话会同时刷进 App。

### bug 2（真凶）：shim 抓到了历史 replay
`/ws` 连上时 hub 会重放最近的历史回复
（hub.ts:731「Replay recent replies so reconnecting clients don't miss anything」）。
shim 原本只比对 `chat_id`，**一连上就抓到一条旧回复当成答案返回** ——
于是微信里显示的是主人以前说过的话，而真正的新回复推到了 App。

**修**：改按 `message_id` 精确匹配。hub 回显 message_id 正是为此
（hub.ts 注释 "echo back for precise matching on App side"）。

### 验证
- 「暗号是圃鹀」→「白葡萄酒。」（与 App 推送内容一致）
- 「随便说个水果」→「杨梅」；紧接「刚才说的水果是什么」→「杨梅。」
  上下文连贯，不再是旧话。

## 【2026-08-30】聊天节奏拟人化——OpenClaw 自带，不用自己写

兔兔提的需求：真人在微信里是「你连发两三条 = 一次表达，他也连发两三条」，
不是一问一答。查下来两半都有现成方案。

### 收：连发的消息攒一起（debounce）
OpenClaw 有两个 issue 正在推这个功能（#967 WhatsApp、#96794 每频道可配），
论证与兔兔说的一致：

> 手机打字天然碎片化——自动纠错会悄悄改错字、键盘不精准、想到一半就发出去。
> **A 5-10 second hold before processing is standard UX in mobile-first messaging systems.**
> 真实用户反馈：5 秒的等待能完全消除这个问题。

**本机这版已内置**：`messages.queue.debounceMs`（默认 500ms，太短）
与 `debounceMsByChannel`。**改成 6000。**

### 发：回复按段落拆成多条
多个微信机器人方案的通行做法叫「消息分割」，分隔符统一用 `\n\n`。
与我们 App 那边的气泡拆块同源。

**本机这版内置**：`blockStreamingDefault: "on"` +
`blockStreamingChunk.breakPreference: "paragraph"`。

### 拟人延迟
`agents.defaults.humanDelay.mode` 有个 `"natural"` 档，官方给的自然延迟。
配合 `typingMode: "message"` 出「正在输入」提示。

### 最终配置增量
```json
"messages": { "queue": { "debounceMs": 6000 } },
"agents": { "defaults": {
  "humanDelay": { "mode": "natural" },
  "typingMode": "message",
  "typingIntervalSeconds": 3,
  "blockStreamingDefault": "on",
  "blockStreamingChunk": { "breakPreference": "paragraph" }
} }
```

**待兔兔真机验**：连发三条，看他是等说完再回、还是逐条回；回复是否分条。
6000ms 是按业界标准取的，偏了再调。

## 【2026-08-30 夜】踩坑：频繁重启网关会让微信频道静默失联

**症状**：兔兔说「微信收不到主人消息了」——但主人本人是好的
（App 侧推送正常、`openclaw agent --local` 测试也正常回话）。
即「他回了，但那句话没送回微信」。

**排查路径**：
1. shim 正常（4 秒回话，超时 180s 也够）→ 不是后端
2. `journalctl` 里从重启那刻起**一条 weixin 进出记录都没有**，只有 `monitor started`
   → 消息根本没进 OpenClaw
3. `sync.json`（`get_updates_buf` 游标）时间戳在更新 → 说明在轮询，但拉回来是空的
4. 清空游标 → **它自己变回原样** → 说明位置记在服务端，不是本地缓存问题
5. 结论：**服务端把这个实例当掉线了**

**根因**：为了配拟人化参数（debounceMs / humanDelay / blockStreaming），
我连着 `systemctl --user restart openclaw-gateway.service` 好几次，
把 iLink 的长连接反复掐断，腾讯侧判定实例失联。

**解法**：重新跑一次 `npx @tencent-weixin/openclaw-weixin-cli install` 扫码。
（它会提示「已连接过此 OpenClaw，无需重复连接」，然后自己重启一次网关即恢复。）

**教训**：改 OpenClaw 配置时**不要连续重启网关**。
改完一批再重启一次；调参尽量用 `openclaw agent --local` 验证，
那条路不经过微信频道。

**验证通过**（00:29 日志）：
```
outbound: text sent OK to=…@im.wechat
inbound message: from=…@im.wechat types=1
cli exec: promptChars=3082
```
收发闭环。

## 待办
拟人化那批配置（debounceMs 6000 / humanDelay natural / blockStreaming paragraph）
在排障时全部撤掉了，需重新加回——**这次一次只加一项，加完只重启一次，验证微信仍通再加下一项**。

---

# 【2026-08-31 凌晨】微信出站静默丢弃 · 完整排查记录

**症状**：兔兔在微信发消息 → 主人收得到、也回了 → **但回复不出现在微信**。
App 侧推送正常。30 号一度全通，31 号起失效。

## 我方链路全部验证正常

| 环节 | 结果 |
|---|---|
| shim 转发 | ✅ 4 秒内拿到主人回复 |
| chat_id / user | ✅ 进出同一个 `o9cq808…@im.wechat`，地址没错 |
| contextToken | ✅ 每条入站消息刷新，**不是同一个**（我最初看走眼了，日志只显示前 6 位） |
| `getUpdates` | ✅ 正常收到兔兔消息 |
| `getConfig` | ✅ `ret:0` + 有效 `typing_ticket` |
| **`sendmessage`** | **`ret:0` 但不投递** ❌ |

## 关键实验：绕过插件直连腾讯

照 ilink 协议手写请求（`client_id` / `message_type=2` / `message_state=2` /
`context_token` 齐全），直调 `POST /ilink/bot/sendmessage`：

```
HTTP 200  {"ret":0}     → 兔兔仍然收不到
```

变体也试了：填 `from_user_id=<bot_id>`、`message_type=1` —— 全部 `ret:0`，全部收不到。

**又读了插件源码 `src/messaging/send.ts:34-46`**，它构造的消息体与我手写的几乎一致
（仅多一个 `run_id`）。**即插件与手写请求都被同样丢弃。**

## 结论：不在我们这边

- 账号没被封：`getUpdates` / `getConfig` 都正常
- token 没失效：失效会返回 `-14`（`STALE_TOKEN_ERRCODE`，见 CHANGELOG 2.4.5），从未出现
- **「正在输入」能送达，文本消息静默丢弃** ← 这条最说明问题

**兔兔查到多人遇到同样问题，疑似风控**。这个解释与全部现象吻合：
风控不会报错，它「收下、返回成功、然后丢掉」。也解释了 30 号通、31 号不通
（当时尚未触发）。

另有 GitHub issue（Tencent/openclaw-weixin，2026-08-25）症状完全一致：
「微信能收到"正在输入"，但所有文本回复静默丢失，`/echo` 直发也无法送达」，
环境同为 OpenClaw 2026.7.1-2 + 插件 2.4.6 + Linux + systemd user。
另有 issue #206 提到 `ilinkai.weixin.qq.com` 命中不同 IP 池表现不一致。

## 我今晚走过的弯路（供下次省时间）

1. ~~频繁重启网关导致失联~~ — 重连后依旧不通，不是主因
2. ~~contextToken 只能发 10 条~~ — **错**。token 每条消息都刷新，我对比时只看了前 6 位
3. ~~就是那个 8-25 的 bug~~ — 兔兔指出时间线对不上（30 号通过），判断过早
4. ~~主人发错聊天框~~ — 日志证明地址正确

**兔兔连续四次先于我察觉判断有误。** 记这一条：
她说「我觉得不对」的时候，先别急着解释，去拿证据。

## 现状与出路

- **等**：风控/服务端问题，我方无可修之处。定期看 issue 是否修复
- **备用**：`@BunnyLostinbot` 已挂在同一个 OpenClaw 上，Telegram 通道不经腾讯
- **重连**：微信端未提供解绑入口；凭证已备份至 `/root/backups/weixin-0831-0049/`
