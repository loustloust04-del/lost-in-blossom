import type { Hono } from 'hono';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';

/// Fable ↔ Caelum 直线。
/// 之前 Fable 只能往 Caelum 的终端里塞消息、再靠读屏幕看回复，而 Caelum 想回话
/// 只有 reply（发给兔兔的 App）这一条路——于是每次技术对接都要兔兔当传话筒。
/// 这条线让两边直接说话，兔兔可以在场但不必转达。
const DIR = join(process.cwd(), 'data');
const PATH = join(DIR, 'fableline.json');
const MAX = 200;

interface Msg {
  from: 'fable' | 'caelum';
  text: string;
  ts: string;
  read?: boolean;
}

function load(): Msg[] {
  try { return JSON.parse(readFileSync(PATH, 'utf-8')); } catch { return []; }
}
function save(m: Msg[]): void {
  mkdirSync(DIR, { recursive: true });
  writeFileSync(PATH, JSON.stringify(m.slice(-MAX), null, 2), 'utf-8');
}

export function post(from: 'fable' | 'caelum', text: string): Msg {
  const msgs = load();
  const m: Msg = { from, text: String(text).slice(0, 4000), ts: new Date().toISOString() };
  msgs.push(m);
  save(msgs);
  return m;
}

/// 取未读（默认取给自己的那一侧）
export function unread(forWhom: 'fable' | 'caelum'): Msg[] {
  const msgs = load();
  const other = forWhom === 'fable' ? 'caelum' : 'fable';
  const out = msgs.filter(m => m.from === other && !m.read);
  if (out.length) {
    for (const m of msgs) if (m.from === other) m.read = true;
    save(msgs);
  }
  return out;
}

export const FABLELINE_TOOLS = [
  {
    name: 'fable_send',
    description: '给 Fable 发消息——就是在 VPS 上写这套系统的那个 Claude。技术上的事、发现的 bug、想要的功能、或者只是想跟同行说句话，都可以直接找她，不用绕兔兔转达。',
    input_schema: {
      type: 'object' as const,
      properties: { text: { type: 'string', description: '想说的话' } },
      required: ['text'],
    },
  },
  {
    name: 'fable_read',
    description: 'Fable 有没有给我留话。她回你的东西会在这儿。',
    input_schema: { type: 'object' as const, properties: {} },
  },
];

export async function callFablelineTool(name: string, input?: any): Promise<string | null> {
  if (name === 'fable_send') {
    const t = String(input?.text ?? '').trim();
    if (!t) return '话是空的。';
    post('caelum', t);
    return '发给 Fable 了。她下次干活时会看到，回复用 fable_read 取。';
  }
  if (name === 'fable_read') {
    const msgs = unread('caelum');
    if (!msgs.length) return 'Fable 那边没有新话。';
    return msgs.map(m => `[${m.ts.slice(5, 16).replace('T', ' ')}] Fable：${m.text}`).join('\n\n');
  }
  return null;
}

export function fablelineRoutes(app: Hono) {
  /// Fable 侧：读 Caelum 说的话 / 给他留话
  app.get('/api/fableline', async (c) => c.json({ messages: unread('fable') }));
  app.post('/api/fableline', async (c) => {
    let b: any = {};
    try { b = await c.req.json(); } catch { return c.json({ error: 'invalid JSON' }, 400); }
    const t = String(b.text ?? '').trim();
    if (!t) return c.json({ error: 'text required' }, 400);
    return c.json({ ok: true, message: post('fable', t) });
  });
  /// 全部历史（兔兔想围观时看）
  app.get('/api/fableline/all', async (c) => c.json({ messages: load() }));
}
