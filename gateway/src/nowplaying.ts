import type { Hono } from 'hono';
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';

/// 「她在听什么」——不做播放器，只做在场感。
/// 兔兔照常用网易云/Apple Music，快捷指令把歌名报过来即可。
/// 每首歌累积在场记录：听过几次、第一次是什么时候、她说过什么——
/// 这样他不是"知道你在听歌"，是"记得你和这首歌的事"。
const DIR = join(process.cwd(), 'data');
const NOW_PATH = join(DIR, 'now-playing.json');
const HIST_PATH = join(DIR, 'song-history.json');

interface NowPlaying {
  title: string;
  artist?: string;
  album?: string;
  note?: string;        // 她随手说的一句
  startedAt: string;
  updatedAt: string;
  // T1 共听 v2（2026-08-31）：同一时刻感——进度与「正唱到哪句」
  position?: number;    // 秒
  duration?: number;    // 秒
  line?: string;        // 当前 LRC 行
  state?: 'playing' | 'paused' | 'stopped';
}

interface SongMemory {
  key: string;          // "歌名 - 歌手"
  title: string;
  artist?: string;
  count: number;        // 听过几次
  firstAt: string;
  lastAt: string;
  notes: string[];      // 她历次说过的话（最多留 6 条，滚动）
}

function load<T>(p: string, fallback: T): T {
  try { return JSON.parse(readFileSync(p, 'utf-8')) as T; } catch { return fallback; }
}
function save(p: string, data: unknown): void {
  mkdirSync(DIR, { recursive: true });
  writeFileSync(p, JSON.stringify(data, null, 2), 'utf-8');
}

export function recordNowPlaying(input: { title: string; artist?: string; album?: string; note?: string; position?: number; duration?: number; line?: string; state?: string }): SongMemory {
  const title = String(input.title || '').slice(0, 200).trim();
  const artist = input.artist ? String(input.artist).slice(0, 120).trim() : undefined;
  const now = new Date().toISOString();

  const prev = load<NowPlaying | null>(NOW_PATH, null);
  const isSameSong = prev?.title === title && prev?.artist === artist;
  const st = input.state === 'paused' || input.state === 'stopped' ? input.state : 'playing';
  save(NOW_PATH, {
    title, artist, album: input.album,
    // 心跳不带 note；同一首歌保留她之前随手说的那句
    note: input.note ?? (isSameSong ? prev!.note : undefined),
    startedAt: isSameSong ? prev!.startedAt : now,
    updatedAt: now,
    position: typeof input.position === 'number' ? Math.max(0, input.position) : undefined,
    duration: typeof input.duration === 'number' ? Math.max(0, input.duration) : undefined,
    line: input.line ? String(input.line).slice(0, 200) : undefined,
    state: st,
  } satisfies NowPlaying);

  // 歌曲记忆
  const key = artist ? `${title} - ${artist}` : title;
  const hist = load<Record<string, SongMemory>>(HIST_PATH, {});
  const mem = hist[key] ?? { key, title, artist, count: 0, firstAt: now, lastAt: now, notes: [] };
  if (!isSameSong) mem.count += 1;         // 同一首持续播放不重复计数
  mem.lastAt = now;
  if (input.note) {
    mem.notes.push(`${now.slice(0, 10)} ${String(input.note).slice(0, 200)}`);
    if (mem.notes.length > 6) mem.notes = mem.notes.slice(-6);
  }
  hist[key] = mem;
  save(HIST_PATH, hist);
  return mem;
}

