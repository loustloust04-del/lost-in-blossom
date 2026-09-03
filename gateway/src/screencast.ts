/// 屏幕直播（连拍版）：Broadcast Upload Extension 每 ~2.5s POST 一张 JPEG 上来，
/// see_screen 优先吃这份，吃不到才回落到老的邮件偷看链路。
///
/// 三条设计红线（09-03，兔兔和 Fable 定）：
///
/// 1. **只留最新一张，不留历史。** 单文件覆盖写。她的屏幕上有微信、有支付、有一切，
///    在 VPS 上堆一串历史帧等于把她的生活留底。旧的必须被盖掉。
///
/// 2. **判活看帧的新鲜度，不信 state。** iOS 给 broadcastFinished 的时间只有一两秒，
///    那个「我停了」的 POST 大概率发不出去 —— state.active 会永远卡在 true。
///    所以 isLive() 只看最后一帧多久前到的，state 仅作辅助显示。
///
/// 3. **主 App 关不掉共享。** Apple 没有让 App 主动停止系统广播的接口，只能她自己去
///    控制中心停。而且 Extension 是独立进程，主 App 被杀了它照样传——
///    「把 App 划掉 ≠ 停止共享」。这一条必须在 UI 上说人话，别让她误以为关了。
import { mkdirSync, writeFileSync, readFileSync, existsSync, statSync } from 'node:fs';
import { join } from 'node:path';
import type { Hono } from 'hono';

const DIR = join(process.cwd(), 'data', 'screencast');
const FRAME = join(DIR, 'latest.jpg');

/// 超过这个时间没新帧就认为共享已经停了（Extension 约 2.5s 一张，留足抖动余量）
const LIVE_WINDOW_MS = 12_000;
/// see_screen 认为「够新，可以直接用」的窗口
const FRESH_MS = 8_000;

interface CastState { active: boolean; startedAt: number; lastFrameAt: number; frames: number; }
let state: CastState = { active: false, startedAt: 0, lastFrameAt: 0, frames: 0 };

function ensureDir() { mkdirSync(DIR, { recursive: true }); }

/// 最后一帧到现在多久（毫秒）。内存里没有就退回看文件 mtime（网关重启后仍能判断）。
export function lastFrameAge(): number | null {
  if (state.lastFrameAt) return Date.now() - state.lastFrameAt;
  try { return Date.now() - statSync(FRAME).mtimeMs; } catch { return null; }
}

/// 是否正在直播 —— 只认帧的新鲜度，不认 state.active（见红线 2）
export function isLive(): boolean {
  const age = lastFrameAge();
  return age !== null && age < LIVE_WINDOW_MS;
}

export function saveFrame(buf: ArrayBuffer): void {
  ensureDir();
  writeFileSync(FRAME, Buffer.from(buf));   // 覆盖写，不留历史（红线 1）
  state.lastFrameAt = Date.now();
  state.frames++;
  if (!state.active) { state.active = true; state.startedAt = Date.now(); }
}

/// 取最新一帧给 see_screen 用
export function latestFrame(): { base64: string; ageMs: number } | null {
  if (!existsSync(FRAME)) return null;
  const age = lastFrameAge();
  if (age === null) return null;
  return { base64: readFileSync(FRAME).toString('base64'), ageMs: age };
}

export function castStatus() {
  const age = lastFrameAge();
  return {
    live: isLive(),
    ageMs: age,
    startedAt: state.active ? state.startedAt : 0,
    frames: state.frames,
    // 诚实标注：active 是 Extension 自报的，可能卡住；live 才是可信的那个
    reportedActive: state.active,
  };
}

/// 和其它手机侧接口同一把钥匙（listen.ts 用的也是这个），Extension 里带 header 或 query 都行。
/// query 会进 nginx access log，所以 Extension 应优先用 header。
function authed(c: any): boolean {
  const key = process.env.PHONE_DATA_KEY || 'bunny-lib-2026';
  const h = c.req.header('authorization') || '';
  if (h === `Bearer ${key}`) return true;
  if ((c.req.header('x-screen-key') || '') === key) return true;
  return (c.req.query('key') || '') === key;
}

export function screencastRoutes(app: Hono) {
  /// Extension 每 ~2.5s 打一张 JPEG 上来（body 是裸二进制）
  app.post('/api/screen/frame', async (c) => {
    if (!authed(c)) return c.json({ error: 'unauthorized' }, 401);
    const buf = await c.req.arrayBuffer();
    if (!buf || buf.byteLength === 0) return c.json({ error: 'empty' }, 400);
    // 一帧 720p JPEG 正常几十 KB；异常大的直接拒，别让磁盘被灌满
    if (buf.byteLength > 2_000_000) return c.json({ error: 'frame too large' }, 413);
    saveFrame(buf);
    return c.json({ ok: true, bytes: buf.byteLength });
  });

  /// Extension 报告开始/结束。**结束那条大概率发不出来**，所以只当辅助信号。
  app.post('/api/screen/state', async (c) => {
    if (!authed(c)) return c.json({ error: 'unauthorized' }, 401);
    let b: any = {};
    try { b = await c.req.json(); } catch {}
    if (b?.active === true) { state.active = true; state.startedAt = Date.now(); state.frames = 0; }
    if (b?.active === false) { state.active = false; }
    return c.json({ ok: true });
  });

  /// App / 控制台查状态
  app.get('/api/screen/state', async (c) => c.json(castStatus()));

  /// 取最新一帧（App 里做「共享中」预览用）
  app.get('/api/screen/frame', async (c) => {
    if (!existsSync(FRAME)) return c.json({ error: 'no frame' }, 404);
    return new Response(readFileSync(FRAME), {
      headers: { 'Content-Type': 'image/jpeg', 'Cache-Control': 'no-store' },
    });
  });
}
