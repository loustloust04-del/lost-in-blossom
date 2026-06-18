// 手机状态上报 + AI 读取
// 存本地 JSON 文件（跟 vitals.ts 一样），每天自动清空
import { Hono } from 'hono';
import { config } from './config';

const DATA_FILE = '/root/projects/BunnyPalace/gateway/data/phone-status.json';

interface PhoneRecord {
  battery: number;
  is_charging: boolean;
  current_time?: string;
  device_name?: string;
  received_at: string; // ISO string
}

interface DayData {
  date: string;
  records: PhoneRecord[];
}

function todayBeijing(): string {
  const now = new Date();
  return new Date(now.getTime() + 8 * 3600 * 1000).toISOString().slice(0, 10);
}

async function load(): Promise<DayData> {
  try {
    const text = await Bun.file(DATA_FILE).text();
    const data = JSON.parse(text) as DayData;
    if (data.date !== todayBeijing()) return { date: todayBeijing(), records: [] };
    return data;
  } catch {
    return { date: todayBeijing(), records: [] };
  }
}

async function save(data: DayData): Promise<void> {
  data.date = todayBeijing();
  await Bun.write(DATA_FILE, JSON.stringify(data, null, 2));
}

// ── AI 工具 ──

export const PHONE_STATUS_TOOLS = [
  {
    name: 'get_phone_status',
    description: 'Get Bunny\'s phone status for today — battery level, charging state, timestamps. Returns all records so you can see trends (morning 80% → afternoon 20% → evening charging). No parameters needed.',
    input_schema: { type: 'object' as const, properties: {} },
  },
];

export async function callPhoneStatusTool(name: string): Promise<string | null> {
  if (name !== 'get_phone_status') return null;
  const data = await load();
  if (data.records.length === 0) {
    return '今天还没有收到手机状态数据。兔兔可能还没设置快捷指令自动化。';
  }
  const first = data.records[0];
  const latest = data.records[data.records.length - 1];
  return JSON.stringify({
    date: data.date,
    total_records: data.records.length,
    first_record_at: first.received_at.slice(11, 16),
    latest_record_at: latest.received_at.slice(11, 16),
    latest_battery: latest.battery,
    latest_charging: latest.is_charging,
    records: data.records.map(r => ({
      time: r.received_at.slice(11, 16),
      battery: r.battery,
      charging: r.is_charging,
    })),
  }, null, 2);
}

// ── 路由 ──

export function phoneStatusRoutes(app: Hono) {
  // POST /phone-data — 快捷指令上报
  app.post('/phone-data', async (c) => {
    const key = c.req.query('key') || '';
    const bearer = (c.req.header('Authorization') || '').replace('Bearer ', '');
    const token = key || bearer;
    if (config.gatewayToken && token !== config.gatewayToken) {
      return c.json({ error: 'unauthorized' }, 401);
    }

    let body: any = {};
    try { body = await c.req.json(); } catch { return c.json({ error: 'invalid JSON' }, 400); }

    const data = await load();
    const now = new Date();
    const beijingNow = new Date(now.getTime() + 8 * 3600 * 1000);

    data.records.push({
      battery: Number(body.battery) || 0,
      is_charging: Boolean(body.is_charging),
      current_time: body.current_time || undefined,
      device_name: body.device_name || undefined,
      received_at: beijingNow.toISOString(),
    });
    await save(data);

    console.log(`[phone] 📱 battery=${body.battery}% charging=${body.is_charging} (${data.records.length} records today)`);
    return c.json({ ok: true });
  });

  // GET /phone-data — 读取今日数据
  app.get('/phone-data', async (c) => {
    const data = await load();
    return c.json({
      date: data.date,
      total_records: data.records.length,
      records: data.records,
    });
  });
}
