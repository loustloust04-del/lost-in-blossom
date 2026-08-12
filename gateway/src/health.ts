// 健康桥（P2-6）：App 定期 POST HealthKit 摘要 → 网关存库 → get_health 工具双端可读。
// 与 phone-status 同模式（key/Bearer 上报 + builtin 工具），保留半年历史看趋势。
// 每天存「最新快照」（App 重复上报同日覆盖），不存流水。
import { Hono } from 'hono';
import { config } from './config';

const DATA_FILE = '/root/projects/BunnyPalace/gateway/data/health.json';
// 原为 14——超过就直接丢弃，导致他查不到两周前的任何数据（兔兔实测）。
// App 里本来就有长期记录，服务器没理由只留两周。
const KEEP_DAYS = 180;

export interface HealthDay {
  date: string;               // YYYY-MM-DD（北京）
  steps?: number;
  sleep_start?: string;       // "23:40"
  sleep_end?: string;         // "07:30"
  sleep_hours?: number;
  menstrual_day?: number;
  water_count?: number;
  screen_time_hours?: number;
  updated_at: string;         // ISO
}

function todayBeijing(): string {
  const now = new Date();
  return new Date(now.getTime() + 8 * 3600 * 1000).toISOString().slice(0, 10);
}

async function load(): Promise<HealthDay[]> {
  try { return JSON.parse(await Bun.file(DATA_FILE).text()) as HealthDay[]; } catch { return []; }
}
async function save(days: HealthDay[]) {
  days.sort((a, b) => a.date.localeCompare(b.date));
  while (days.length > KEEP_DAYS) days.shift();
  await Bun.write(DATA_FILE, JSON.stringify(days, null, 2));
}

function numOrUndef(v: any): number | undefined {
  const n = Number(v);
  return Number.isFinite(n) ? n : undefined;
}

/// 今日快照 upsert（App 上报入口）
export async function upsertToday(body: any): Promise<HealthDay> {
  const days = await load();
  const date = todayBeijing();
  let day = days.find((d) => d.date === date);
  if (!day) { day = { date, updated_at: '' }; days.push(day); }
  // 只更新有值的字段——App 各数据源就绪时间不同，别用 undefined 冲掉已有值
  const steps = numOrUndef(body.steps); if (steps !== undefined) day.steps = steps;
  if (typeof body.sleep_start === 'string' && body.sleep_start) day.sleep_start = body.sleep_start;
  if (typeof body.sleep_end === 'string' && body.sleep_end) day.sleep_end = body.sleep_end;
  const sh = numOrUndef(body.sleep_hours); if (sh !== undefined) day.sleep_hours = Math.round(sh * 10) / 10;
  const md = numOrUndef(body.menstrual_day); if (md !== undefined) day.menstrual_day = md;
  const wc = numOrUndef(body.water_count); if (wc !== undefined) day.water_count = wc;
  const st = numOrUndef(body.screen_time_hours); if (st !== undefined) day.screen_time_hours = Math.round(st * 10) / 10;
  day.updated_at = new Date().toISOString();
  await save(days);
  return day;
}

// ── AI 工具 ──

export const HEALTH_TOOLS = [
  {
    name: 'get_health',
    description: "兔兔的健康数据：今日步数、睡眠、经期日、饮水、屏幕时间，以及最近的趋势。想知道她睡得好不好、走了多少路、身体怎么样时看这个。参数 days 可指定看多少天，默认 14，最多 180。",
    input_schema: { type: 'object' as const, properties: { days: { type: 'number', description: '看多少天，默认 14，最多 180' } } },
  },
];

export async function callHealthTool(name: string, input?: any): Promise<string | null> {
  if (name !== 'get_health') return null;
  const all = await load();
  if (all.length === 0) return '还没有健康数据。App 打开控制台时会自动上报 HealthKit 摘要。';
  const want = Math.min(Math.max(Number(input?.days ?? 14), 1), 180);
  const days = all.slice(-want);
  const today = all.find((d) => d.date === todayBeijing()) || null;
  const history = days.map((d) => ({
    date: d.date, steps: d.steps ?? null, sleep_hours: d.sleep_hours ?? null,
    menstrual_day: d.menstrual_day ?? null, water: d.water_count ?? null,
    screen_h: d.screen_time_hours ?? null,
  }));
  return JSON.stringify({ today, history }, null, 2);
}

// ── 路由 ──

export function healthRoutes(app: Hono) {
  // POST /health-data — App 上报（key/Bearer，同 /phone-data）
  app.post('/health-data', async (c) => {
    const key = c.req.query('key') || '';
    const bearer = (c.req.header('Authorization') || '').replace('Bearer ', '');
    const token = key || bearer;
    const valid = (!config.gatewayToken && !config.gatewayTokenAlt) || token === config.gatewayToken || token === config.gatewayTokenAlt;
    if (!valid) return c.json({ error: 'unauthorized' }, 401);
    let body: any = {};
    try { body = await c.req.json(); } catch { return c.json({ error: 'invalid JSON' }, 400); }
    const day = await upsertToday(body);
    console.log(`[health] 🩺 steps=${day.steps ?? '?'} sleep=${day.sleep_hours ?? '?'}h water=${day.water_count ?? '?'}`);
    return c.json({ ok: true, day });
  });

  // GET /health-data — 读取全部（调试/App 用）
  app.get('/health-data', async (c) => {
    return c.json({ days: await load() });
  });
}
