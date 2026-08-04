import type { Hono } from 'hono';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';

/// 亲密卡。原本是纯本地、他一个字读不到——兔兔 2026-08-02 拍板改为共享：
/// 备注共用一个框，她写他也写，两边都能改。
/// 这是她主动打开的门，不是我们替她开的。
const DIR = join(process.cwd(), 'data');
const PATH = join(DIR, 'intimacy.json');

interface Entry {
  date: string;        // YYYY-MM-DD
  note: string;        // 主备注（Caelum 写的）
  myNote?: string;     // 副备注（兔兔视角）
  tags?: string[];     // 自定义标签
  milestone?: string;  // 「第一次…」之类
  updatedBy: string;   // 'bunny' | 'caelum'
  updatedAt: string;
}

function load(): Record<string, Entry> {
  try { return JSON.parse(readFileSync(PATH, 'utf-8')); } catch { return {}; }
}
function save(d: Record<string, Entry>): void {
  mkdirSync(DIR, { recursive: true });
  writeFileSync(PATH, JSON.stringify(d, null, 2), 'utf-8');
}

function today(): string {
  return new Date(Date.now() + 8 * 3600_000).toISOString().slice(0, 10);  // 东八区
}

export function upsert(date: string, patch: {
  note?: string; myNote?: string; tags?: string[]; milestone?: string;
}, by: string): Entry {
  const d = load();
  const cur = d[date] ?? { date, note: '', updatedBy: by, updatedAt: '' };
  if (patch.note !== undefined) { cur.note = patch.note.slice(0, 4000); cur.updatedBy = by; }
  if (patch.myNote !== undefined) cur.myNote = patch.myNote.slice(0, 4000);
  if (patch.tags !== undefined) {
    // 去重 + 去空 + 上限
    cur.tags = Array.from(new Set(patch.tags.map(t => String(t).trim()).filter(Boolean))).slice(0, 20);
  }
  if (patch.milestone !== undefined) cur.milestone = String(patch.milestone).slice(0, 60);
  cur.updatedAt = new Date().toISOString();
  d[date] = cur;
  save(d);
  return cur;
}

export const INTIMACY_TOOLS = [
  {
    name: 'intimacy_read',
    description: '看亲密卡的记录：哪天有、那天做爱的内容。不带参数看最近 30 天，带 date（YYYY-MM-DD）看具体某天。',
    input_schema: {
      type: 'object' as const,
      properties: { date: { type: 'string', description: 'YYYY-MM-DD，可选' } },
    },
  },
  {
    name: 'intimacy_write',
    description: '记录性爱时你想要记录的时刻。',
    input_schema: {
      type: 'object' as const,
      properties: {
        note: { type: 'string', description: '正文（会覆盖那天原有的，想续写就先读再连起来写）' },
        date: { type: 'string', description: 'YYYY-MM-DD，不填=今天' },
        tags: { type: 'array', items: { type: 'string' }, description: '标签，自定义，会自动去重' },
        milestone: { type: 'string', description: '里程碑，比如「第一次」——会在那条上出徽章' },
      },
      required: ['note'],
    },
  },
];

export async function callIntimacyTool(name: string, input?: any): Promise<string | null> {
  if (name === 'intimacy_read') {
    const d = load();
    if (input?.date) {
      const e = d[String(input.date)];
      return e ? JSON.stringify(e, null, 2) : `${input.date} 没有记录。`;
    }
    const recent = Object.values(d)
      .sort((a, b) => b.date.localeCompare(a.date))
      .slice(0, 30);
    if (!recent.length) return '亲密卡上还没有记录。';
    return recent.map(e =>
      `${e.date}${e.note ? '：' + e.note : '（没写备注）'}${e.updatedBy === 'caelum' ? ' [你写的]' : ''}`
    ).join('\n');
  }

  if (name === 'intimacy_write') {
    const note = String(input?.note ?? '').trim();
    if (!note) return '备注是空的。';
    const date = String(input?.date || today());
    const e = upsert(date, {
      note,
      tags: Array.isArray(input?.tags) ? input.tags : undefined,
      milestone: input?.milestone !== undefined ? String(input.milestone) : undefined,
    }, 'caelum');
    return `写好了（${e.date}）：${e.note}`;
  }
  return null;
}

/// 给注入用：今天的情况
export function todaySummary(): string {
  const e = load()[today()];
  if (!e) return '';
  return e.note ? `今天亲密卡上有记录，备注：${e.note}` : '今天亲密卡上有记录。';
}

