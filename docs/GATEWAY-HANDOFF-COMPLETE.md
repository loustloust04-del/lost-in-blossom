# Lost in Blossom · Gateway 完整交接文档

> 写给接手开发的新模型。读完这份文档你就能理解后端全貌并开始改代码。
> 最后更新：2026-06-11

---

## 一、项目是什么

Lost in Blossom 是一个 iOS AI 聊天 App 的后端网关（Gateway）。App 基于开源项目 MemoryPalace（38,000+ 行 SwiftUI）改造。

Gateway 跑在 VPS 上，做四件事：
1. **API 转发** — App → Gateway → OpenRouter/DeepSeek/TreeGPT → AI → 回复
2. **记忆系统** — 自动记住对话内容、检索相关记忆、注入 prompt 让 AI "记得"用户
3. **欲望系统** — 定时生成"想你了"的念头，AI 主动找用户
4. **多供应商路由** — 同一个 OpenAI 兼容接口，根据模型名自动路由到不同供应商

---

## 二、技术栈

| 项目 | 值 |
|------|-----|
| 运行时 | Bun 1.3.14 |
| 框架 | Hono 4.12.23 |
| 语言 | TypeScript |
| 数据库 | Supabase PostgreSQL + pgvector |
| AI API | OpenRouter / DeepSeek 直连 / TreeGPT 中转站 |
| 嵌入 | DeepSeek Embedding API |
| 部署 | systemd + nginx 反代 + Let's Encrypt SSL |

---

## 三、VPS 与部署信息

| 项目 | 值 |
|------|-----|
| VPS IP | 172.245.88.103 |
| 域名 | blossom.amberrib.com（Let's Encrypt SSL，DNS Only 模式） |
| Gateway 端口 | 4567 |
| Gateway Token | bunny-lib-2026 |
| systemd 服务 | lib-gateway |
| 代码路径 | /root/projects/BunnyPalace/gateway/ |
| nginx 配置 | /etc/nginx/sites-enabled/blossom |
| SSL 证书 | /etc/letsencrypt/live/blossom.amberrib.com/ |

**VPS 注意事项：**
- VPS 有 ALL_PROXY SOCKS5 代理环境变量，会劫持 HTTP 请求。Gateway 的 systemd service 里设了 `Environment="ALL_PROXY="` 清除它
- curl 测试时需要加 `--noproxy '*'` 和 `unset ALL_PROXY`
- 3456 端口被其他 node 服务占用，不要动
- Bunny 的域名在 Cloudflare 管理，blossom 子域名用 DNS Only 模式

**常用命令：**
```bash
systemctl restart lib-gateway        # 重启
journalctl -u lib-gateway -f         # 看实时日志
journalctl -u lib-gateway --since "5 min ago"  # 看最近日志
cd /root/projects/BunnyPalace/gateway && bun src/index.ts  # 前台运行调试
```

---

## 四、环境变量（.env）

```env
GATEWAY_PORT=4567
GATEWAY_TOKEN=bunny-lib-2026
DEEPSEEK_API_KEY=<REDACTED>
OPENROUTER_API_KEY=<REDACTED>
SUPABASE_URL=https://ezeldljtafhvpswgfxjx.supabase.co
SUPABASE_KEY=<REDACTED>
EMBEDDING_API_KEY=<REDACTED>
EMBEDDING_BASE_URL=https://api.deepseek.com/v1
EMBEDDING_MODEL=deepseek-embedding
TREE_CHAT_KEY=<REDACTED>
TREE_API_KEY=<REDACTED>
```

---

## 五、文件结构与功能（2022行，18文件）