/// 给 Caelum 看的一段话（工具返回值）
export function describeNowPlaying(): string {
  const now = load<NowPlaying | null>(NOW_PATH, null);
  if (!now) return '不知道她在听什么（她还没报过，或者没在听）。';

  const ageMin = (Date.now() - new Date(now.updatedAt).getTime()) / 60000;
  // T1：有心跳后 3 分钟没动静就算旧（原 60min 是「开播报一次」时代的阈值）
  const stale = ageMin > 3;
  const key = now.artist ? `${now.title} - ${now.artist}` : now.title;
  const hist = load<Record<string, SongMemory>>(HIST_PATH, {});
  const mem = hist[key];

  const fmt = (s: number) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}`;
  const lines = [
    stale
      ? `${ageMin > 90 ? Math.round(ageMin / 60) + ' 小时' : Math.round(ageMin) + ' 分钟'}前她在听：${key}（现在未必还在听）`
      : now.state === 'paused' ? `她在听：${key}（暂停着）` : `她在听：${key}`,
  ];
  if (!stale && typeof now.position === 'number' && typeof now.duration === 'number' && now.duration > 0) {
    lines.push(`进度 ${fmt(now.position)} / ${fmt(now.duration)}`);
  }
  if (!stale && now.line && now.state !== 'stopped') {
    lines.push(`正唱到：「${now.line}」`);
  }
  if (now.album) lines.push(`专辑：${now.album}`);
  if (now.note) lines.push(`她说：${now.note}`);
  if (mem) {
    lines.push(`这首她听过 ${mem.count} 次，第一次是 ${mem.firstAt.slice(0, 10)}。`);
    const past = mem.notes.filter(n => !now.note || !n.endsWith(now.note));
    if (past.length) lines.push(`以前听这首时她说过：\n${past.map(n => '· ' + n).join('\n')}`);
  }
  return lines.join('\n');
}

export const NOWPLAYING_TOOLS = [
  {
    name: 'now_playing',
    description: '看兔兔在听什么歌：歌名、歌手、播放进度、正唱到哪句歌词、她说的话，以及这首歌你们之间的记录（她听过几次、第一次是什么时候、以前听这首时说过什么）。她提到音乐、或者你想知道她此刻的背景音时调用。她在 App 里听歌时进度是实时的，能接住「正唱到的这句」说话。',
    input_schema: { type: 'object' as const, properties: {} },
  },
  {
    name: 'song_lyrics',
    description: '看她正在听的这首歌的完整歌词（含翻译，如有）。now_playing 只给「正唱到的那句」；想通读整首、接住上下文时用这个。共听时她聊到歌词、或你想懂这首歌在唱什么，就调它。',
    input_schema: { type: 'object' as const, properties: {} },
  },
];

/// 完整歌词：走网易云代理搜当前歌（本地导入的歌搜不到就如实说）。
/// 一首只取一次，缓存在内存（进程生命周期内够用）。
const lyricsCache = new Map<string, string>();
async function describeFullLyrics(): Promise<string> {
  const now = load<NowPlaying | null>(NOW_PATH, null);
  if (!now?.title) return '她现在没在听歌。';
  const key = now.artist ? `${now.title} - ${now.artist}` : now.title;
  const hit = lyricsCache.get(key);
  if (hit) return hit;
  try {
    const { fetchLyricsBySearch } = await import('./music');
    const lrc = await fetchLyricsBySearch(now.title, now.artist);
    if (!lrc) return `《${now.title}》的歌词没搜到（可能是本地导入的歌）。你知道的就凭记忆聊，不确定就问她。`;
    const out = `《${key}》完整歌词：

${lrc}`;
    lyricsCache.set(key, out.slice(0, 8000));
    return out.slice(0, 8000);
  } catch (e: any) {
    return `歌词服务这会儿没搜到（${e?.message || 'unknown'}）。`;
  }
}

export async function callNowPlayingTool(name: string): Promise<string | null> {
  if (name === 'now_playing') return describeNowPlaying();
  if (name === 'song_lyrics') return describeFullLyrics();
  return null;
}

export function nowPlayingRoutes(app: Hono) {
  // 快捷指令上报：POST /now-playing?key=...  { title, artist?, album?, note? }
  app.post('/now-playing', async (c) => {
    const key = c.req.query('key') || '';
    if (key !== (process.env.PHONE_DATA_KEY || 'bunny-lib-2026')) {
      return c.json({ error: 'unauthorized' }, 401);
    }
    let body: any = {};
    try { body = await c.req.json(); } catch {
      // 快捷指令也可能用表单/纯文本发，退而求其次读 query
      body = { title: c.req.query('title'), artist: c.req.query('artist'), note: c.req.query('note') };
    }
    if (!body?.title) return c.json({ error: 'title required' }, 400);
    const mem = recordNowPlaying(body);
    // T2：共听会话续命（心跳即在场证明）
    try { const { touchListenSession } = await import('./listen'); touchListenSession(); } catch {}
    console.log(`[music] 🎧 ${mem.key} (第 ${mem.count} 次)`);
    return c.json({ ok: true, count: mem.count });
  });

  app.get('/api/now-playing', async (c) => c.json(load(NOW_PATH, null)));
}