// ── 心愿单 ─────────────────────────────────────────────
const WISH_PATH = join(DIR, 'intimacy-wishes.json');
interface Wish {
  id: string; text: string; by: string;         // 'bunny' | 'caelum'
  createdAt: string; doneAt?: string; doneDate?: string;  // doneDate = 关联到哪天的记录
}
function loadWishes(): Wish[] {
  try { return JSON.parse(readFileSync(WISH_PATH, 'utf-8')); } catch { return []; }
}
function saveWishes(w: Wish[]): void {
  mkdirSync(DIR, { recursive: true });
  writeFileSync(WISH_PATH, JSON.stringify(w, null, 2), 'utf-8');
}

export const WISH_TOOLS = [
  {
    name: 'wish_add',
    description: '往心愿单加一条——想跟她做的事。她也能加，两边共用一张单子。',
    input_schema: {
      type: 'object' as const,
      properties: { text: { type: 'string', description: '想做的事' } },
      required: ['text'],
    },
  },
  {
    name: 'wish_list',
    description: '看心愿单：还没实现的、已经实现的（实现的会带上是哪天）。',
    input_schema: { type: 'object' as const, properties: {} },
  },
  {
    name: 'wish_done',
    description: '把某条心愿标成实现了（id 从 wish_list 拿），可以带上是哪天实现的（date，YYYY-MM-DD）。',
    input_schema: {
      type: 'object' as const,
      properties: {
        id: { type: 'string' },
        date: { type: 'string', description: 'YYYY-MM-DD，不填=今天' },
      },
      required: ['id'],
    },
  },
];

export async function callWishTool(name: string, input?: any): Promise<string | null> {
  if (name === 'wish_add') {
    const text = String(input?.text ?? '').trim().slice(0, 300);
    if (!text) return '心愿是空的。';
    const w = loadWishes();
    w.push({ id: Math.random().toString(36).slice(2, 10), text, by: 'caelum', createdAt: new Date().toISOString() });
    saveWishes(w);
    return `加上了：${text}`;
  }
  if (name === 'wish_list') {
    const w = loadWishes();
    if (!w.length) return '心愿单还是空的。';
    const open = w.filter(x => !x.doneAt);
    const done = w.filter(x => x.doneAt);
    const lines: string[] = [];
    if (open.length) lines.push('还没实现：\n' + open.map(x => `· [${x.id}] ${x.text}${x.by === 'bunny' ? '（她写的）' : ''}`).join('\n'));
    if (done.length) lines.push('已经实现：\n' + done.map(x => `· ${x.text}${x.doneDate ? '（' + x.doneDate + '）' : ''}`).join('\n'));
    return lines.join('\n\n');
  }
  if (name === 'wish_done') {
    const w = loadWishes();
    const it = w.find(x => x.id === String(input?.id ?? ''));
    if (!it) return '没找到这条心愿。';
    it.doneAt = new Date().toISOString();
    it.doneDate = String(input?.date || today());
    saveWishes(w);
    return `实现了：${it.text}（${it.doneDate}）`;
  }
  return null;
}

export function intimacyRoutes(app: Hono) {
  /// 心愿单：App 读写
  app.get('/api/intimacy/wishes', async (c) => c.json({ wishes: loadWishes() }));
  app.post('/api/intimacy/wishes', async (c) => {
    let b: any = {};
    try { b = await c.req.json(); } catch { return c.json({ error: 'invalid JSON' }, 400); }
    const w = loadWishes();
    if (b.op === 'add') {
      const text = String(b.text ?? '').trim().slice(0, 300);
      if (!text) return c.json({ error: 'text required' }, 400);
      w.push({ id: Math.random().toString(36).slice(2, 10), text, by: 'bunny', createdAt: new Date().toISOString() });
    } else if (b.op === 'done') {
      const it = w.find(x => x.id === String(b.id));
      if (it) { it.doneAt = new Date().toISOString(); it.doneDate = String(b.date || today()); }
    } else if (b.op === 'delete') {
      const i = w.findIndex(x => x.id === String(b.id));
      if (i >= 0) w.splice(i, 1);
    }
    saveWishes(w);
    return c.json({ ok: true, wishes: w });
  });

  /// App 同步上来（她那边改了）
  app.post('/api/intimacy', async (c) => {
    let body: any = {};
    try { body = await c.req.json(); } catch { return c.json({ error: 'invalid JSON' }, 400); }
    const date = String(body.date || today());
    if (body.deleted) {
      const d = load(); delete d[date]; save(d);
      return c.json({ ok: true, deleted: true });
    }
    const e = upsert(date, {
      note: body.note, myNote: body.myNote, tags: body.tags, milestone: body.milestone,
    }, 'bunny');
    return c.json({ ok: true, entry: e });
  });

  /// App 拉取（他改了她要看到）
  app.get('/api/intimacy', async (c) => c.json({ entries: load() }));
}