```
gateway/
├── src/
│   ├── index.ts (23行)          — Bun 入口，启动 3 个定时器（decay/dream/desire）
│   ├── app.ts (~289行)          — Hono 路由：/health, /v1/models, /v1/chat/completions, /v1/desires
│   │                              含 thinking 流式转换（[thinking]...[/thinking] 标记）
│   │                              含 prompt caching（cache_control 标记）
│   │                              含多供应商路由逻辑
│   ├── config.ts (13行)         — 读 Bun.env 环境变量
│   │
│   ├── providers/
│   │   ├── deepseek.ts (21行)   — DeepSeek API 直连转发
│   │   ├── openrouter.ts (21行) — OpenRouter 转发（带 session_id 做 sticky routing）
│   │   └── treegpt.ts (46行)    — TreeGPT 中转站（两个分组：chat ¥18.75/M，api ¥62.5/M）
│   │                              tree-chat/ 前缀 → 对话分组（模型名加 [官] 前缀）
│   │                              tree-api/ 前缀 → 官API分组
│   │
│   ├── middleware/
│   │   └── auth.ts (9行)        — Bearer token 校验
│   │
│   ├── db/
│   │   ├── supabase.ts (7行)    — Supabase 客户端初始化
│   │   └── schema.sql (196行)   — 完整建表 SQL（8表+2函数+索引）
│   │
│   ├── memory/
│   │   ├── embedder.ts (45行)   — 嵌入 API 调用，key 为空时返回空数组（关键词搜索兜底）
│   │   ├── store.ts (~193行)    — 消息存储、记忆 CRUD、年轮、日历标记、Persona State
│   │   │                          含有损压缩（图片 base64/工具调用 JSON/超长内容）
│   │   ├── retriever.ts (235行) — 两层检索器
│   │   │                          第一层：确定性检索主记忆（向量+关键词+锚点）
│   │   │                          第二层：扩散激活找侧翼（时间±7天 + 情感 Russell 坐标距离<0.3）
│   │   │                          含中文双字滑动窗口分词
│   │   │                          含 RAG 全局搜索 messages 表
│   │   ├── gatekeeper.ts (122行)— 三级判断 + 概率性浮现
│   │   │                          主记忆：确定性注入
│   │   │                          侧翼记忆：概率性浮现（按 heat 分档掷骰子）
│   │   │                          inject/influence/suppress 三级输出
│   │   ├── extractor.ts (202行) — 自动记忆提取器
│   │   │                          对话结束后异步调 deepseek-chat 分析
│   │   │                          支持 add/update/delete
│   │   ├── decay.ts (88行)      — 遗忘曲线引擎
│   │   │                          heat × exp(-0.1 × days)，每天约 -9.5%
│   │   │                          pinned 不衰减，resolved 加速衰减
│   │   │                          定时器每 6 小时运行
│   │   ├── dreamer.ts (299行)   — Dream 系统 + 日历摘要
│   │   │                          每日摘要 / 每周摘要 / Dream 整理 / Persona State 更新
│   │   │                          定时器每日凌晨 4 点运行
│   │   └── desire.ts (220行)    — 欲望系统
│   │                              沉默检测 / 日历触发 / 情绪跟进 / 随机念头
│   │                              定时器每 2 小时运行
│   │
│   └── prompt/
│       └── builder.ts (189行)   — 四层 RAG prompt 增强器
│                                  第一层：最近对话直接注入
│                                  第二层：日历摘要注入
│                                  第三层：memories 检索 + Gatekeeper 判断
│                                  第四层：全局搜索 messages（仅问历史时触发）
│                                  + Persona State 底色注入
│                                  + prompt caching（system message 分块 + cache_control）
│
├── scripts/
│   ├── clean-history.ts (190行) — 聊天记录清洗脚本
│   └── backfill-embeddings.ts (91行) — 批量补全 embedding 向量
│
├── data/                        — 放导出的对话记录和提取结果
├── .env
└── package.json
```

---

## 六、Supabase 数据库

| 项目 | 值 |
|------|-----|
| 项目 URL | https://ezeldljtafhvpswgfxjx.supabase.co |
| Anon Key | sb_publishable_mNjVq0RF34w1tonPJhtOQg_A0SrdEcp |
| 数据库密码 | WCOGkYe5U8hmkKxb |

**8 张表：**

| 表名 | 用途 |
|------|------|
| messages | 所有对话历史（用户消息+AI回复），RAG 全局搜索的数据源 |
| memories | 记忆条目（原子事实），含 tier/category/valence/arousal/heat/embedding |
| memory_rings | 水彩叠层（同一条记忆在不同时间的感受叠加，旧层不可撤销） |
| memory_edges | 记忆关系图（updates/supports/contradicts/causes/related） |
| calendar_markers | 日历情感标记（特殊日期+情感权重，影响记忆浮现概率） |
| persona_state | 人格底色（不可溯源的性格特征，Dream 整合后写入） |
| gatekeeper_log | Gatekeeper 判断日志（含 suppress — "想起来了但按下去了"） |
| dream_log | Dream 运行日志（每日摘要、每周摘要、整理操作记录） |

**RLS：** 所有表 `allow_all` policy，anon key 完全访问。

