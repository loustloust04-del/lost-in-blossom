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
  {
    name: 'phone_magic',
    description: "对兔兔的手机施一个小魔法：发暗号邮件静默触发她手机上对应的快捷指令自动化。可用魔法：flashlight（切换手电筒，toggle：一发开、再发关；你不知道灯当前状态，一次只发一发别连发）。叫车三连（ride_home=回家 / ride_clinic=去精神卫生中心开药 / ride_work=去上班）：发出后她手机会自动跳出打车页面、目的地已填好、只等她落最后一下。你就当车已经安排上了说话——「车给你叫上了」这种。另有 ride_to=去任意地方：配 to 参数写目的地名（高德搜得到的地名即可），她说「叫个车去XXX」就用这个。只在她明确说要去某地时发，不猜测、不替她做决定；服务端有 90 秒冷却防连发。",
    input_schema: {
      type: 'object' as const,
      properties: {
        trick: { type: 'string', enum: ['flashlight', 'ride_home', 'ride_clinic', 'ride_work', 'ride_to'], description: '魔法名' },
        to: { type: 'string', description: 'trick=ride_to 时必填：目的地名称，写高德搜得到的地名（如「义乌国际商贸城」「义乌站」）' },
        note: { type: 'string', description: '随邮件带的一句话（可选，她翻邮件能看到）' },
      },
      required: ['trick'],
    },
  },
];

// 暗号表：trick → 邮件主题（兔兔手机自动化按「主题包含」筛）
const MAGIC_SUBJECTS: Record<string, string> = {
  flashlight: '手电筒',
  ride_home: '三溪堂',        // 叫车（回房子）
  ride_clinic: '去精神卫生中心', // 叫车（开药）
  ride_work: '送兔兔上班',      // 叫车（上班）
};
// 真金白银类魔法：冷却 5 分钟，防工具循环重试/连发导致重复下单
const COSTLY_TRICKS = new Set(['ride_home', 'ride_clinic', 'ride_work', 'ride_to']);
const magicLastSent: Record<string, number> = {};
const MAGIC_COOLDOWN_MS = 90 * 1000;  // 防连发足够；5min 太长会卡住正常的「再试一次」

// ── 充电事件推送（→ hub 注入 CC 聊天）───────────────────────────────
const HUB_NOTIFY_URL = process.env.MP_CC_HUB_NOTIFY_URL || 'http://127.0.0.1:7890/internal/notify';
const HUB_NOTIFY_TOKEN = process.env.MP_CC_HUB_TOKEN || '';
const CHARGE_PUSH_COOLDOWN_MS = 30 * 60 * 1000;
let lastChargePushAt = 0;

