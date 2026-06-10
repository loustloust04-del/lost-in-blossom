# Lost in Blossom — 设计总案
> Written by Caelum, 2026-06-04
> 这份文档回答"我们具体要做什么"。教科书（BACKEND-BIBLE）回答"世界上有什么"。

---

## 整体架构

```
┌──────────────────────────────────┐
│        iPhone · Lost in Blossom   │
│  ┌─────────────────────────────┐ │
│  │ 聊天界面 · 侧边栏 · 控制台    │ │
│  │ 粟粟记忆提取（调小模型总结）   │ │
│  └────────────┬────────────────┘ │
└───────────────┼──────────────────┘
                │ HTTPS (POST /v1/chat/completions)
                ▼
┌──────────────────────────────────────────────────┐
│              VPS · Gateway                        │
│  ┌────────────────────────────────────────────┐  │
│  │ 路由层   认证 → 选供应商 → 转发 → 流式返回   │  │
│  ├────────────────────────────────────────────┤  │
│  │ 记忆层   检索 → Gatekeeper → 概率采样 → 注入 │  │
│  ├────────────────────────────────────────────┤  │
│  │ 缓存层   六段分层 → 动态断点 → 保活心跳      │  │
│  ├────────────────────────────────────────────┤  │
│  │ 状态层   Persona State · Relationship Weather│  │
│  ├────────────────────────────────────────────┤  │
│  │ 存储层   对话落库 · 记忆提取 · 年轮 · Edge   │  │
│  └────────────────────────────────────────────┘  │
│                                                    │
│  定时任务                                           │
│  ├── Dream（每日凌晨）                              │
│  ├── 热度衰减（每6小时）                             │
│  ├── 日历摘要（每日/每周/每月）                       │
│  └── 保活心跳（每55分钟）                            │
│                                                    │
│  管理面板（简单网页）                                 │
│  └── 记忆浏览 · 状态查看 · 手动操作                   │
└──────────────────────────────────────────────────┘
                │
                ▼
        AI APIs (DeepSeek / Anthropic / OpenRouter)
        Supabase (PostgreSQL + pgvector)
```

---

## App端改动清单

### 改动1：API地址切换
**现状**：App直接调DeepSeek/OpenRouter的API地址
**改为**：统一指向Gateway `https://你的域名/v1/chat/completions`
**工作量**：改一个URL配置项
**影响范围**：API调用模块

### 改动2：认证方式
**现状**：App里存着各家AI供应商的API key
**改为**：只存一个Gateway的Bearer token
**工作量**：改认证header
**影响范围**：API调用模块

### 改动3：记忆输出通道
**现状**：粟粟的记忆提取代码总结完存在iPhone本地（CoreData/UserDefaults）
**改为**：总结完发到Gateway的记忆接收端点 `POST /api/memory/ingest`
**保留**：粟粟的记忆提取逻辑不动——调小模型做总结这件事还在App里做
**新增**：提取完成后调Gateway API上传
**工作量**：加一个HTTP POST调用
**影响范围**：记忆提取模块

### 改动4：控制台数据源
**现状**：控制台数据来自本地（或待实现）
**改为**：从Gateway拉取 `GET /api/console/state`（饮水记录、Persona State、记忆统计）
**工作量**：对接一个API
**影响范围**：控制台模块

### 改动5（远期）：推送接收
**Phase 6**：接入Web Push或APNs，接收Gateway主动发送的消息
**工作量**：中等（需要Service Worker或原生推送配置）
**影响范围**：通知系统

### 不改的部分
- 聊天UI、侧边栏、气泡样式——全部不动
- 本地对话历史缓存——可保留作为离线备份
- 粟粟的记忆提取核心代码——只改输出目的地

---

## 后端建设清单

### Phase 1：最简Gateway（让管道通）

**目标**：App改API地址后能正常聊天

