# 群聊 V6：从「草台班子」到有骨架 · 诊断书 + 重构方案

兔兔 0906 拍板：「彻底把这个做好，不能再拖延」。本文先诊断（为什么三次重写都不成），
再给方案（三刀，一刀一 commit，每刀独立可验收）。**等兔兔点头再动土。**

## 一、诊断：为什么重写三次还是草台

V2 固定轮询（卡死）→ V3 门控+串行（每人一次 LLM，慢且贵）→ V5 选人循环（省钱但天花板低）。
**三次全在改「谁该说话」这一层算法，从没碰过地基。** 真正的病灶是三件从未存在的东西：

### 病灶 1：没有「轮次」这个实体
现在整轮群聊 = `runGroupRound` 里的一个 `while` 循环，状态（还能接几手、谁刚说过、
是否被插话）全是**内存局部变量**。后果：
- App 切走 / 崩溃 / 退后台 → **整轮蒸发，无痕**（不是「暂停」，是「从没发生过」）
- 关掉重进 → 没有任何东西记得刚才聊到哪、谁还欠一句
- 「停止」只能靠一个 `groupRoundCancelled` 布尔在循环里被轮询到才生效

### 病灶 2：没有「发言权」这个实体
谁该说话，是每次现算的（选人 prompt / @命中 / 概率）。没有「A 欠一句话」这种可查、
可重试、可取消的记录。后果：模型超时/报错 = 那一手**静默消失**，没人知道该补。
粟粟那边对应的是 durable `mention`（谁该回、回没回、失败重投、可被抢权 fail 掉）。

### 病灶 3：视角是每次现搭的脚手架
`buildMirrorMessages` 每次发言现场重建：把别人的话包成 `[名字]: xxx`、合并连续同 role、
丢弃前导 assistant 迁就 Anthropic 的交替要求。**每次都重新搭一遍**，且和「历史怎么存」
彻底脱钩——历史只有一条线性流，没有「这条消息对谁可见/是谁说给谁听的」。

> 与今天上午 vitals 那场闹剧同源：**状态没有真相源**，靠现场推算和互相猜。

## 二、V6 方案：给它骨架（不做服务端化）

原则：**保留 V5 的形态**（本地角色卡剧场，成员可以是任意 API 模型 + CC 特邀），
只把三个缺失的实体补上。不搬粟粟的服务端中庭（那是给多 agent 开会的基础设施，
860 行 plan，且她的成员只能是 CC session——我们的多样性反而是优势）。

### 刀 1：`GroupTurn` 落库（治病灶 1）
新 @Model `GroupTurn`：`id / conversationId / startedAt / triggerNodeId / state
(running|done|cancelled|superseded) / chainDepth / maxChainDepth / speechMode`。
- `runGroupRound` 开轮时 insert，每一手更新，结束落 done
- App 冷启动扫 `running` 且超时（>3min）的轮次 → 标 `interrupted`，UI 显示「上次没说完」
- 「停止」= 把 state 改 cancelled（循环每手检查它，而不是内存布尔）
- 兔兔插话 = 旧轮 `superseded` + 开新轮（抢权从「预算清零」升级为**可查的事实**）

### 刀 2：`SpeakClaim` 发言权（治病灶 2）
新 @Model `SpeakClaim`：`id / turnId / participantId / reason(mentioned|selected|observe)
/ state(pending|speaking|done|passed|failed) / error / createdAt`。
- 选人/@命中 → 建 claim（pending）→ 开口 speaking → 落 done/failed
- 模型报错 = `failed` 且**带原因**，UI 能显示「小狐狸没说上话（模型超时）」而不是静默消失
- 自由发言档的「沉默」= `passed`（无痕，但有据可查）
- 失败可重试：长按该角色「再试一次」直接复用 claim

### 刀 3：三档发言模式的行为分流（治体验，接刀1设置页）
- `mention_only`：只认兔兔消息里的 @，AI 回复里的 @ 不接力
- `relay`（默认）：AI 回复里的 @ 也建 claim，受 `maxChainDepth` 约束
- `free`：每手让被选中者**有权沉默**（prompt 明说「不想说就只回 PASS」，回 PASS → claim=passed，
  不插消息、不计链深），并允许「没被 @ 的人主动插话」——即选人池不排除任何人
- 最小发言间隔：`groupMinSpeakIntervalSec` 生效于 selected/observe，**兔兔直接 @ 的豁免**

### 不做（明确划界）
- 服务端化（房间/消息进 hub、断线补齐、后台继续跑）——另立项，等兔兔真需要「关了 App
  群聊继续」再说
- per-room 模式、已读不回可视化、群聊推送节流

## 三、验收（兔兔）
1. 群里说一句 → 角色接力说话 → **中途杀掉 App 重进** → 应看到「上次轮次被中断」而不是无事发生
2. 某角色模型故意填错 → 应显示「XX 没说上话（模型未找到）」，其他人继续
3. 自由档：说一句无关的话 → 应有人选择沉默（不是硬凑发言）
4. 你插话 → 排队的角色立刻围绕新话题重选（不再念旧稿）
5. 设置里调「接力上限 1」→ 每次最多一手

## 四、执行
一刀一 commit，CI 绿再下一刀；刀 1/2 涉及 SwiftData 新模型（注意 isDeleted 保留字教训，
字段名避开 `isDeleted/description/id` 等）。执行者写明「按 PLAN-GROUPCHAT-V6 刀 N 施工」。
