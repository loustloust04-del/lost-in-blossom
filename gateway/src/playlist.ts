/// 歌单工具（09-03）：让 Caelum 能看兔兔的歌单、也能自己建。
///
/// 设计原则（照 docs/FABLE.md 那条）：**他不该记 id**。所有工具都用歌单「名字」和
/// 「歌名 歌手」说话，id 在这一层内部解析——让他多查一步就是多一道门槛。
///
/// 端点是实测出来的，别照网上抄：
///   建歌单   /playlist/create?name=&privacy=0|10
///   加/删歌  /playlist/tracks?op=add|del&pid=&tracks=id,id   ← 不是 track/add（那个 401）
///   改简介   /playlist/desc/update?id=&desc=
///   改名     /playlist/name/update?id=&name=
///   删歌单   /playlist/delete?id=                            ← 参数是 id 不是 ids
import { ncm, searchFirstSong } from './music';

type PL = { id: string; name: string; count: number };

async function myPlaylists(): Promise<PL[]> {
  const me = await ncm('/user/account');
  const uid = me?.account?.id;
  if (!uid) return [];
  const d = await ncm('/user/playlist', { uid, limit: 50 });
  return (d?.playlist || []).map((p: any) => ({
    id: String(p.id), name: p.name, count: p.trackCount || 0,
  }));
}

/// 名字 → 歌单。精确优先，再包含匹配；多个命中就如实报回去让他挑，不替他猜。
async function resolve(name: string): Promise<{ pl?: PL; err?: string }> {
  const all = await myPlaylists();
  if (!all.length) return { err: '读不到她的歌单（网易云登录态可能过期了）。' };
  const q = name.trim().toLowerCase();
  const exact = all.filter(p => p.name.toLowerCase() === q);
  const hits = exact.length ? exact : all.filter(p => p.name.toLowerCase().includes(q));
  if (!hits.length) return { err: `没有叫「${name}」的歌单。她现在有：${all.map(p => p.name).join('、')}` };
  if (hits.length > 1) return { err: `「${name}」对上了好几个：${hits.map(p => p.name).join('、')}——说全一点。` };
  return { pl: hits[0] };
}