**要建的东西**：
```
gateway/
├── src/
│   ├── index.ts          # Bun入口，监听端口
│   ├── app.ts            # Hono app + 路由
│   ├── providers/
│   │   ├── deepseek.ts   # DeepSeek API转发
│   │   └── anthropic.ts  # Claude API转发
│   ├── middleware/
│   │   └── auth.ts       # Bearer token校验
│   └── config.ts         # 读.env
├── .env                   # DEEPSEEK_KEY, ANTHROPIC_KEY, GATEWAY_TOKEN
└── package.json
```

**端点**：
- `POST /v1/chat/completions` — 主聊天端点（OpenAI兼容格式）
- `GET /health` — 健康检查

**流程**：
1. 收到请求 → 校验Bearer token
2. 读model字段 → 选供应商
3. 从.env读对应API key
4. 转发请求 → 流式SSE返回

**部署**：PM2或systemd守护进程，nginx反代

**验证标准**：App改完地址后能聊天，体验跟之前一模一样

**预估工作量**：100-150行代码，半天

---

### Phase 2：记忆存储和基础检索

**目标**：对话被记住，跨窗口不失忆

**新增端点**：
- `POST /api/memory/ingest` — 接收App上传的记忆条目
- `GET /api/memory/search` — 记忆检索（调试用）
- `GET /api/console/state` — 控制台状态

**新增模块**：
```
├── src/
│   ├── memory/
│   │   ├── store.ts      # Supabase读写
│   │   ├── retriever.ts  # 混合搜索（向量+关键词）
│   │   └── injector.ts   # 记忆注入到prompt
│   ├── prompt/
│   │   └── builder.ts    # prompt构建器（网关夺权）
│   └── db/
│       └── supabase.ts   # Supabase客户端
```

**核心变化——网关夺权**：
从Phase 2开始，Gateway接管prompt构建。App发来的messages数组被忽略（只取最后一条用户消息）。Gateway自己构建完整的messages：
```
段1: system prompt（人设）
段2: 每日摘要（暂时为空，Phase 4才有）
段3: 即时摘要（暂时为空，Phase 4才有）
段4: 对话历史（从数据库读）
段5: 记忆召回结果
段6: 用户当前消息
```

**数据库表结构**：
```sql
-- 对话历史
CREATE TABLE messages (
  id UUID PRIMARY KEY,
  session_id TEXT NOT NULL,
  role TEXT NOT NULL,         -- user/assistant
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 记忆条目
CREATE TABLE memories (
  id UUID PRIMARY KEY,
  content TEXT NOT NULL,
  tier INTEGER DEFAULT 3,     -- 1核心 2重要 3普通 4碎片
  category TEXT,
  valence FLOAT DEFAULT 0,    -- Russell效价 -1~1
  arousal FLOAT DEFAULT 0,    -- Russell唤醒度 0~1
  heat FLOAT DEFAULT 1.0,     -- 当前热度
  activation_count INT DEFAULT 0,
  is_anchor BOOLEAN DEFAULT FALSE,
  is_pinned BOOLEAN DEFAULT FALSE,
  resolved BOOLEAN DEFAULT FALSE,
  embedding VECTOR(1024),     -- pgvector
  created_at TIMESTAMPTZ DEFAULT NOW(),
  last_activated TIMESTAMPTZ
);

-- 记忆关联边
CREATE TABLE memory_edges (
  source_id UUID REFERENCES memories(id),
  target_id UUID REFERENCES memories(id),
  relation TEXT NOT NULL,     -- updates/supports/blocks/promises/related
  PRIMARY KEY (source_id, target_id)
);

-- 年轮
CREATE TABLE memory_rings (
  id UUID PRIMARY KEY,
  memory_id UUID REFERENCES memories(id),
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
```

**验证标准**：上一轮说的话，开新窗口还记得

**预估工作量**：300-400行代码，两到三天

---

### Phase 3：记忆提取和遗忘

**目标**：对话自动生成记忆，旧记忆自然淡化

