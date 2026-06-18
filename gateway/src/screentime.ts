// 从 dream_events 聚合今日屏幕时间（app_open 事件代理 Screen Time）

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
  // 默认用北京时间的今天（VPS 是 UTC，兔兔在 UTC+8）
  const now = new Date();
  const beijingNow = new Date(now.getTime() + 8 * 3600 * 1000);
  const date = dateStr || beijingNow.toISOString().slice(0, 10);

  // 取今天 00:00 ~ 23:59 的所有 app_open 事件，按时间排序（北京时间）
  const dayStart = new Date(date + 'T00:00:00+08:00').getTime();
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

  // 算法：每个 app_open 事件开始一个 session，持续到下一个 app_open 事件或 15 分钟超时
  // （取较小值）。15 分钟超时防止用户锁屏但没触发新 app_open 导致虚高。
  const MAX_SESSION_MS = 15 * 60 * 1000;
  const appMinutes: Record<string, { sessions: number; minutes: number }> = {};

  for (let i = 0; i < events.length; i++) {
    const app = events[i].value as string;
    const start = events[i].ts as number;
    const nextTs = i + 1 < events.length ? (events[i + 1].ts as number) : start + MAX_SESSION_MS;
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