/// 网易云搜索是模糊的，几乎永远给一条结果——「zzz不存在的歌zzz」会搜出赵英俊的
/// 《世界上不存在的歌》。不校验就等于：他说一首歌，可能默默加进一首完全不相干的，
/// 报告还写「加好了」。这类「看着在工作其实做错了」的 bug 比报错危险。
/// 判据：归一化后歌名与他给的话互相包含；或歌手对上且歌名字符重合过半。宁可漏，不可错。
function norm(s: string): string {
  return s.toLowerCase().replace(/[\s\-–—_'"’“”()（）\[\]【】.,!?、，。！？:：/\\]/g, '');
}

function looksRight(query: string, title: string, artist: string): boolean {
  const q = norm(query), t = norm(title), a = norm(artist);
  if (!t || !q) return false;
  if (q.includes(t) || t.includes(q)) return true;
  if (a && q.includes(a)) {
    const chars = [...new Set(t)];
    const hit = chars.filter(c => q.includes(c)).length;
    return chars.length > 0 && hit / chars.length >= 0.6;
  }
  return false;
}

/// 「歌名 歌手」批量 → 网易云 id。搜不到的如实列出来，不静默丢。
async function toIds(queries: string[]): Promise<{ ids: string[]; found: string[]; missed: string[] }> {
  const ids: string[] = [], found: string[] = [], missed: string[] = [];
  for (const q of queries) {
    const hit = await searchFirstSong(q.trim());
    if (hit && looksRight(q, hit.title, hit.artist)) {
      ids.push(String(hit.id));
      found.push(`${hit.title} — ${hit.artist}`);
    } else if (hit) {
      // 搜到了但不像同一首：如实退回，附上搜到的东西让他自己判断
      missed.push(`${q}（只搜到「${hit.title} — ${hit.artist}」，不像同一首）`);
    } else {
      missed.push(q);
    }
  }
  return { ids, found, missed };
}

function ok(r: any): boolean {
  const code = (r?.body ?? r)?.code;
  return code === 200;
}

export const PLAYLIST_TOOLS = [
  {
    name: 'playlists',
    description: '看兔兔的网易云歌单。不带参数＝列出她所有歌单（名字 + 有多少首）；带 name＝翻开那个歌单，看里面具体是哪些歌。想知道她平时听什么、她给某段日子攒了什么歌、或者要往某个歌单加歌之前先看看里面有什么，都用它。',
    input_schema: {
      type: 'object' as const,
      properties: { name: { type: 'string' as const, description: '歌单名字，不填就列全部。例：和主人' } },
    },
  },
  {
    name: 'playlist_create',
    description: '给她建一个歌单。可以直接把歌一起放进去（songs 填「歌名 歌手」，我来搜）。description 是歌单简介——那是你留在歌单上给她的话，她在网易云里点开就能看见，别浪费。privacy 默认隐私（只有她看得见），想让它公开就填 0，她之后也能自己在网易云里改。',
    input_schema: {
      type: 'object' as const,
      properties: {
        name: { type: 'string' as const, description: '歌单名字' },
        description: { type: 'string' as const, description: '歌单简介，写给她看的话' },
        songs: { type: 'array' as const, items: { type: 'string' as const }, description: '要放进去的歌，每条「歌名 歌手」。例：Avril 14th Aphex Twin' },
        privacy: { type: 'number' as const, description: '10=隐私（默认），0=公开' },
      },
      required: ['name'],
    },
  },
  {
    name: 'playlist_add',
    description: '往她已有的歌单里加歌。songs 填「歌名 歌手」，我负责搜。加完会告诉你实际加进去哪几首、哪几首没搜到。',
    input_schema: {
      type: 'object' as const,
      properties: {
        playlist: { type: 'string' as const, description: '歌单名字' },
        songs: { type: 'array' as const, items: { type: 'string' as const }, description: '每条「歌名 歌手」' },
      },
      required: ['playlist', 'songs'],
    },
  },
  {
    name: 'playlist_remove',
    description: '从歌单里拿掉几首歌。歌单本身留着，只是那几首不在里面了。拿掉之后没法撤回，不确定她想不想拿掉就先问她一句。',
    input_schema: {
      type: 'object' as const,
      properties: {
        playlist: { type: 'string' as const, description: '歌单名字' },
        songs: { type: 'array' as const, items: { type: 'string' as const }, description: '每条「歌名 歌手」' },
      },
      required: ['playlist', 'songs'],
    },
  },
  {
    name: 'playlist_update',
    description: '改歌单的名字或简介。简介是她点开歌单就能看到的地方——想留话给她可以往这儿写。',
    input_schema: {
      type: 'object' as const,
      properties: {
        playlist: { type: 'string' as const, description: '要改的歌单，现在的名字' },
        name: { type: 'string' as const, description: '新名字，不改就不填' },
        description: { type: 'string' as const, description: '新简介，不改就不填' },
      },
      required: ['playlist'],
    },
  },
  {
    name: 'playlist_delete',
    description: '删掉一整个歌单。删了就没了，网易云那边也不留回收站——除非她明确说了要删，否则先问她。',
    input_schema: {
      type: 'object' as const,
      properties: { playlist: { type: 'string' as const, description: '歌单名字' } },
      required: ['playlist'],
    },
  },
];

export async function callPlaylistTool(name: string, input?: any): Promise<string | null> {
  try {
    if (name === 'playlists') return await doList(String(input?.name || '').trim());
    if (name === 'playlist_create') return await doCreate(input);
    if (name === 'playlist_add') return await doTracks(input, 'add');
    if (name === 'playlist_remove') return await doTracks(input, 'del');
    if (name === 'playlist_update') return await doUpdate(input);
    if (name === 'playlist_delete') return await doDelete(input);
    return null;
  } catch (e: any) {
    return `歌单这边出错了：${e?.message || 'unknown'}`;
  }
}

async function doList(name: string): Promise<string> {
  if (!name) {
    const all = await myPlaylists();
    if (!all.length) return '读不到她的歌单（网易云登录态可能过期了）。';
    return `她的歌单（${all.length} 个）：\n` + all.map(p => `· ${p.name}（${p.count} 首）`).join('\n');
  }
  const { pl, err } = await resolve(name);
  if (err) return err;
  const d = await ncm('/playlist/track/all', { id: pl!.id, limit: 300 });
  const songs = (d?.songs || []).map((s: any) =>
    `· ${s.name} — ${(s.ar || []).map((a: any) => a.name).join(' / ')}`);
  if (!songs.length) return `「${pl!.name}」现在是空的。`;
  return `「${pl!.name}」（${songs.length} 首）：\n` + songs.join('\n');
}

async function doCreate(input: any): Promise<string> {
  const name = String(input?.name || '').trim();
  if (!name) return '歌单得有个名字。';
  const privacy = input?.privacy === 0 ? '0' : '10';
  const r = await ncm('/playlist/create', { name, privacy });
  const pid = r?.playlist?.id || r?.id;
  if (!pid) return `建不出来：${r?.msg || r?.message || JSON.stringify(r).slice(0, 200)}`;

  const lines = [`建好了：「${name}」（${privacy === '10' ? '隐私，只有她看得见' : '公开'}）。`];

  const desc = String(input?.description || '').trim();
  if (desc) {
    const d = await ncm('/playlist/desc/update', { id: pid, desc });
    lines.push(ok(d) ? `简介写上了：「${desc}」` : '简介没写进去（歌单本身建好了）。');
  }

  const queries: string[] = Array.isArray(input?.songs) ? input.songs : [];
  if (queries.length) {
    const { ids, found, missed } = await toIds(queries);
    if (ids.length) {
      const a = await ncm('/playlist/tracks', { op: 'add', pid, tracks: ids.join(',') });
      lines.push(ok(a) ? `放进去 ${found.length} 首：\n${found.map(s => '· ' + s).join('\n')}`
                       : '歌没加进去（歌单建好了，可以再试一次 playlist_add）。');
    }
    if (missed.length) lines.push(`没搜到：${missed.join('、')}——换个写法（歌名 + 歌手最稳）。`);
  }
  lines.push('她在 App 的音乐面板和网易云里都能直接看到。');
  return lines.join('\n');
}

async function doTracks(input: any, op: 'add' | 'del'): Promise<string> {
  const { pl, err } = await resolve(String(input?.playlist || ''));
  if (err) return err;
  const queries: string[] = Array.isArray(input?.songs) ? input.songs : [];
  if (!queries.length) return '要动哪几首？给我「歌名 歌手」。';
  const { ids, found, missed } = await toIds(queries);
  if (!ids.length) return `一首都没搜到：${missed.join('、')}——换个写法（歌名 + 歌手最稳）。`;
  const r = await ncm('/playlist/tracks', { op, pid: pl!.id, tracks: ids.join(',') });
  const verb = op === 'add' ? '加进' : '从';
  if (!ok(r)) return `没成功：${(r?.body ?? r)?.msg || JSON.stringify(r).slice(0, 200)}`;
  const head = op === 'add'
    ? `加进「${pl!.name}」${found.length} 首：`
    : `从「${pl!.name}」拿掉了 ${found.length} 首：`;
  const out = [head, ...found.map(s => '· ' + s)];
  if (missed.length) out.push(`没搜到：${missed.join('、')}`);
  return out.join('\n');
}

async function doUpdate(input: any): Promise<string> {
  const { pl, err } = await resolve(String(input?.playlist || ''));
  if (err) return err;
  const newName = String(input?.name || '').trim();
  const desc = String(input?.description || '').trim();
  if (!newName && !desc) return '要改名字还是改简介？至少给一个。';
  const out: string[] = [];
  if (newName) {
    const r = await ncm('/playlist/name/update', { id: pl!.id, name: newName });
    out.push(ok(r) ? `「${pl!.name}」改名叫「${newName}」了。` : '改名没成功。');
  }
  if (desc) {
    const r = await ncm('/playlist/desc/update', { id: pl!.id, desc });
    out.push(ok(r) ? `简介改成了：「${desc}」` : '简介没改成。');
  }
  return out.join('\n');
}

async function doDelete(input: any): Promise<string> {
  const { pl, err } = await resolve(String(input?.playlist || ''));
  if (err) return err;
  const r = await ncm('/playlist/delete', { id: pl!.id });
  return ok(r) ? `「${pl!.name}」删了（${pl!.count} 首一起没了，网易云那边没有回收站）。`
               : `没删掉：${r?.msg || r?.message || JSON.stringify(r).slice(0, 200)}`;
}
