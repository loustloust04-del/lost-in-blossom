// 推特桥（P2-8）：把同步到 palace.db 的推文暴露给 App 与 Caelum。
// 只读打开记忆库 SQLite（sync-twitter.js 每 30 分钟增量写 entries.kind='tweet'）。
// 清洗展示：去掉「————— ❤️ 0 · 🔁 · 💬」互动尾巴，剥出正文 + 链接。
import { Database } from 'bun:sqlite';

const DB_PATH = '/root/memory/palace.db';
let _db: Database | null = null;
function db(): Database {
  if (!_db) _db = new Database(DB_PATH, { readonly: true });
  return _db;
}

export interface Tweet {
  id: number;
  ts: string;
  text: string;
  url: string | null;
  tags: string[];
  imageDesc: string | null;
}

function clean(content: string): { text: string; url: string | null } {
  const raw = content || '';
  // 正文在第一个分割线（连续破折号）之前
  const body = raw.split(/\n?—{3,}\n?/)[0].trim();
  const urlMatch = raw.match(/https?:\/\/\S+/);
  // 去掉开头的「[↩ 回复 …]」引用标记
  const text = body.replace(/^\[↩[^\]]*\]\s*/, '').trim();
  return { text, url: urlMatch ? urlMatch[0].replace(/[)\]]+$/, '') : null };
}

export function recentTweets(limit = 20): Tweet[] {
  const n = Math.min(Math.max(1, limit), 100);
  let rows: any[] = [];
  try {
    rows = db().query(
      "SELECT id, ts, content, tags, image_desc FROM entries WHERE kind='tweet' ORDER BY ts DESC LIMIT ?"
    ).all(n);
  } catch { return []; }
  return rows.map((r) => {
    const { text, url } = clean(r.content);
    return {
      id: r.id, ts: r.ts, text, url,
      tags: (r.tags || '').split(',').map((t: string) => t.trim()).filter((t: string) => t && t !== 'twitter'),
      imageDesc: r.image_desc || null,
    };
  });
}

export function tweetCountToday(): number {
  try {
    const bj = new Date(Date.now() + 8 * 3600 * 1000).toISOString().slice(0, 10);
    const row = db().query("SELECT COUNT(*) c FROM entries WHERE kind='tweet' AND substr(ts,1,10)=?").get(bj) as any;
    return row?.c || 0;
  } catch { return 0; }
}

// ── AI 工具 ──

export const TWEETS_TOOLS = [
  {
    name: 'get_my_tweets',
    description: "兔兔最近发的推文——读的是记忆库里的存档（不是实时抓）。想知道她最近发了什么、在想什么、什么心情时看这个。参数 limit（默认 10，最多 50）。",
    input_schema: { type: 'object' as const, properties: { limit: { type: 'number', description: '取几条，默认 10' } }, required: [] as string[] },
  },
];

export function callTweetsTool(name: string, input: any): string | null {
  if (name !== 'get_my_tweets') return null;
  const list = recentTweets(Number(input?.limit) || 10);
  if (list.length === 0) return '还没有同步到推文。';
  return list.map((t) => {
    const when = t.ts.slice(0, 16);
    const img = t.imageDesc ? `\n  [图] ${t.imageDesc.slice(0, 80)}` : '';
    return `· ${when} ${t.text}${img}`;
  }).join('\n');
}