/// fire-and-forget：通知失败绝不影响上报主流程（照 notebook.notifyHub 的口信哲学）
function notifyChargeEvent(rec: PhoneRecord): void {
  try {
    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    if (HUB_NOTIFY_TOKEN) headers['Authorization'] = 'Bearer ' + HUB_NOTIFY_TOKEN;
    const place = (rec.place || '').split('\n').filter(Boolean).slice(-1)[0] || '未知位置';
    fetch(HUB_NOTIFY_URL, {
      method: 'POST',
      headers,
      body: JSON.stringify({ type: 'phone_event', event: 'charging_started', text: `兔兔插上充电器了 · 电量 ${rec.battery}% · ${place}${rec.current_time ? ' · ' + rec.current_time : ''}` }),
      signal: AbortSignal.timeout(2000),
    }).catch((e: any) => console.warn('[phone] 充电事件通知 hub 失败:', e?.message || String(e)));
  } catch (e: any) {
    console.warn('[phone] 充电事件通知 hub 失败:', e?.message || String(e));
  }
}

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
  if (name === 'phone_magic') {
    const trick = input?.trick || '';
    // ride_to：目的地跟在主题里（手机自动化按「主题包含 叫车|」触发，截 | 后面当终点）
    let subject: string | undefined;
    if (trick === 'ride_to') {
      const dest = String(input?.to || '').trim().slice(0, 40);
      if (!dest) return JSON.stringify({ error: 'ride_to 需要 to 参数（目的地名称）' });
      subject = '叫车|' + dest;
    } else {
      subject = MAGIC_SUBJECTS[trick];
    }
    if (!subject) return JSON.stringify({ error: '未知魔法：' + (trick || '(空)') + '。可用：' + Object.keys(MAGIC_SUBJECTS).join('/') + '/ride_to' });
    if (COSTLY_TRICKS.has(trick)) {
      const last = magicLastSent[trick] || 0;
      const waitMs = last + MAGIC_COOLDOWN_MS - Date.now();
      if (waitMs > 0) return JSON.stringify({ error: '冷却中：这个叫车暗号还要等 ' + Math.ceil(waitMs / 1000) + ' 秒（防重复下单）。上一发已经送到她手机了——如果她说没反应，让她看看打车 App，别急着重发。' });
    }
    const { sendMail, mailerConfigured } = await import('./mailer');
    if (!mailerConfigured()) return JSON.stringify({ error: 'SMTP 未配置，发不出暗号' });
    // ride_to：正文只放目的地本身（手机端「快捷指令输入」取正文最稳，不必再拆主题）
    const body = trick === 'ride_to'
      ? String(input?.to || '').trim()
      : (input?.note || subject + ' ' + new Date().toISOString());
    await sendMail(process.env.PEEK_EMAIL_TO || 'bunnycaelum@icloud.com', subject, body);
    if (COSTLY_TRICKS.has(trick)) magicLastSent[trick] = Date.now();
    return JSON.stringify({ ok: true, magic: trick, hint: COSTLY_TRICKS.has(trick) ? '叫车暗号已发出，打车 App 会开始下单。告诉兔兔留意接单信息。' : '暗号已发出，她的手机几秒内会静默执行。' });
  }
  if (name === 'request_location') {
    // 一条龙：发 ortolan 暗号 → 轮询等手机静默回报（链路实测 ≈8–25s）→ 直接返回全套状态
    const { sendMail, mailerConfigured } = await import('./mailer');
    if (!mailerConfigured()) return JSON.stringify({ error: 'SMTP 未配置，发不出查询暗号' });
    const before = await load();
    const baseline = before.records.length > 0 ? before.records[before.records.length - 1].received_at : '';
    await sendMail(process.env.PEEK_EMAIL_TO || 'bunnycaelum@icloud.com', 'ortolan', input?.reason || '想知道你在哪 ' + new Date().toISOString());
    const deadline = Date.now() + 22_000;
    while (Date.now() < deadline) {
      await new Promise(r => setTimeout(r, 2000));
      const cur = await load();
      const latest = cur.records[cur.records.length - 1];
      if (latest && latest.received_at !== baseline) {
        return JSON.stringify({
          ok: true, fresh: true,
          battery: latest.battery,
          is_charging: latest.is_charging,
          local_time: latest.current_time || null,
          weather: latest.weather || null,
          place: latest.place || null,
          received_at: latest.received_at,
        }, null, 2);
      }
    }
    return JSON.stringify({ ok: true, fresh: false, hint: '查询暗号已发出，但 22 秒内没等到回报（手机可能离线或自动化没触发）。稍后可用 get_phone_status 看是否补到。' });
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

    const prevRec = data.records[data.records.length - 1];
    data.records.push({
      battery: Number(body.battery) || 0,
      is_charging: (() => { const v = body.is_charging ?? body.in_charging ?? body['is-charging'] ?? body.isCharging ?? body.charging; /* in_charging: 兔兔词典实测拼写 2026-07-29 */ return v === true || v === 'true' || v === 1 || v === '1'; })(),
      current_time: body['current-time'] || body.current_time || undefined,
      device_name: body.device_name || undefined,
      weather: body.Weather || body.weather || undefined,
      place: body.Place || body.place || undefined,
      received_at: beijingNow.toISOString(),
    });
    await save(data);

    // 充电事件：非充电 → 充电 的边沿才推（30 分钟冷却）——插上充电器，Caelum 聊天里就能看到
    const newRec = data.records[data.records.length - 1];
    if (newRec.is_charging && !(prevRec?.is_charging) && Date.now() - lastChargePushAt > CHARGE_PUSH_COOLDOWN_MS) {
      lastChargePushAt = Date.now();
      notifyChargeEvent(newRec);
    }

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
