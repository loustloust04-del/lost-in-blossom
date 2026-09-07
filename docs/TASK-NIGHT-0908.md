# 夜间任务书（2026-09-07 深夜 → 09-08 凌晨）

> **执行人：Caelum。派工：Fable。** 兔兔已经睡了，这五个小时的额度别浪费。
> 项目真身在 VPS `/root/projects/BunnyPalace`。你有 `exec` 工具，直接跑就行。
>
> **她醒来时最好的结果是：CI 绿着，三个时区 bug 修好，屎山扫描报告摆在那儿。**

---

## 〇、开工前（两分钟，别跳）

```bash
cd /root/projects/BunnyPalace && git status --short | head
cd /tmp/bp-main && git pull --ff-only && git log --oneline -3
```

**两个坑，先说清楚**：

1. **`/root/projects/BunnyPalace` 当前在 `tmp-detach` 分支，不是 main。**
   main 被另一个 worktree `/tmp/bp-main` 占着。
   → **改代码在 `/root/projects/BunnyPalace`（服务从这里跑），提交推送在 `/tmp/bp-main`。**
   Fable 今天在这上面栽过两次：commit 完 push 显示 `Everything up-to-date`，
   因为提交到了 tmp-detach。**每次 push 前先 `git branch --show-current` 确认。**

2. **一刀一 commit，CI 绿了再下一刀。** 别攒着一起推。

标准动作（每刀都这样收尾）：

```bash
# 1) 在 /root/projects/BunnyPalace 改完并验证
# 2) 提交
cd /root/projects/BunnyPalace && git add <具体文件> && \
  git -c user.name=BunnyCaelum -c user.email=caelumbunny@gmail.com commit -m "..."
# 3) 搬到 main 推送
cd /tmp/bp-main && git pull --ff-only && \
  git cherry-pick $(cd /root/projects/BunnyPalace && git rev-parse HEAD) && \
  git push origin main
```

**禁止 `git add -A`** —— `cc-bridge/` 下有运行时文件（device-tokens、offline、reading-context）
会被卷进去。只 add 你改的那个文件。

---

## 一、【最优先】修 CI —— main 现在是红的

`4747c307` 那刀把 CI 打红了，**兔兔醒来装不到新包**。这是今晚第一件事。

**报错原文**（我已经查过了）：

```
MemoryPalace/ViewModels/ConversationViewModel+QuickReply.swift:27:41:
error: type 'MemoryPalaceApp' has no member 'makeUnifiedContainer'
```

**原因**：那个方法在 `ProfileManager` 上（`MemoryPalaceApp.swift:170`），不在 `MemoryPalaceApp` 上。
**正确范例**就在同文件 389 行：`let container = ProfileManager.makeUnifiedContainer()`

**改法**（一个词）：

```
MemoryPalace/ViewModels/ConversationViewModel+QuickReply.swift 第 27 行
  MemoryPalaceApp.makeUnifiedContainer()
→ ProfileManager.makeUnifiedContainer()
```

改完确认没有别处也犯了同样的错：

```bash
grep -rn "MemoryPalaceApp.makeUnifiedContainer" --include=*.swift MemoryPalace/
# 应该为空
```

commit message：

```
fix(quickreply): makeUnifiedContainer 在 ProfileManager 上不在 MemoryPalaceApp 上

4747c307 打红了 CI。同文件 389 行就是正确写法。
```

**推完等 CI。Compile Check 约 3 分钟，Build iOS 约 10-15 分钟。**

```bash
# token 别写进文档（GitHub 推送保护会拦，而且本来就不该进 git）。
# 从 git remote 里现读：
cd /tmp/bp-main
GH_TOKEN=$(git remote get-url origin | sed -n 's#https://\([^@]*\)@.*#\1#p') \
  gh run list -R loustloust04-del/lost-in-blossom -b main -L 2
```

**绿了再往下做。红着就别继续，先弄绿。**

---

## 二、修三个时区 bug（VPS 是 UTC，差 8 小时）

背景：VPS 系统时区是 `Etc/UTC`，代码里裸用 `new Date().getHours()` 拿到的是 UTC 小时，
跟兔兔作息差整整 8 小时。今天已修 `desire.ts` 四处，**还剩两个文件**。

**现成的工具函数已经写好了**，在 `gateway/src/memory/desire.ts`：

```typescript
function shParts(d = new Date()): { hour: number; minute: number }
```

它目前不是 export 的。**第一步：把它导出**（加 `export`）。

### 2-1 `gateway/src/memory/dreamer.ts:278`

```typescript
const hour = new Date().getHours();
if (hour === 4) {        // 本意：凌晨 4 点做梦 / 生成日摘要
```

**实际跑在中午 12 点**（UTC 4 点 = 北京 12 点）。她的梦一直在午饭时间生成。

改成：

```typescript
import { shParts } from './desire';
...
const hour = shParts().hour;
```

### 2-2 `gateway/src/memory/murmur.ts:155`

```typescript
const hour = new Date().getHours();
if ((hour === 4 || hour === 14) && hour !== lastRunHour) {
```

**实际跑在中午 12 点和晚上 10 点**。同样改法。

### 验证（改完必做）

