// T2 共听会话态（plan-listen-together-v2，2026-09-01 凌晨落码，随下次网关重启生效）。
// 「叫他一起听」：她按下按钮 = 邀请这个动作本身有仪式感。
// start → 状态落盘 + 给 Caelum 发一条 liveline 级事件（他先开口）；
// stop / 切歌不 stop（同一场共听可以连着听好几首）/ 心跳断 5min 自动过期。

import { Hono } from 'hono';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const STATE_PATH = join(import.meta.dir, '../data/listen-session.json');

interface ListenSession {
  active: boolean;
  startedAt: string;
  lastSeenAt: string;   // 由 now-playing 心跳刷新（nowplaying.ts 调 touchListenSession）
}

function load(): ListenSession | null {
  try { return existsSync(STATE_PATH) ? JSON.parse(readFileSync(STATE_PATH, 'utf8')) : null; }
  catch { return null; }
}
function save(s: ListenSession) { writeFileSync(STATE_PATH, JSON.stringify(s, null, 2)); }

/// 心跳来时续命（nowplaying 路由里调）
export function touchListenSession() {
  const s = load();
  if (s?.active) { s.lastSeenAt = new Date().toISOString(); save(s); }
}

/// 共听是否进行中（心跳断 5 分钟 = 她走了，自动过期）
export function isListeningTogether(): boolean {
  const s = load();
  if (!s?.active) return false;
  return Date.now() - new Date(s.lastSeenAt).getTime() < 5 * 60_000;
}

/// 注入段（每轮上下文用；配合 describeNowPlaying 的进度/当句）。
/// 防复述标注是 Duetto/粟粟共同的教训：不标他会把歌词复述当聊天。
export function listenContextLine(): string | null {
  if (!isListeningTogether()) return null;
  return '[共听中·她邀请你一起听歌。当下在放的内容用 now_playing 看。这是背景，不要复述歌词，除非她先聊到。]';
}

export function listenRoutes(app: Hono) {
  const KEY = process.env.PHONE_DATA_KEY || 'bunny-lib-2026';

  app.post('/listen/start', async (c) => {
    if (c.req.query('key') !== KEY) return c.json({ error: 'unauthorized' }, 401);
    const now = new Date().toISOString();
    save({ active: true, startedAt: now, lastSeenAt: now });
    let body: any = {};
    try { body = await c.req.json(); } catch {}
    const song = body?.title ? `${body.title}${body.artist ? ' - ' + body.artist : ''}` : '';
    // 邀请事件：他先开口（走 liveline 同一条通道；kind=listen 无节流条目默认 5min，
    // 邀请是显式动作不该被吞——pushLiveline 之前先清那条节流记录做不到，
    // 用专属 kind 'listen_invite'，THROTTLE 若未配则 5min 足够：连点两次不重推是对的）
    const { pushLiveline } = await import('./liveline');
    pushLiveline('listen_invite', `兔兔按下了「一起听」${song ? `，正在放：${song}` : ''}。她在邀请你陪她听歌，先开口。`);
    console.log(`[listen] 🎧 共听开始 ${song}`);
    return c.json({ ok: true });
  });

  app.post('/listen/stop', async (c) => {
    if (c.req.query('key') !== KEY) return c.json({ error: 'unauthorized' }, 401);
    const s = load();
    if (s) { s.active = false; save(s); }
    console.log('[listen] 共听结束');
    return c.json({ ok: true });
  });

  app.get('/api/listen', async (c) => c.json({ active: isListeningTogether() }));
}