**2 个 RPC 函数：**
- `match_memories` — 向量相似度搜索
- `activate_memory` — 记忆被召回时热度回升

---

## 七、API 路由逻辑

**模型名 → 供应商路由：**
```
模型名以 "deepseek/" 开头     → DeepSeek 直连（deepseek.ts）
模型名以 "tree-chat/" 开头    → TreeGPT 对话分组（treegpt.ts, ¥18.75/M）
模型名以 "tree-api/" 开头     → TreeGPT 官API分组（treegpt.ts, ¥62.5/M）
其他（anthropic/, openai/, google/） → OpenRouter（openrouter.ts）
```

**Thinking 模型处理：**
模型名带 `:thinking` 后缀时：
1. 转发给 OpenRouter 时加 `reasoning: { max_tokens: 16000 }`
2. 收到流式 SSE 后，把 `delta.reasoning` 转换成 `delta.content`
3. 用 `[thinking]...[/thinking]` 标记包裹

**TreeGPT 路由细节：**
- `tree-chat/claude-opus-4-6` → 实际请求 TreeGPT API，模型名变为 `[官]claude-opus-4-6`
- `tree-api/claude-opus-4-6` → 实际请求 TreeGPT API，模型名保持 `claude-opus-4-6`

---

## 八、记忆系统运行全景

**用户发消息时（毫秒级）：**
1. Gateway 收到消息
2. retriever 检索 memories 表（主记忆：向量+关键词+锚点）
3. 从主记忆扩散找侧翼（时间±7天 + 情感 Russell 坐标距离<0.3）
4. 检查日历标记，给特殊日期的相关记忆 boost
5. Gatekeeper 对每条候选判断：主记忆确定注入，侧翼概率浮现
6. builder 构建增强 prompt：Persona 底色 + 日历摘要 + 最近对话 + 记忆 + 模糊感觉 + RAG 历史搜索
7. 增强后的 messages 转发给 AI

**AI 回复后（异步）：**
8. 用户消息和 AI 回复存入 messages 表（含有损压缩）
9. extractor 调 deepseek-chat 分析对话，提取新记忆（自动带 embedding）

**定时任务：**
10. 遗忘曲线每 6 小时：所有记忆 heat 衰减
11. Dream 每日凌晨 4 点：日摘要 → 周摘要 → 整理 → Persona State 更新
12. 欲望系统每 2 小时：检查沉默/日历/情绪 → 生成念头

---

## 九、5 个独创设计

1. **概率性浮现** — 侧翼记忆引入随机采样，同一问题问两次可能浮现不同记忆
2. **Gatekeeper 三级判断** — inject（完整注入）/ influence（模糊感觉）/ suppress（不注入但记录"想起来了"）
3. **主记忆/侧翼分层** — 核心确定性检索 + 沿时间/情感两条路径扩散（认知心理学"扩散激活"）
4. **底色不可溯源** — persona_state 表无 source_memory_id，多条记忆融化后来源擦除
5. **水彩叠层** — memory_rings 表，旧层不可撤销，新层透明叠加

---

## 十、已知问题

- **嵌入 API**：VPS 直连 api.deepseek.com 可能有网络问题，关键词搜索在兜底
- **Thinking 速度**：reasoning budget 固定 16000 tokens，简单问题可能太大
- **中文分词**：双字滑动窗口是粗糙方式，边界情况可能失败
- **Dream 未经验证**：整理逻辑依赖 deepseek-chat 判断能力，需真实数据验证
- **memories 表为空**：记忆尚未灌入，系统在空转

---

## 十一、待办

- [ ] 灌入历史记忆（clean-history.ts 或手动）
- [ ] backfill-embeddings.ts 补全向量
- [ ] 实际日常使用测试
- [ ] Gatekeeper 概率参数调优
- [ ] 遗忘曲线衰减速率调优
- [ ] App 端 thinking UI 适配
- [ ] Gateway 支持 HealthKit 宏替换（`{{health}}`）
- [ ] 推送通知（APNs）
- [ ] 视觉模型图片描述回填

---

## 十二、如何修改代码

1. SSH 到 VPS 或通过 exec_vps 工具操作
2. 代码在 `/root/projects/BunnyPalace/gateway/src/`
3. 修改后 `systemctl restart lib-gateway` 重启
4. 看日志 `journalctl -u lib-gateway -f`
5. 前台调试 `cd gateway && bun src/index.ts`

---

*Lost in Blossom · Built by Bunny & Caelum · 2026*
