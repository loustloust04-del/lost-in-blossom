# 任务：Screen Time 代理 — 从 app_open 事件聚合屏幕时间

> 写给 CC 的指令。Bunny 验收。

## 背景

iOS 的 Screen Time API 需要 Family Controls entitlement（要向 Apple 申请）。
我们没有这个权限，所以用已有的 iOS Shortcuts 事件上报系统做代理。

**现有设施：**
- iOS 快捷指令在用户打开指定 App 时 POST `{ type: "app_open", value: "小红书" }` 到 `POST /api/events`
- 数据存在 Supabase 的 `dream_events` 表（字段：type, value, ts, metadata）
- iOS App 的 `ScreenTimeClient` 已经写好了读取逻辑，调 `GET /api/screentime`
- iOS App 的 `ConsoleView` 已经有 screen time 卡片 UI（显示总时长 + 社交 App 时长）

**缺失的一块：** Gateway 没有 `/api/screentime` 端点来聚合 `dream_events` 数据。

## 任务 1：Gateway 新增 `/api/screentime` 端点

### 文件：`gateway/src/screentime.ts`（新建）

```typescript
// 从 dream_events 聚合今日屏幕时间

import { supabase } from './db/supabase';

// 社交 App 列表（用于分类统计）
const SOCIAL_APPS = ['小红书', '微博', '抖音', 'B站', '微信', 'QQ', 'Twitter', 'Instagram', 'TikTok'];

interface AppSession {
  app: string;
  sessions: number;
  minutes: number;
}

interface ScreenTimeResult {
  date: string;
  total_minutes: number;
  social_minutes: number;
  apps: AppSession[];
}

export async function getScreenTime(dateStr?: string): Promise<ScreenTimeResult> {
  const date = dateStr || new Date().toISOString().slice(0, 10);

  // 取今天 00:00 ~ 23:59 的所有 app_open 事件，按时间排序
  const dayStart = new Date(date + 'T00:00:00+08:00').getTime(); // 北京时间
  const dayEnd = dayStart + 24 * 60 * 60 * 1000;

  const { data: events } = await supabase
    .from('dream_events')
    .select('value, ts')
    .eq('type', 'app_open')
    .gte('ts', dayStart)
    .lt('ts', dayEnd)
    .order('ts', { ascending: true });

  if (!events || events.length === 0) {
    return { date, total_minutes: 0, social_minutes: 0, apps: [] };
  }

  // 算法：每个 app_open 事件开始一个 session。
  // session 持续到下一个 app_open 事件或 15 分钟超时（取较小值）。
  // 15 分钟超时是因为用户可能锁屏了但没触发新的 app_open。
  const MAX_SESSION_MS = 15 * 60 * 1000; // 15 分钟
  const appMinutes: Record<string, { sessions: number; minutes: number }> = {};

  for (let i = 0; i < events.length; i++) {
    const app = events[i].value;
    const start = events[i].ts;
    const nextTs = i + 1 < events.length ? events[i + 1].ts : start + MAX_SESSION_MS;
    const duration = Math.min(nextTs - start, MAX_SESSION_MS);

    if (!appMinutes[app]) appMinutes[app] = { sessions: 0, minutes: 0 };
    appMinutes[app].sessions += 1;
    appMinutes[app].minutes += duration / 60000;
  }

  const apps: AppSession[] = Object.entries(appMinutes)
    .map(([app, d]) => ({
      app,
      sessions: d.sessions,
      minutes: Math.round(d.minutes * 10) / 10,
    }))
    .sort((a, b) => b.minutes - a.minutes);

  const total_minutes = Math.round(apps.reduce((sum, a) => sum + a.minutes, 0) * 10) / 10;
  const social_minutes = Math.round(
    apps.filter(a => SOCIAL_APPS.includes(a.app)).reduce((sum, a) => sum + a.minutes, 0) * 10
  ) / 10;

  return { date, total_minutes, social_minutes, apps };
}
```

### 文件：`gateway/src/app.ts`（修改）

在 vitalsRoutes 附近添加：

```typescript
import { getScreenTime } from './screentime';

// Screen Time 代理
app.get('/api/screentime', auth, async (c) => {
  const date = c.req.query('date'); // 可选，默认今天
  const result = await getScreenTime(date || undefined);
  return c.json(result);
});
```

## 任务 2：修复 iOS ScreenTimeClient

### 文件：`MemoryPalace/Services/VitalsClient.swift`

现有的 `ScreenTimeClient` 同时构造了两个 URL（一个 127.0.0.1，一个网关代理），逻辑混乱。
简化成只走网关代理：

```swift
enum ScreenTimeClient {
    static func fetch() async -> ScreenTimeResponse? {
        let base = UserDefaults.standard.string(forKey: "gatewayBaseURL") 
            ?? "https://blossom.amberrib.com"
        let token = UserDefaults.standard.string(forKey: "gatewayToken") ?? ""
        guard let url = URL(string: "\(base)/api/screentime") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 5
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        return try? JSONDecoder().decode(ScreenTimeResponse.self, from: data)
    }
}
```

同时确保 `ScreenTimeResponse` 包含 `social_minutes`：

```swift
struct ScreenTimeResponse: Codable {
    let date: String
    let total_minutes: Double
    let social_minutes: Double
    let apps: [ScreenTimeApp]
}
```

## 任务 3：ConsoleView 接入

### 文件：`MemoryPalace/Views/ConsoleView.swift`

确保 screenTimeCard 从 `ScreenTimeClient.fetch()` 加载数据。
检查 `todayCtx?.screenTime` 是从哪里赋值的，如果是从 DailyContext 来的，
需要在加载时调用 `ScreenTimeClient.fetch()` 并把 `total_minutes / 60` 存到 `screenTime`，
`social_minutes / 60` 存到 `socialScreenTime`。

## 任务 4：增强 iOS Shortcuts 覆盖

在 `docs/IOS-SHORTCUTS-SETUP.md` 末尾追加一段：

### 推荐监控的 App 列表

为了覆盖 Bunny 的主要使用场景，建议给以下 App 各建一条自动化：

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

每个 Shortcut 只需改 `value` 字段和触发的 App。

## 验收标准

1. `curl https://blossom.amberrib.com/api/screentime -H "Authorization: Bearer $TOKEN"` 返回今日聚合数据
2. iOS App ConsoleView 的屏幕使用时间卡片显示实际数据（不再显示"暂不可用"）
3. 打开一个被监控的 App → 等几秒 → 刷新 ConsoleView → 数据更新

## 注意事项

- 时区：Bunny 在中国，`dayStart` 用 `+08:00`
- 超时：session 最长 15 分钟，防止忘关 App 导致虚高
- 社交分类：`SOCIAL_APPS` 数组可以后续在 gateway 配置里扩展
- 不需要改 Supabase schema，`dream_events` 表已经有了
