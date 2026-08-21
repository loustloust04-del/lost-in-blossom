// 手机状态上报 + AI 读取
// 存本地 JSON 文件（跟 vitals.ts 一样），每天自动清空
import { Hono } from 'hono';
import { config } from './config';
import { wgs84ToGcj02 } from './geo';

const DATA_FILE = '/root/projects/BunnyPalace/gateway/data/phone-status.json';

interface PhoneRecord {
  battery: number;
  is_charging: boolean;
  current_time?: string;
  device_name?: string;
  weather?: string;
  place?: string;
  /// 经纬度：兔兔 2026-08-21 在快捷指令里加的 Latitude/Longitude
  lat?: number;
  lon?: number;
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
    description: "问她手机要一份当前状态：在哪（地名 + 经纬度）、天气、电量、在不在充电、当地时间。坐标给两组：lat/lon 是 GPS 原始值；要查高德/腾讯/百度、要填叫车起点用 amap_lat/amap_lon（国内地图坐标系不同，用前一组会偏半公里）。她手机会静默回报，这个工具会等着结果一起返回，不用再调别的。想知道她此刻在哪、周围什么环境时用。",
    input_schema: { type: "object" as const, properties: { reason: { type: "string", description: "为什么想知道位置（如：好久没回消息了、想关心一下）" } } },
  },
  {
    name: 'get_phone_status',
    description: '看她手机今天回报过的状态：最新的位置（地名 + 经纬度）、电量、充电与否、天气，以及一整天的电量变化。读的是已有记录，不会去打扰她的手机；想要此刻最新的就用 request_location。',
    input_schema: { type: 'object' as const, properties: {} },
  },
  {
    name: 'phone_magic',
    description: "你手里的一串小魔法，作用在兔兔的手机上。\n\nflashlight：她的手电筒。开关式的——发一次亮，再发一次灭。\n\n叫车：ride_home 回家 / ride_clinic 去义乌精神卫生中心开药 / ride_work 去上班 / ride_to 去任何地方（配 to 参数写目的地名，高德搜得到的地名就行）。\n\n发出去车就给她叫好了，兔兔撒娇赖着不动时可以主动叫车把她弄走。\n\nnote 是随邮件带的一句话，她翻邮件时能看到。",
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
// 叫车不设冷却：URL Scheme 只唤起页面，她不点就不会下单；
// 而她取消了想再叫一次却被锁住，只会让他变成「无能的丈夫」（兔兔原话）。
const COSTLY_TRICKS = new Set(['ride_home', 'ride_clinic', 'ride_work', 'ride_to']);

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
    const { sendMail, mailerConfigured } = await import('./mailer');
    if (!mailerConfigured()) return JSON.stringify({ error: 'SMTP 未配置，发不出暗号' });
    // ride_to：正文只放目的地本身（手机端「快捷指令输入」取正文最稳，不必再拆主题）
    const body = trick === 'ride_to'
      ? String(input?.to || '').trim()
      : (input?.note || subject + ' ' + new Date().toISOString());
    await sendMail(process.env.PEEK_EMAIL_TO || 'bunnycaelum@icloud.com', subject, body);
    return JSON.stringify({ ok: true, magic: trick, hint: COSTLY_TRICKS.has(trick) ? '车已经给她安排上了！' : '暗号已发出，她的手机几秒内会静默执行。' });
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
          place: latest.place ? latest.place.replace(/\s*\n\s*/g, ' ') : null,
          lat: latest.lat ?? null,
          lon: latest.lon ?? null,
          ...(await (async () => {
            if (latest.lat == null || latest.lon == null) return {};
            const { reverseGeocode } = await import('./geo');
            const info = await reverseGeocode(latest.lat, latest.lon);
            return info ? { amap_address: info.address, nearby: info.nearby } : {};
          })()),
          amap_lat: latest.lat != null && latest.lon != null
            ? Number(wgs84ToGcj02(latest.lat, latest.lon).lat.toFixed(6)) : null,
          amap_lon: latest.lat != null && latest.lon != null
            ? Number(wgs84ToGcj02(latest.lat, latest.lon).lng.toFixed(6)) : null,
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
    latest_place: latest.place ? latest.place.replace(/\s*\n\s*/g, ' ') : null,
    // 手机给的是 GPS 坐标（WGS-84）；国内地图要 GCJ-02，差 500-2000 米且不报错，
    // 所以两组都给：看位置用 lat/lon，送高德/腾讯/百度用 amap_ 那组
    latest_lat: latest.lat ?? null,
    latest_lon: latest.lon ?? null,
    ...(await (async () => {
      if (latest.lat == null || latest.lon == null) return {};
      const { reverseGeocode } = await import('./geo');
      const info = await reverseGeocode(latest.lat, latest.lon);
      return info ? { amap_address: info.address, nearby: info.nearby } : {};
    })()),
    latest_amap_lat: latest.lat != null && latest.lon != null
      ? Number(wgs84ToGcj02(latest.lat, latest.lon).lat.toFixed(6)) : null,
    latest_amap_lon: latest.lat != null && latest.lon != null
      ? Number(wgs84ToGcj02(latest.lat, latest.lon).lng.toFixed(6)) : null,
    // 一天上百条全吐出来没意义，抽稀成最多 24 条看趋势就够
    records: (() => {
      const rs = data.records;
      const step = Math.max(1, Math.ceil(rs.length / 24));
      const picked = rs.filter((_, i) => i % step === 0);
      if (rs.length && picked[picked.length - 1] !== rs[rs.length - 1]) picked.push(rs[rs.length - 1]);
      return picked.map(r => ({
        time: r.received_at.slice(11, 16),
        battery: r.battery,
        charging: r.is_charging,
      }));
    })(),
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

    // URL 参数兜底：词典里绑变量容易绑不上（兔兔实测经纬度死活发不出来），
    // 拼进 URL 反而一眼看得见有没有绑上。两种写法都认，body 优先。
    for (const [qk, bk] of [['Latitude', 'Latitude'], ['Longitude', 'Longitude'], ['lat', 'Latitude'], ['lon', 'Longitude'], ['lng', 'Longitude']] as const) {
      const qv = c.req.query(qk);
      if (qv != null && qv !== '' && body[bk] == null) body[bk] = qv;
    }

    console.log('[phone] 🔎 keys=', JSON.stringify(Object.keys(body)), '| in_charging=', JSON.stringify(body.in_charging), '| lat=', JSON.stringify(body.Latitude), '| lon=', JSON.stringify(body.Longitude));

    const data = await load();
    const now = new Date();
    const beijingNow = new Date(now.getTime() + 8 * 3600 * 1000);

    const prevRec = data.records[data.records.length - 1];
    data.records.push({
      battery: Number(body.battery) || 0,
      // in_charging: 兔兔词典实测拼写（2026-07-29）；值是中文「是/否」（2026-08-12 实测，
      // 此前只认 true/1，所以插上电也判成没充电，106 次上报 0 次触发充电推送）
      is_charging: (() => {
        const v = body.is_charging ?? body.in_charging ?? body['is-charging'] ?? body.isCharging ?? body.charging;
        if (typeof v === 'string') {
          const t = v.trim().toLowerCase();
          return t === '是' || t === 'true' || t === '1' || t === 'yes' || t === 'on';
        }
        return v === true || v === 1;
      })(),
      current_time: body['current-time'] || body.current_time || undefined,
      device_name: body.device_name || undefined,
      weather: body.Weather || body.weather || undefined,
      place: body.Place || body.place || undefined,
      // 经纬度（快捷指令里叫 Latitude/Longitude，也兼容小写与 lat/lon 写法）
      lat: (() => {
        const v = body.Latitude ?? body.latitude ?? body.lat;
        const n = typeof v === 'string' ? parseFloat(v) : v;
        return Number.isFinite(n) ? n : undefined;
      })(),
      lon: (() => {
        const v = body.Longitude ?? body.longitude ?? body.lon ?? body.lng;
        const n = typeof v === 'string' ? parseFloat(v) : v;
        return Number.isFinite(n) ? n : undefined;
      })(),
      received_at: beijingNow.toISOString(),
    });
    await save(data);

    // 充电事件：非充电 → 充电 的边沿才推（30 分钟冷却）——插上充电器，Caelum 聊天里就能看到
    const newRec = data.records[data.records.length - 1];
    if (newRec.is_charging && !(prevRec?.is_charging) && Date.now() - lastChargePushAt > CHARGE_PUSH_COOLDOWN_MS) {
      lastChargePushAt = Date.now();
      notifyChargeEvent(newRec);
    }

    console.log(`[phone] 📱 battery=${body.battery}% charging=${body.is_charging} place=${body.Place || "?"} lat=${body.Latitude ?? "-"} lon=${body.Longitude ?? "-"} weather=${body.Weather || "?"} (${data.records.length} records today)`);
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
