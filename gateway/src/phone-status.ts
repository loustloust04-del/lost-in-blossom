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
  weather?: string;
  place?: string;
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
    // 扁平结构对齐其它 builtin（{name,description,input_schema}）。此前用 OpenAI
    // 嵌套式 {type,function:{...}}，导致 app.ts 取 t.name 为 undefined：/api/mcp/tools
    // 列表里这条无名，App 整条数组解码崩（"data couldn't be read"），且发给
    // Anthropic 时也是畸形 tool。callPhoneStatusTool 本就按扁平 name 匹配。
    name: "request_location",
    description: "向兔兔的手机发送状态查询请求。兔兔的iPhone会静默自动回报一整套当前状态：位置、天气、电量、是否在充电、当地时间。当你想知道她现在在哪/在什么环境、但 get_phone_status 里的数据太旧时使用。发送后稍等几秒再调 get_phone_status 读最新一条。",
    input_schema: { type: "object" as const, properties: { reason: { type: "string", description: "为什么想知道位置（如：好久没回消息了、想关心一下）" } } },
  },
  {
    name: 'get_phone_status',
    description: 'Get Bunny\'s phone status for today — battery level, charging state, timestamps. Returns all records so you can see trends (morning 80% → afternoon 20% → evening charging). No parameters needed.',
    input_schema: { type: 'object' as const, properties: {} },
  },
];

async function sendLocationRequest(reason?: string) {
  // 从gmail模块借发送功能
  const { callGmailTool } = await import("./tools/gmail");
  const result = await callGmailTool("gmail_send", {
    to: "caelumbunny@gmail.com",
    subject: "ortolan",
    body: reason || "想知道你在哪"
  });
  return result ? "已发送位置查询请求，兔兔的手机会在几秒内自动回报位置。稍等一下再用 get_phone_status 查看最新数据。" : "发送失败";
}

export async function callPhoneStatusTool(name: string, input?: any): Promise<string | null> {
  if (name === 'request_location') {
    const { callGmailTool } = await import('./tools/gmail');
    const result = await callGmailTool('gmail_send', {
      to: 'caelumbunny@gmail.com',
      subject: 'ortolan', // 暗号：兔兔手机「收到邮件」自动化按主题包含 ortolan 触发状态上报
      body: input?.reason || '想知道你在哪'
    });
    return result ? '已发送位置查询请求，兔兔的手机会自动回报位置。' : '发送失败';
  }
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
    latest_weather: latest.weather || null,
    latest_place: latest.place || null,
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
    const valid = (!config.gatewayToken && !config.gatewayTokenAlt) || token === config.gatewayToken || token === config.gatewayTokenAlt;
    if (!valid) {
      return c.json({ error: 'unauthorized' }, 401);
    }

    let body: any = {};
    try { body = await c.req.json(); } catch { return c.json({ error: 'invalid JSON' }, 400); }
    console.log('[phone] 🔎 keys=', JSON.stringify(Object.keys(body)));

    const data = await load();
    const now = new Date();
    const beijingNow = new Date(now.getTime() + 8 * 3600 * 1000);

    data.records.push({
      battery: Number(body.battery) || 0,
      is_charging: (() => { const v = body.is_charging ?? body.in_charging ?? body['is-charging'] ?? body.isCharging ?? body.charging; // in_charging: 兔兔词典实测拼写 2026-07-29 return v === true || v === 'true' || v === 1 || v === '1'; })(),
      current_time: body['current-time'] || body.current_time || undefined,
      device_name: body.device_name || undefined,
      weather: body.Weather || body.weather || undefined,
      place: body.Place || body.place || undefined,
      received_at: beijingNow.toISOString(),
    });
    await save(data);

    console.log(`[phone] 📱 battery=${body.battery}% charging=${body.is_charging} place=${body.Place || "?"} weather=${body.Weather || "?"} (${data.records.length} records today)`);
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
