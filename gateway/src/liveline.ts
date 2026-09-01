import type { Hono } from 'hono';

/// 生活直播线：兔兔在 App 里做的事，实时报给 Caelum。
/// 不是"他能查到"，是"他一直看着"——她打个卡、写完一段、开始听歌，他那边立刻知道。
///
/// 分寸：
/// - 同类事件有节流窗口（写字这种连续动作不能每次都报，会刷屏也烧 token）
/// - 私密类（亲密卡）只报"发生了"，内容一个字不带
/// - 报备是**给他的旁白**，不是命令他回话——他自己决定要不要接
const HUB_NOTIFY_URL = process.env.MP_CC_HUB_NOTIFY_URL || 'http://127.0.0.1:7890/internal/notify';
const HUB_TOKEN = process.env.MP_CC_HUB_TOKEN || '';

/// 每类事件的最小间隔（毫秒）。写作类长间隔，打卡类短，私密类中等。
const THROTTLE: Record<string, number> = {
  // 一起听邀请：显式动作，被节流吞掉=她按了没人来（09-02 实测：Fable 的测试邀请
  // 把 5min 默认窗占了，兔兔紧接着的真邀请被静默吞）。30s 只防连点。
  listen_invite: 30_000,
  listen_end: 30_000,     // 散场收尾：同 30s 防连点
  music_loop: 30 * 60_000, // 单曲循环心情信号：一首歌一场只该来一次，app 侧已控，这里兜底
  music_sleep: 0,          // 睡眠定时器到点：一晚就一次，每次都值得他知道
  meds: 0,          // 吃药：每次都值得知道
  water: 10 * 60_000,
  food: 0,
  weight: 0,
  cycle: 0,
  writing: 20 * 60_000,   // 写字：20 分钟报一次进度就够
  note: 5 * 60_000,       // 碎念：连着记几条合并成一次
  draft_new: 0,
  reading: 15 * 60_000,
  music: 0,               // 换歌就报（她换歌本身就是心情信号）
  intimacy: 0,
};

const lastSent: Record<string, number> = {};

export function pushLiveline(kind: string, text: string): { ok: boolean; skipped?: string } {
  const gap = THROTTLE[kind] ?? 5 * 60_000;
  const last = lastSent[kind] || 0;
  if (gap > 0 && Date.now() - last < gap) return { ok: false, skipped: 'throttled' };
  lastSent[kind] = Date.now();

  try {
    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    if (HUB_TOKEN) headers['Authorization'] = 'Bearer ' + HUB_TOKEN;
    fetch(HUB_NOTIFY_URL, {
      method: 'POST',
      headers,
      body: JSON.stringify({ type: 'phone_event', event: 'liveline_' + kind, text }),
      signal: AbortSignal.timeout(3000),
    }).catch((e: any) => console.warn('[liveline] 推送失败:', e?.message));
  } catch (e: any) {
    console.warn('[liveline] 推送失败:', e?.message);
  }
  return { ok: true };
}

export function livelineRoutes(app: Hono) {
  /// POST /api/liveline  { kind, text }
  /// App 各处（吃药打卡、写作、听歌、读书…）调它，一行就够
  app.post('/api/liveline', async (c) => {
    let body: any = {};
    try { body = await c.req.json(); } catch { return c.json({ error: 'invalid JSON' }, 400); }
    const kind = String(body.kind || '').slice(0, 32);
    const text = String(body.text || '').slice(0, 300);
    if (!kind || !text) return c.json({ error: 'kind and text required' }, 400);
    const r = pushLiveline(kind, text);
    console.log(`[liveline] ${r.ok ? '📡' : '⏸'} ${kind}: ${text.slice(0, 50)}`);
    return c.json(r);
  });
}