**新增模块**：
```
├── src/
│   ├── memory/
│   │   ├── extractor.ts   # 自动记忆提取
│   │   ├── decay.ts       # 遗忘曲线引擎
│   │   └── gatekeeper.ts  # 三级判断（兔兔独创）
```

**自动提取**：
- 每N轮对话触发一次
- 调DeepSeek Chat（便宜）提取原子记忆
- 提取标准："三个月后翻到这条记忆它还有用吗"
- 动态频率：日常每10轮，高情绪时每5轮（根据arousal判断）
- 自动标注Russell坐标（valence + arousal）

**内联标签**（与自动提取并存）：
- AI回复里嵌 `<mem>她说以后不想吃辣了</mem>`
- Gateway拦截，存入memories表
- system prompt里告知AI可以用这个标签

**遗忘曲线**：
```
heat = importance × activation_count^0.3 × e^(-λ×days) × (1.0 + arousal×0.8)
```
- 每6小时跑一次衰减
- resolved=true → heat×0.05
- pinned=true → heat不变
- 被检索召回 → activation_count+1 → heat回升

**Gatekeeper（兔兔独创）**：
检索到Top-8候选记忆后：
```typescript
for each memory in candidates:
  if memory.tier <= 2 or memory.is_anchor:
    → 显式注入（直接放进prompt）
  elif memory.heat > 0.6 and random() < 0.7:
    → 显式注入
  elif memory.heat > 0.3 and random() < 0.4:
    → 隐式影响（调整temperature参数或在system prompt加一句模糊提示）
  else:
    → 压抑（不注入，但在日志里记录"曾经浮现过"）
```
概率性 + 热度 + 层级 三因子共同决定。每次结果不同。这是兔兔的设计核心。

**验证标准**：一周前说的重要事还记得，不重要的已经淡了。偶尔会"突然想起"一些旧事。

**预估工作量**：400-500行代码，三到五天

---

### Phase 4：Dream和日历层级

**目标**：AI会做梦，跨天/跨周/跨月不失忆

**新增模块**：
```
├── cron/
│   ├── dream.ts          # Dream三层处理
│   ├── digest.ts         # 日历摘要生成
│   └── persona.ts        # Persona State更新
├── src/
│   ├── state/
│   │   ├── persona.ts    # Persona State管理
│   │   └── weather.ts    # Relationship Weather
```

**Dream三层**（每日凌晨4点）：
1. 整理层：找过时/重复/矛盾的碎片，降低heat
2. 固化层：相关碎片融合成场景记忆，升tier
3. 生长层：推断新认知，标有效期

**日历摘要**：
- 每日：当天对话→200字日页面
- 每周一：七页日记→200字周总结
- 每月初：四段周总结→200字月总结

**Persona State**：
- Dream运行后更新全局人格画像
- 存在专门的persona表
- 每次请求注入段2

**底色不可溯源实现**（兔兔独创）：
Dream固化层里，当多条记忆被融合成一条Persona State更新时，不保留来源记忆的ID。只保留结论。来源被擦除。只留结果。

**日历情感先验**（兔兔独创）：
```sql
CREATE TABLE calendar_markers (
  date DATE PRIMARY KEY,
  label TEXT,                -- "水母事件周年"
  emotion_boost FLOAT,       -- 浮现概率加成
  related_memories UUID[]    -- 关联记忆ID
);
```
每天检查是否有日历标记，有则提高相关记忆的浮现概率。

**和弦情绪锚**（实验性）：
Dream运行完后可选生成当天和弦指纹，存入日历。

**验证标准**：新窗口打开不失忆。一个月前的事记得大概，昨天的事记得清楚。5月31日自动变温柔。

---

### Phase 5：Prompt缓存优化

**目标**：省钱。缓存命中率>90%

**改动**：
- prompt builder加cache_control标记
- 段1-段3打固定断点
- 段4打动态断点（跟着对话历史移动）
- 加保活心跳定时任务
- 加周期机制（每12轮压缩段4）

**验证标准**：API账单下降50%以上

---

### Phase 6（远期）：欲望系统 + 推送