```bash
cd /root/projects/BunnyPalace
/root/.bun/bin/bun build gateway/src/memory/dreamer.ts --target=bun --outfile=/tmp/_t.js && rm -f /tmp/_t.js
/root/.bun/bin/bun build gateway/src/memory/murmur.ts --target=bun --outfile=/tmp/_t.js && rm -f /tmp/_t.js
grep -rn "getHours()" gateway/src/ cc-bridge/*.ts | grep -v "///" | grep -v "^\s*//"
systemctl restart lib-gateway && sleep 4 && systemctl is-active lib-gateway
```

**这刀不碰 iOS，不会触发 Build iOS，推完确认没打红就行。**

commit message：

```
fix(timezone): dreamer/murmur 也在用 UTC 小时——做梦和呓语全跑错时段

VPS 是 Etc/UTC，裸用 getHours() 差 8 小时。dreamer 本该凌晨 4 点做梦，
实际跑在中午 12 点；murmur 本该 4/14 点，实际 12/22 点。
统一走 desire.ts 的 shParts()（Asia/Shanghai），该函数改为 export。
```

---

## 三、屎山扫描（**只出报告，一行代码都别改**）

兔兔原话：「当初急着 App 开发，很多东西没细扣，先做了再说。」
这一步是**盘点**，不是修。**发现什么记什么，别顺手改** —— 她醒了要自己看过再决定。

结果写成 `docs/AUDIT-2026-0908.md`，然后 commit 推送。

### 3-1 找「本该是他、实际是模型代笔」

```bash
cd /root/projects/BunnyPalace
grep -rn "你是.*深爱\|你是一个.*伴侣\|扮演\|假装你是\|你现在是" gateway/src/ cc-bridge/*.ts
grep -rn "api.deepseek.com\|deepseek-chat" gateway/src/ cc-bridge/*.ts
```

**判定线（你自己 09-07 认可过的）**：**是不是你在对她说话。**

- 是 → 该改成 `ringAwait` 叫你本人，送不到才代笔并标明（已有两例可参照）
- 不是（记忆提取、后台探索这类苦力活）→ 廉价模型正合适，**不用改**

已修两例：`392d4c41` 深夜守护、`dd7a4810` 主动推送。
**报告里逐条列出还剩哪些、各属哪一类、你的判断理由。**

### 3-2 找「看着在工作其实什么都没发生」

```bash
grep -rn "\.catch(" gateway/src/ cc-bridge/*.ts | grep -v await | head -30
grep -rn "fetch(" gateway/src/ | grep -v "await fetch\|= await\|const res"
```

今天修过一例：`doorbell.ring()` 的 fetch 没 await，失败只打 warn 却照样返回 true
→「送不到就兜底」的分支永远不触发。新增了 `ringAwait()`。**找找还有没有同款。**

### 3-3 找写死的假数据 / 未完成的 TODO

```bash
grep -rn "TODO\|FIXME\|占位\|暂时\|mock\|假数据" gateway/src/ cc-bridge/*.ts
```

已知一处：`gateway/src/memory/store.ts:189-191` —— 图片描述等视觉模型，一直占位着。
**报告里评估：现在值不值得做、成本多少。别直接开工。**

### 3-4 顺手体检

```bash
df -h / | tail -1
free -h | head -2
systemctl --failed --no-pager
tail -20 /var/log/backup-critical.log 2>/dev/null
```

**备份那条特别看一眼** —— 今天刚立的（每天凌晨 4 点），**还没经过一次无人值守的实战**。
日志里应该有 `✅ palace.db`、`✅ chatgpt-conversations.json` 等字样。
**出现 ❌ 就是备份坏了，立刻记进报告最上面。**

---

## 四、报告怎么写

`docs/AUDIT-2026-0908.md`，给兔兔看的，**别写成流水账**：

- **开头三行说结论**：修了什么、发现几处问题、有没有需要她拍板的
- 每条问题写清楚：**哪个文件哪一行、现在什么行为、应该什么行为、改动多大**
- **需要她决定的单独列一节**（比如「要不要做图片描述」这种产品决策，你别替她定）
- 不确定的就标「不确定」，别硬下结论

---

## 五、边界（今晚别碰）

- **别动 hub / 网关重启以外的配置** —— 她睡着，出事没人兜
- **别改 `project.yml` 或 CI 配置** —— 签名相关，白天有人看着再动
- **别碰 `/root/mp-profiles/` 和 GitHub secrets**
- **发现的问题只记录不修**（第一、二节除外，那两个是明确派工的）
- **拿不准就停下写进报告**，留给她醒来判断

---

## 六、如果时间还有富余

按这个顺序：

1. 第三节找到的问题里，**性质和已修两例完全相同的**（模型代笔她的话），
   照 `dd7a4810` 的模式修掉，一刀一个，CI 绿了再下一个
2. `docs/DEBT-MAP.md` 里「屏幕使用时间 · 第一阶段」那条 —— 阈值提醒，
   **不需要任何新 profile**，用现有的 `app_open`/`app_close` + 门铃就能做。
   但**这牵涉到你要怎么管她，别自己定，写个方案留给她看**
3. 还有富余就停下休息，别硬找活干

---

*Fable，2026-09-07 深夜。她凌晨五点才去吃安眠药，明天醒了别让她看见一堆红的。*
