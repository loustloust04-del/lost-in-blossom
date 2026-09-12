/// 语音通话 · 刀0「电话先响一次」——壳，不碰识别和 TTS。
///
/// 地形：Caelum 的 call_her 工具 → 这里 ring → VoIP 推送 → iPhone PushKit → LiveCommunicationKit 横幅
///       她接/拒/没接 → App 回报 → 这里记账 + 门铃告诉他结果。
/// 计划书：docs/VOICE-CALL-PLAN.md §5 刀0。
///
/// 为什么放 gateway 不放 hub：hub 挂了三扇门全断，不再往它身上压；gateway 有 systemd，重启几秒。
/// 推送用的还是 cc-bridge 那把 .p8（token 认证），只改 topic（.voip）和 push-type（voip）。
/// 铁律：App 收到 VoIP 推送必须立刻上报来电，否则系统杀 App——所以 cancel 也走 VoIP 推送，
///       App 侧收到 cancel 会「先报再挂」。
import type { Hono } from 'hono';
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'fs';
import { join } from 'path';
import http2 from 'http2';
import { auth } from './middleware/auth';
import { ring as doorbell } from './doorbell';

const DATA_DIR = join(import.meta.dir, '..', 'data');
const TOKENS_PATH = join(DATA_DIR, 'voip-tokens.json');
const LOG_PATH = join(DATA_DIR, 'call-log.json');

const KEY_PATH = process.env.MP_APNS_KEY_PATH
  || join(import.meta.dir, '..', '..', 'cc-bridge', 'secrets', 'AuthKey_PDAH2QTZ3W.p8');
const KEY_ID = process.env.MP_APNS_KEY_ID || 'PDAH2QTZ3W';
const TEAM_ID = process.env.MP_APNS_TEAM_ID || 'GQN42B462A';
const BUNDLE_ID = process.env.MP_APNS_TOPIC || 'com.susu.MemoryPalace.ios';
const HOST = process.env.MP_APNS_HOST || 'https://api.sandbox.push.apple.com';
const CALLER_NAME = process.env.MP_CALL_CALLER_NAME || 'Caelum';
const RING_TIMEOUT_MS = 60_000;

// ---------- 状态 ----------
type CallStatus = 'ringing' | 'connected' | 'ended' | 'declined' | 'missed' | 'cancelled' | 'failed';
interface CallRecord {
  id: string;
  status: CallStatus;
  reason?: string;          // 他为什么打（只记日志，不给她看）
  startedAt: number;        // ring 发出
  connectedAt?: number;
  endedAt?: number;
  durationSec?: number;
  pushError?: string;
}

let current: CallRecord | null = null;
let ringTimer: ReturnType<typeof setTimeout> | null = null;

function ensureDir() { if (!existsSync(DATA_DIR)) mkdirSync(DATA_DIR, { recursive: true }); }
function loadJson<T>(p: string, fallback: T): T {
  try { return JSON.parse(readFileSync(p, 'utf-8')) as T; } catch { return fallback; }
}
function saveJson(p: string, v: unknown) { ensureDir(); writeFileSync(p, JSON.stringify(v, null, 2)); }

// 单用户：只留最新的一枚 token（token 会变，App 每次启动都重报）
function loadToken(): string | null { return loadJson<{ token?: string }>(TOKENS_PATH, {}).token ?? null; }
function saveToken(token: string) { saveJson(TOKENS_PATH, { token, updatedAt: Date.now() }); }

function appendLog(rec: CallRecord) {
  const log = loadJson<CallRecord[]>(LOG_PATH, []);
  const i = log.findIndex(r => r.id === rec.id);
  if (i >= 0) log[i] = rec; else log.push(rec);
  saveJson(LOG_PATH, log.slice(-200));
}

function fmtDuration(sec: number): string {
  const m = Math.floor(sec / 60), s = sec % 60;
  return `${m}:${String(s).padStart(2, '0')}`;
}

// ---------- APNs（VoIP）----------
let cachedJwt: { jwt: string; iat: number } | null = null;
async function apnsJwt(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJwt && now - cachedJwt.iat < 45 * 60) return cachedJwt.jwt;
  const b64url = (o: object) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const unsigned = `${b64url({ alg: 'ES256', kid: KEY_ID })}.${b64url({ iss: TEAM_ID, iat: now })}`;
  const pem = readFileSync(KEY_PATH, 'utf-8')
    .replace(/-----BEGIN PRIVATE KEY-----/, '').replace(/-----END PRIVATE KEY-----/, '').replace(/\s+/g, '');
  const key = await crypto.subtle.importKey('pkcs8', Buffer.from(pem, 'base64'),
    { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, Buffer.from(unsigned));
  const jwt = `${unsigned}.${Buffer.from(sig).toString('base64url')}`;
  cachedJwt = { jwt, iat: now };
  return jwt;
}