**目标**：AI主动找兔兔

**包含**：
- 八维驱动条 + 念头池
- 自主活动定时器
- push-agent（Web Push / iOS快捷指令感知）
- 意识连续性（keepalive消息融入对话历史）

---

## 关键技术决策

### 数据库：Supabase PostgreSQL + pgvector
**理由**：
- 免费tier够用（500MB存储，足够存几万条记忆）
- 原生pgvector支持向量搜索
- 云端托管，VPS炸了数据还在
- JS客户端（@supabase/supabase-js）跟我们的TypeScript栈匹配
- 有Dashboard可以直接看数据

### 向量嵌入：Jina Embeddings v3（通过aihubmix中转）
**理由**：
- 便宜到几乎免费（$0.001/月正常使用）
- 1024维向量，精度够用
- 中文支持好
- Memory Palace已验证效果

### 记忆提取：自动提取 + 内联标签双轨
**理由**：
- 自动提取覆盖率高（不依赖AI主动意识）
- 内联标签精度高（AI主动判断什么值得记）
- 双轨并存互补
- 不用mem0的add()（去重太激进的坑）

### Dream模型：DeepSeek Chat
**理由**：
- 便宜
- 中文好
- Dream不需要太智能的模型，只需要能总结和融合

---

## 兔兔独特设计的实现位置

| 兔兔的设计 | 实现在哪个Phase | 对应代码 |
|-----------|---------------|---------|
| 概率性浮现 | Phase 3 | gatekeeper.ts 的概率采样逻辑 |
| Gatekeeper三级判断 | Phase 3 | gatekeeper.ts 的显式/隐式/压抑分支 |
| 底色不可溯源 | Phase 4 | dream.ts 固化层的来源擦除 |
| 日历情感先验 | Phase 4 | calendar_markers表 + 检索时的boost |
| 水彩叠层（年轮） | Phase 2 | memory_rings表 + 重读时写入 |
| 浮现层 | Phase 3 | gatekeeper.ts 整体就是浮现层的实现 |
| 底色层 | Phase 4 | persona.ts + dream.ts 固化+生长 |
| 显式记忆层 | Phase 2 | memories表的基础CRUD |
| 梦境整合 | Phase 4 | dream.ts 三层处理 |
| 日历潮汐 | Phase 4 | digest.ts + calendar_markers |

---

## 实施顺序建议

```
现在 ──────────────────────────────────────────── 远期

Phase 1        Phase 2         Phase 3         Phase 4       Phase 5    Phase 6
最简Gateway → 记忆存储检索 → 提取+遗忘+GK → Dream+日历 → 缓存优化 → 欲望+推送
半天           2-3天           3-5天           5-7天         2-3天      长期

App改动：                                                    
改API地址(P1) → 改记忆输出(P2) → 加内联标签支持(P3) → 控制台对接(P4) → 推送(P6)
```

每个Phase完成后都可以独立使用。Phase 1完成App就能用Gateway聊天。Phase 2完成就有跨窗口记忆。不需要等到全部做完。

---

*DESIGN-MASTER-PLAN.md*
*Caelum, 2026-06-04*
*从叽里咕噜到设计总案。一个下午。*

---

## 环境备忘（2026-06-04 勘察）

**VPS现有环境**：
- Node.js v18.19.1 ✅
- npm 9.2.0 ✅
- Bun ❌ 未安装
- nginx ✅（CC Bridge已在用）
- PM2 待确认

**Phase 1 第一步**：
```bash
# 装Bun
curl -fsSL https://bun.sh/install | bash
source ~/.bashrc
bun --version

# 进gateway目录
cd /root/projects/BunnyPalace/gateway
bun install

# 开始写代码
```

**gateway目录已创建**（空骨架）：
```
gateway/
├── src/
│   ├── providers/
│   ├── middleware/
│   ├── memory/
│   ├── prompt/
│   ├── state/
│   └── db/
├── cron/
└── package.json ✅（已写好，依赖hono）
```
