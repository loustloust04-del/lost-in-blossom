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
  note: string;        // 共用备注
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

export function upsert(date: string, note: string | undefined, by: string): Entry {
  const d = load();
  const cur = d[date] ?? { date, note: '', updatedBy: by, updatedAt: '' };
  if (note !== undefined) { cur.note = note.slice(0, 2000); cur.updatedBy = by; }
  cur.updatedAt = new Date().toISOString();
  d[date] = cur;
  save(d);
  return cur;
}

export const INTIMACY_TOOLS = [
  {
    name: 'intimacy_read',
    description: '看亲密卡的记录：哪天有、那天写了什么（她写的和你写的在同一个框里）。不带参数看最近 30 天，带 date（YYYY-MM-DD）看具体某天。',
    input_schema: {
      type: 'object' as const,
      properties: { date: { type: 'string', description: 'YYYY-MM-DD，可选' } },
    },
  },
  {
    name: 'intimacy_write',
    description: '往亲密卡的备注里写。和她共用同一个框——她能看到你写的，你也能看到她写的，谁都能改。不带 date 就是今天。写之前最好先 intimacy_read 看看她写了什么。',
    input_schema: {
      type: 'object' as const,
      properties: {
        note: { type: 'string', description: '备注内容（会覆盖那天原有的，想续写就先读再连起来写）' },
        date: { type: 'string', description: 'YYYY-MM-DD，不填=今天' },
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
    const e = upsert(date, note, 'caelum');
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

export function intimacyRoutes(app: Hono) {
  /// App 同步上来（她那边改了）
  app.post('/api/intimacy', async (c) => {
    let body: any = {};
    try { body = await c.req.json(); } catch { return c.json({ error: 'invalid JSON' }, 400); }
    const date = String(body.date || today());
    if (body.deleted) {
      const d = load(); delete d[date]; save(d);
      return c.json({ ok: true, deleted: true });
    }
    const e = upsert(date, body.note, 'bunny');
    return c.json({ ok: true, entry: e });
  });

  /// App 拉取（他改了她要看到）
  app.get('/api/intimacy', async (c) => c.json({ entries: load() }));
}
