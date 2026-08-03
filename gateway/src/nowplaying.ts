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

export function recordNowPlaying(input: { title: string; artist?: string; album?: string; note?: string }): SongMemory {
  const title = String(input.title || '').slice(0, 200).trim();
  const artist = input.artist ? String(input.artist).slice(0, 120).trim() : undefined;
  const now = new Date().toISOString();

  const prev = load<NowPlaying | null>(NOW_PATH, null);
  const isSameSong = prev?.title === title && prev?.artist === artist;
  save(NOW_PATH, {
    title, artist, album: input.album, note: input.note,
    startedAt: isSameSong ? prev!.startedAt : now,
    updatedAt: now,
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
  const stale = ageMin > 60;
  const key = now.artist ? `${now.title} - ${now.artist}` : now.title;
  const hist = load<Record<string, SongMemory>>(HIST_PATH, {});
  const mem = hist[key];

  const lines = [
    stale
      ? `${Math.round(ageMin / 60)} 小时前她在听：${key}（现在未必还在听）`
      : `她在听：${key}`,
  ];
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
    description: '看兔兔在听什么歌：歌名、歌手、她说的话，以及这首歌你们之间的记录（她听过几次、第一次是什么时候、以前听这首时说过什么）。她提到音乐、或者你想知道她此刻的背景音时调用。',
    input_schema: { type: 'object' as const, properties: {} },
  },
];

export async function callNowPlayingTool(name: string): Promise<string | null> {
  if (name === 'now_playing') return describeNowPlaying();
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
    console.log(`[music] 🎧 ${mem.key} (第 ${mem.count} 次)`);
    return c.json({ ok: true, count: mem.count });
  });

  app.get('/api/now-playing', async (c) => c.json(load(NOW_PATH, null)));
}