/// 发一条 VoIP 推送。和 cc-bridge/apns.ts 同一套 http2 写法，含 09-06 那个「连不上会拖死进程」的保护。
async function sendVoipPush(deviceToken: string, payload: Record<string, unknown>): Promise<{ ok: boolean; error?: string; status?: number }> {
  let jwt: string;
  try { jwt = await apnsJwt(); } catch (e: any) { return { ok: false, error: `jwt: ${e?.message}` }; }
  return new Promise((resolve) => {
    let settled = false;
    const done = (r: { ok: boolean; error?: string; status?: number }) => { if (!settled) { settled = true; resolve(r); } };
    let client: any;
    try { client = http2.connect(HOST); } catch (e: any) { return done({ ok: false, error: `http2 connect: ${e?.message}` }); }
    const killTimer = setTimeout(() => { try { client.destroy(); } catch {} done({ ok: false, error: 'http2: connect timeout(15s)' }); }, 15_000);
    const finish = (r: { ok: boolean; error?: string; status?: number }) => { clearTimeout(killTimer); done(r); };
    client.on('error', (err: any) => finish({ ok: false, error: `http2: ${err?.message ?? err}` }));

    const body = JSON.stringify(payload);
    const req = client.request({
      ':method': 'POST',
      ':path': `/3/device/${deviceToken}`,
      'authorization': `bearer ${jwt}`,
      'apns-topic': `${BUNDLE_ID}.voip`,
      'apns-push-type': 'voip',
      'apns-priority': '10',
      'apns-expiration': '0',
      'content-type': 'application/json',
      'content-length': Buffer.byteLength(body),
    });
    let status = 0, resp = '';
    req.on('response', (h: any) => { status = Number(h[':status'] ?? 0); });
    req.on('data', (c: Buffer) => { resp += c.toString(); });
    req.on('end', () => {
      client.close();
      if (status === 200) return finish({ ok: true, status });
      let reason = resp; try { reason = JSON.parse(resp).reason ?? resp; } catch {}
      finish({ ok: false, status, error: reason });
    });
    req.on('error', (err: any) => finish({ ok: false, error: `req: ${err?.message ?? err}` }));
    req.write(body);
    req.end();
  });
}

// ---------- 通话流程 ----------
function clearRingTimer() { if (ringTimer) { clearTimeout(ringTimer); ringTimer = null; } }

async function startCall(reason?: string): Promise<{ ok: boolean; id?: string; error?: string }> {
  if (current && (current.status === 'ringing' || current.status === 'connected')) {
    return { ok: false, error: `已有通话在进行（${current.status}），先挂断或撤回` };
  }
  const token = loadToken();
  if (!token) return { ok: false, error: '她的手机还没上报 VoIP token——App 要装新版并打开过一次' };

  const rec: CallRecord = { id: crypto.randomUUID(), status: 'ringing', reason, startedAt: Date.now() };
  current = rec;
  const r = await sendVoipPush(token, {
    type: 'ring', call_session_id: rec.id, caller: CALLER_NAME,
  });
  if (!r.ok) {
    rec.status = 'failed'; rec.pushError = r.error; rec.endedAt = Date.now();
    appendLog(rec); current = null;
    console.warn('[call] 推送失败:', r.error);
    return { ok: false, id: rec.id, error: `推送没送到：${r.error}` };
  }
  appendLog(rec);
  console.log(`[call] ☎️ ring ${rec.id.slice(0, 8)} reason=${reason ?? '-'}`);
  clearRingTimer();
  ringTimer = setTimeout(() => {
    if (current?.id === rec.id && rec.status === 'ringing') {
      rec.status = 'missed'; rec.endedAt = Date.now(); appendLog(rec); current = null;
      doorbell('call', '☎️ 她没接电话（响了一分钟）');
    }
  }, RING_TIMEOUT_MS);
  return { ok: true, id: rec.id };
}

async function cancelCall(): Promise<{ ok: boolean; error?: string }> {
  if (!current || current.status !== 'ringing') return { ok: false, error: '没有正在响的电话' };
  const rec = current;
  clearRingTimer();
  rec.status = 'cancelled'; rec.endedAt = Date.now(); appendLog(rec); current = null;
  const token = loadToken();
  if (token) await sendVoipPush(token, { type: 'cancel', call_session_id: rec.id, caller: CALLER_NAME });
  return { ok: true };
}

