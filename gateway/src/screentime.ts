// 从本地 app-opens.json 聚合今日屏幕时间

const DATA_FILE = '/root/projects/BunnyPalace/gateway/data/app-opens.json';

const SOCIAL_APPS = ['小红书', '微博', '抖音', 'B站', '微信', 'QQ', 'Twitter', 'Instagram', 'TikTok'];

interface AppOpen { app: string; ts: number; }
interface DayData { date: string; opens: AppOpen[]; }

function todayBeijing(): string {
  const now = new Date();
  return new Date(now.getTime() + 8 * 3600 * 1000).toISOString().slice(0, 10);
}

async function loadOpens(): Promise<DayData> {
  try {
    const text = await Bun.file(DATA_FILE).text();
    const data = JSON.parse(text) as DayData;
    if (data.date !== todayBeijing()) return { date: todayBeijing(), opens: [] };
    return data;
  } catch {
    return { date: todayBeijing(), opens: [] };
  }
}

async function saveOpens(data: DayData): Promise<void> {
  data.date = todayBeijing();
  await Bun.write(DATA_FILE, JSON.stringify(data, null, 2));
}

export async function recordAppOpen(app: string): Promise<void> {
  const data = await loadOpens();
  data.opens.push({ app, ts: Date.now() });
  await saveOpens(data);
  console.log(`[screen] 📱 app_open: ${app} (${data.opens.length} opens today)`);
}

export async function getScreenTime(): Promise<any> {
  const data = await loadOpens();
  const date = data.date;

  if (data.opens.length === 0) {
    return { date, total_minutes: 0, social_minutes: 0, apps: [] };
  }

  const MAX_SESSION_MS = 15 * 60 * 1000;
  const appMinutes: Record<string, { sessions: number; minutes: number }> = {};

  for (let i = 0; i < data.opens.length; i++) {
    const app = data.opens[i].app;
    const start = data.opens[i].ts;
    const nextTs = i + 1 < data.opens.length ? data.opens[i + 1].ts : start + MAX_SESSION_MS;
    const duration = Math.min(nextTs - start, MAX_SESSION_MS);

    if (!appMinutes[app]) appMinutes[app] = { sessions: 0, minutes: 0 };
    appMinutes[app].sessions += 1;
    appMinutes[app].minutes += duration / 60000;
  }

  const apps = Object.entries(appMinutes)
    .map(([app, d]) => ({ app, sessions: d.sessions, minutes: Math.round(d.minutes * 10) / 10 }))
    .sort((a, b) => b.minutes - a.minutes);

  const total_minutes = Math.round(apps.reduce((sum, a) => sum + a.minutes, 0) * 10) / 10;
  const social_minutes = Math.round(
    apps.filter(a => SOCIAL_APPS.includes(a.app)).reduce((sum, a) => sum + a.minutes, 0) * 10
  ) / 10;

  return { date, total_minutes, social_minutes, apps };
}
