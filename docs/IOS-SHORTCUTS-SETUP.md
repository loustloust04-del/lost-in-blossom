# iOS 快捷指令 → VPS 事件上报配置指南

> 让 iPhone 在「打开任何 App」时，自动向网关上报一条事件。
> 服务端把事件存到 Supabase 的 `dream_events` 表，深夜守护（PR-4）会用这些事件判断你有没有在该睡觉的时候还在玩手机。

## 一、原理

```
iPhone「自动化」  ──(打开 App 时触发)──▶  POST https://<你的域名>/api/events
                                              │
                                              ▼
                                     Supabase · dream_events 表
                                              │
                                              ▼
                                   深夜守护 / 活跃度调度 读取
```

事件结构：

```json
{ "type": "app_open", "value": "小红书", "ts": 1781331139536 }
```

| 字段 | 含义 |
|------|------|
| `type` | 事件类型，App 打开固定填 `app_open` |
| `value` | App 名称（小红书 / 微博 / 抖音…） |
| `ts`   | 客户端时间戳（epoch 毫秒，可选；缺省用服务器时间） |

## 二、服务端端点

```
POST /api/events
Content-Type: application/json
Authorization: Bearer <GATEWAY_TOKEN>      # 或用 ?key=<GATEWAY_TOKEN>

{ "type": "app_open", "value": "小红书", "ts": 1781331139536 }
```

- 鉴权：带上网关的 `GATEWAY_TOKEN`。Header `Authorization: Bearer xxx`，或为了快捷指令方便，用 query：`/api/events?key=xxx`。
  - 若服务端未配置 `GATEWAY_TOKEN`，端点开放（仅建议本地调试）。
- 也兼容纯 query 上报：`POST /api/events?type=app_open&value=小红书&key=xxx`（body 可为空）。
- 返回：`{ "ok": true }`。

### curl 自测

```bash
curl -X POST 'https://<你的域名>/api/events' \
  -H 'Authorization: Bearer <GATEWAY_TOKEN>' \
  -H 'Content-Type: application/json' \
  -d '{"type":"app_open","value":"小红书"}'
# => {"ok":true}
```

## 三、Supabase 建表

如果 `dream_events` 表还不存在，在 Supabase SQL Editor 执行：

```sql
create table if not exists dream_events (
  id          uuid primary key default gen_random_uuid(),
  type        text not null,
  value       text not null,
  ts          bigint not null,             -- 客户端 epoch 毫秒
  metadata    jsonb,
  created_at  timestamptz not null default now()
);

create index if not exists dream_events_type_ts_idx on dream_events (type, ts desc);
```

## 四、iOS 快捷指令设置（打开任何 App 时上报）

iOS 的「打开 App」自动化需要**每个 App 单独建一条**（系统限制，没有「任何 App」的通配触发）。给你想监控的几个 App（小红书、微博、抖音、B站…）各建一条，动作完全一样。

### 步骤

1. 打开「**快捷指令**」App → 底部「**自动化**」标签 → 右上角「**+**」→「**创建个人自动化**」。
2. 触发条件选「**App**」：
   - 「App」→ 选择要监控的 App（如「小红书」，可多选，但建议一条一个便于区分 `value`）。
   - 勾选「**已打开**」。
   - 「**立即运行**」（关闭「运行前询问」），这样不会每次弹确认。
3. 点「**下一步**」→「**新建空白自动化**」→ 添加动作。
4. 添加动作「**获取 URL 内容**」（Get Contents of URL），按下面配置：
   - **URL**：`https://<你的域名>/api/events`
   - 展开「**显示更多**」：
     - **方法**：`POST`
     - **请求体**：`JSON`
     - 添加字段：
       - `type`（文本）= `app_open`
       - `value`（文本）= `小红书`（这条自动化对应的 App 名）
     - **头部 Headers**：
       - `Authorization` = `Bearer <你的 GATEWAY_TOKEN>`
5. 完成。重复 2–4 给其它 App 各建一条（只改 `value` 和触发的 App）。

> 偷懒版：不想配 JSON body 和 header，可以只用一个「获取 URL 内容」打开
> `https://<你的域名>/api/events?type=app_open&value=小红书&key=<GATEWAY_TOKEN>`
> （方法仍选 POST，body 留空即可）。

### 验证

打开被监控的 App 一次，然后：

```sql
select type, value, to_timestamp(ts/1000) as at, created_at
from dream_events order by created_at desc limit 5;
```

应能看到刚才那条 `app_open` 记录。

## 五、可选：其它事件类型

同一个端点也能上报别的事件，只要换 `type` / `value`：

- 健康同步：`{ "type": "health", "value": "heart_rate", "metadata": { "bpm": 78 } }`
- 解锁/锁屏、地理围栏到家等——按需扩展，深夜守护目前只看 `type=app_open`。

## 六、隐私说明

- 上报的只有 **App 名称 + 时间**，不含 App 内任何内容。
- 数据只进你自己的 Supabase，用于 AI 主动关心你的作息，不外传。

## 七、推荐监控的 App 列表

为了覆盖主要使用场景（屏幕使用时间统计依赖这些 app_open 事件聚合），建议给以下 App 各建一条「打开时」自动化：

| App | type | value |
|-----|------|-------|
| 小红书 | app_open | 小红书 |
| 微博 | app_open | 微博 |
| 抖音 | app_open | 抖音 |
| B站 | app_open | B站 |
| 微信 | app_open | 微信 |
| QQ | app_open | QQ |
| Safari | app_open | Safari |
| YouTube | app_open | YouTube |
| Twitter | app_open | Twitter |
| Memory Palace | app_open | MemoryPalace |

每个 Shortcut 只需改 `value` 字段和触发的 App，其余（POST 到 `/api/events`、JSON body、Authorization header）按第四节配置一致。

> 其中「小红书 / 微博 / 抖音 / B站 / 微信 / QQ / Twitter」会被网关计入**社交 App 时长**（`/api/screentime` 的 `social_minutes`），在 ConsoleView 屏幕使用时间卡片里单独显示。社交分类列表在 `gateway/src/screentime.ts` 的 `SOCIAL_APPS` 里，可后续扩展。