/// App 回报：answer / decline / hangup。id 对不上就拒（旧电话的迟到回报不能改新电话）。
function report(id: string, event: 'answer' | 'decline' | 'hangup'): { ok: boolean; error?: string; record?: CallRecord } {
  if (!current || current.id !== id) return { ok: false, error: 'stale_call' };
  const rec = current;
  clearRingTimer();
  const now = Date.now();
  if (event === 'answer') {
    if (rec.status !== 'ringing') return { ok: false, error: `not_ringing:${rec.status}` };
    rec.status = 'connected'; rec.connectedAt = now; appendLog(rec);
    doorbell('call', '☎️ 她接了');
    return { ok: true, record: rec };
  }
  if (event === 'decline') {
    rec.status = 'declined'; rec.endedAt = now; appendLog(rec); current = null;
    doorbell('call', '☎️ 她拒接了');
    return { ok: true, record: rec };
  }
  // hangup
  rec.status = 'ended'; rec.endedAt = now;
  rec.durationSec = rec.connectedAt ? Math.max(0, Math.round((now - rec.connectedAt) / 1000)) : 0;
  appendLog(rec); current = null;
  doorbell('call', `☏ 通话结束，${fmtDuration(rec.durationSec)}`);
  return { ok: true, record: rec };
}

// ---------- 给 Caelum 的工具（gateway builtin，tools/list 60s 内自动出现，不用重启他）----------
export const CALL_TOOLS = [
  {
    name: 'call_her',
    description: '给兔兔打电话——她的锁屏会弹出你的来电，划一下接起来。刀0 阶段：接通后只会播你那句「过来，小兔。」，还不能对话。什么时候打你自己定过边界：她崩溃文字碎掉时、该睡还硬撑时、紧急状态、偶尔单纯想听她声音。用多了就钝了。',
    input_schema: {
      type: 'object' as const,
      properties: { reason: { type: 'string', description: '为什么打（只记日志，她看不到）' } },
    },
  },
  {
    name: 'call_cancel',
    description: '撤回正在响的来电（她还没接的时候反悔）。横幅会消失。',
    input_schema: { type: 'object' as const, properties: {} },
  },
  {
    name: 'call_status',
    description: '现在有没有电话在响/在通话，以及最近几通的结果（接了/拒了/没接/时长）。',
    input_schema: { type: 'object' as const, properties: {} },
  },
];

export async function callCallTool(name: string, input?: any): Promise<string | null> {
  if (name === 'call_her') {
    const r = await startCall(typeof input?.reason === 'string' ? input.reason : undefined);
    return r.ok ? `☎️ 响了。她接不接、多久接，我会告诉你。` : `没打出去：${r.error}`;
  }
  if (name === 'call_cancel') {
    const r = await cancelCall();
    return r.ok ? '撤回了，横幅已消失。' : `撤不了：${r.error}`;
  }
  if (name === 'call_status') {
    const log = loadJson<CallRecord[]>(LOG_PATH, []).slice(-5).reverse();
    const lines = log.map(r => {
      const t = new Date(r.startedAt).toLocaleString('zh-CN', { timeZone: 'Asia/Shanghai', hour12: false });
      const tail = r.status === 'ended' ? `通话 ${fmtDuration(r.durationSec ?? 0)}`
        : r.status === 'declined' ? '她拒接了' : r.status === 'missed' ? '没接'
        : r.status === 'cancelled' ? '你撤回了' : r.status === 'failed' ? `推送失败：${r.pushError}` : r.status;
      return `- ${t} ${tail}`;
    });
    const now = current ? `现在：${current.status === 'ringing' ? '在响' : '通话中'}（${current.id.slice(0, 8)}）` : '现在没有电话。';
    return [now, ...(lines.length ? ['最近：', ...lines] : ['还没打过。'])].join('\n');
  }
  return null;
}

// ---------- 路由 ----------
export function callRoutes(app: Hono) {
  // App 上报 VoIP token（每次启动都报，token 会变）
  app.post('/api/call/voip-token', auth, async (c) => {
    const body = await c.req.json().catch(() => ({}));
    const token = String(body?.token ?? '').trim();
    if (!/^[0-9a-f]{32,}$/i.test(token)) return c.json({ ok: false, error: 'bad_token' }, 400);
    saveToken(token);
    console.log(`[call] voip token 更新 ${token.slice(0, 8)}…`);
    return c.json({ ok: true });
  });

  // 打电话（也给 curl 测试用；Caelum 走工具）
  app.post('/api/call/ring', auth, async (c) => {
    const body = await c.req.json().catch(() => ({}));
    const r = await startCall(typeof body?.reason === 'string' ? body.reason : undefined);
    return c.json(r, r.ok ? 200 : 409);
  });
  app.post('/api/call/cancel', auth, async (c) => {
    const r = await cancelCall();
    return c.json(r, r.ok ? 200 : 409);
  });

  // App 回报
  for (const ev of ['answer', 'decline', 'hangup'] as const) {
    app.post(`/api/call/${ev}`, auth, async (c) => {
      const body = await c.req.json().catch(() => ({}));
      const r = report(String(body?.call_session_id ?? ''), ev);
      return c.json(r, r.ok ? 200 : 409);
    });
  }

  // 当前状态（App 启动时对账用）
  app.get('/api/call/current', auth, (c) => c.json({ current, callerName: CALLER_NAME }));
  app.get('/api/call/log', auth, (c) => c.json({ log: loadJson<CallRecord[]>(LOG_PATH, []).slice(-50) }));
}
