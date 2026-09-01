import type { Hono } from 'hono';
import { readFileSync } from 'node:fs';

/// 音源代理：App ↔ 本机 NCM API（api-enhanced 4.39.0，:3335）。
/// App 里零网易代码，只认自家网关地址——审核口径同 VLC/Plex 那类"支持自定义媒体服务器的播放器"。
/// cookie 存在服务器（/root/ncm-cookie.txt），不下发给客户端。
const NCM = process.env.NCM_API_URL || 'http://127.0.0.1:3335';
const COOKIE_PATH = process.env.NCM_COOKIE_PATH || '/root/ncm-cookie.txt';

function cookie(): string {
  try { return readFileSync(COOKIE_PATH, 'utf-8').trim(); } catch { return ''; }
}

async function ncm(path: string, params: Record<string, string | number> = {}): Promise<any> {
  const q = new URLSearchParams({ ...Object.fromEntries(
    Object.entries(params).map(([k, v]) => [k, String(v)])), timestamp: String(Date.now()) });
  const ck = cookie();
  if (ck) q.set('cookie', ck);
  const r = await fetch(`${NCM}${path}?${q}`, { signal: AbortSignal.timeout(20_000) });
  return r.json();
}

/// music_play 工具用：搜网易云取第一条命中（id/歌名/歌手）
export async function searchFirstSong(query: string): Promise<{ id: number; title: string; artist: string } | null> {
  const d = await ncm('/search', { keywords: query, limit: 1 });
  const hit = d?.result?.songs?.[0];
  if (!hit?.id) return null;
  return {
    id: hit.id,
    title: String(hit.name || ''),
    artist: (hit.artists || hit.ar || []).map((a: any) => a.name).filter(Boolean).join(' / '),
  };
}

/// song_lyrics 工具用：按「歌名 歌手」搜网易云取第一条命中的 LRC（去时间戳留纯词，保留翻译）
export async function fetchLyricsBySearch(title: string, artist?: string): Promise<string | null> {
  const q = artist ? `${title} ${artist.split('/')[0].trim()}` : title;
  const d = await ncm('/search', { keywords: q, limit: 1 });
  const id = d?.result?.songs?.[0]?.id;
  if (!id) return null;
  const l = await ncm('/lyric', { id });
  const strip = (raw: string) => raw
    .split('\n')
    .map((ln: string) => ln.replace(/\[[0-9:.\]]+\]/g, '').trim())
    .filter((ln: string) => ln.length > 0)
    .join('\n');
  const main = strip(l?.lrc?.lyric || '');
  if (!main) return null;
  const trans = strip(l?.tlyric?.lyric || '');
  return trans ? `${main}\n\n—— 翻译 ——\n${trans}` : main;
}

export function musicRoutes(app: Hono) {
  /// 搜索：GET /api/music/search?q=五月天
  app.get('/api/music/search', async (c) => {
    const q = c.req.query('q') || '';
    if (!q) return c.json({ error: 'q required' }, 400);
    const d = await ncm('/search', { keywords: q, limit: Number(c.req.query('limit') || 30) });
    const songs = (d?.result?.songs || []).map((s: any) => ({
      id: String(s.id),
      title: s.name,
      artist: (s.artists || s.ar || []).map((a: any) => a.name).join(' / '),
      album: (s.album || s.al || {}).name || '',
      duration: Math.round((s.duration || s.dt || 0) / 1000),
    }));
    return c.json({ songs });
  });

  /// 我的歌单列表
  app.get('/api/music/playlists', async (c) => {
    const me = await ncm('/user/account');
    const uid = me?.account?.id;
    if (!uid) return c.json({ error: 'not logged in' }, 401);
    const d = await ncm('/user/playlist', { uid, limit: 50 });
    return c.json({
      playlists: (d?.playlist || []).map((p: any) => ({
        id: String(p.id), name: p.name, count: p.trackCount,
        cover: p.coverImgUrl || '',
      })),
    });
  });

  /// 歌单里的歌
  app.get('/api/music/playlist/:id', async (c) => {
    const d = await ncm('/playlist/track/all', { id: c.req.param('id'), limit: 300 });
    return c.json({
      songs: (d?.songs || []).map((s: any) => ({
        id: String(s.id),
        title: s.name,
        artist: (s.ar || []).map((a: any) => a.name).join(' / '),
        album: (s.al || {}).name || '',
        duration: Math.round((s.dt || 0) / 1000),
        cover: (s.al || {}).picUrl || '',
      })),
    });
  });

  /// 播放直链 + 歌词（App 拿到就能播）
  app.get('/api/music/song/:id', async (c) => {
    const id = c.req.param('id');
    const [u, l] = await Promise.all([
      ncm('/song/url/v1', { id, level: c.req.query('level') || 'exhigh' }),
      ncm('/lyric', { id }),
    ]);
    const d = (u?.data || [])[0] || {};
    return c.json({
      url: d.url || null,
      level: d.level || '',
      size: d.size || 0,
      lyric: l?.lrc?.lyric || '',
      translated: l?.tlyric?.lyric || '',
    });
  });

  /// 登录态自检（cookie 会过期，App 可据此提示重新扫码）
  app.get('/api/music/status', async (c) => {
    const me = await ncm('/user/account');
    const p = me?.profile;
    return c.json({
      loggedIn: !!p,
      nickname: p?.nickname || null,
      uid: p?.userId || null,
      vip: me?.account?.vipType || 0,
    });
  });
}
