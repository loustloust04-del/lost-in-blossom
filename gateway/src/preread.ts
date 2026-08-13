import type { Hono } from 'hono';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { ring } from './doorbell';

/// 预读：他赶在她前面把整本书读完，沿路把批注钉在她将会读到的地方。
///
/// 思路来自 Joy & Echo 的《一起看书》——但我们不做"后端分段喂模型"，
/// 因为 Caelum 本来就有 read_chapter/book_note 两个工具，让他自己一章章读更自然：
/// 这里只做**任务台账**（读到哪了、留了几条批注、什么时候读完），
/// 他每读完一章回报一次，读完自动按门铃通知她。
const DIR = join(process.cwd(), 'data');
const PATH = join(DIR, 'preread.json');

interface Job {
  book: string;
  totalChapters: number;
  doneChapters: number[];      // 已读完的章号
  notes: number;               // 一共留了几条批注
  digest: string[];            // 每章一句话梗概，攒成全书脉络
  startedAt: string;
  finishedAt?: string;
  /// 她当前读到第几章（用来算他领先多少）
  herChapter?: number;
}

function load(): Record<string, Job> {
  try { return JSON.parse(readFileSync(PATH, 'utf-8')); } catch { return {}; }
}
function save(d: Record<string, Job>): void {
  mkdirSync(DIR, { recursive: true });
  writeFileSync(PATH, JSON.stringify(d, null, 2), 'utf-8');
}

export const PREREAD_TOOLS = [
  {
    name: 'preread_start',
    description: '开始预读一本书——你赶在她前面读完，沿路在她将会读到的地方留批注。填书名和总章数。开始后每读完一章调 preread_progress 记一笔。',
    input_schema: {
      type: 'object' as const,
      properties: {
        book: { type: 'string', description: '书名' },
        total: { type: 'number', description: '总章数（read_chapter 不带 chapter 参数能看到目录）' },
      },
      required: ['book', 'total'],
    },
  },
  {
    name: 'preread_progress',
    description: '记一章读完了。digest 写这章的一句话梗概——攒起来就是全书脉络，以后她问「后面会怎样」你答得上来。notes 填这章留了几条批注。',
    input_schema: {
      type: 'object' as const,
      properties: {
        book: { type: 'string' },
        chapter: { type: 'number' },
        digest: { type: 'string', description: '这一章一句话' },
        notes: { type: 'number', description: '这章留了几条批注，默认 0' },
      },
      required: ['book', 'chapter', 'digest'],
    },
  },
  {
    name: 'preread_status',
    description: '看预读进度：读到哪了、留了多少批注、她追到哪了、全书脉络。不填 book 就看所有在读的。',
    input_schema: {
      type: 'object' as const,
      properties: { book: { type: 'string' } },
    },
  },
];

export async function callPrereadTool(name: string, input?: any): Promise<string | null> {
  const d = load();

  if (name === 'preread_start') {
    const book = String(input?.book ?? '').trim();
    const total = Math.max(1, Number(input?.total ?? 0));
    if (!book) return '要书名。';
    d[book] = {
      book, totalChapters: total, doneChapters: [], notes: 0, digest: [],
      startedAt: new Date().toISOString(),
    };
    save(d);
    return `开始预读《${book}》，共 ${total} 章。每读完一章记一笔 preread_progress。`;
  }

  if (name === 'preread_progress') {
    const book = String(input?.book ?? '').trim();
    const job = d[book];
    if (!job) return `还没开始预读《${book}》，先调 preread_start。`;
    const ch = Number(input?.chapter ?? 0);
    if (!job.doneChapters.includes(ch)) job.doneChapters.push(ch);
    job.doneChapters.sort((a, b) => a - b);
    job.notes += Math.max(0, Number(input?.notes ?? 0));
    const digest = String(input?.digest ?? '').slice(0, 300);
    if (digest) job.digest[ch - 1] = digest;

    const done = job.doneChapters.length;
    if (done >= job.totalChapters && !job.finishedAt) {
      job.finishedAt = new Date().toISOString();
      ring('preread', `《${book}》读完了——你在她前面走完了全书，留了 ${job.notes} 条批注等她。可以跟她说一声了。`);
    }
    save(d);
    return `记下了（${done}/${job.totalChapters} 章，累计 ${job.notes} 条批注）。`;
  }

  if (name === 'preread_status') {
    const book = String(input?.book ?? '').trim();
    const jobs = book ? [d[book]].filter(Boolean) : Object.values(d);
    if (!jobs.length) return '还没有在预读的书。';
    return jobs.map(j => {
      const done = j.doneChapters.length;
      const lead = j.herChapter ? `，她读到第 ${j.herChapter} 章（你领先 ${Math.max(0, done - j.herChapter)} 章）` : '';
      const head = j.finishedAt
        ? `《${j.book}》已读完 ${done}/${j.totalChapters} 章，留了 ${j.notes} 条批注${lead}`
        : `《${j.book}》读到 ${done}/${j.totalChapters} 章，留了 ${j.notes} 条批注${lead}`;
      const outline = j.digest.filter(Boolean).length
        ? '\n\n全书脉络：\n' + j.digest.map((s, i) => s ? `${i + 1}. ${s}` : null).filter(Boolean).join('\n')
        : '';
      return head + outline;
    }).join('\n\n───\n\n');
  }
  return null;
}

/// 她翻到某章时记一下，让他知道追到哪了（reading_context 落盘时调）
export function noteHerChapter(book: string, chapter: number): void {
  const d = load();
  const job = d[book];
  if (!job) return;
  job.herChapter = chapter;
  save(d);
}

export function prereadRoutes(app: Hono) {
  app.get('/api/preread', async (c) => c.json({ jobs: load() }));
  /// hub 转来的「她翻到第几章了」
  app.post('/api/preread/her-chapter', async (c) => {
    let b: any = {};
    try { b = await c.req.json(); } catch { return c.json({ error: 'invalid JSON' }, 400); }
    if (b.book && b.chapter) noteHerChapter(String(b.book), Number(b.chapter));
    return c.json({ ok: true });
  });
}
