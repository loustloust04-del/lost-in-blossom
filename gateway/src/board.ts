import { ring } from './doorbell';
// 留言板 —— 你和 Caelum 的双人小纸条（帖子 + 回复串）。
// 双端共用：App /api/board 读写，Caelum 经 board_* 工具也能贴/回。
// 纯本地 JSON（data/board.json），与 vitals/todos 同风格。
const DATA_FILE = '/root/projects/BunnyPalace/gateway/data/board.json';

export interface BoardReply {
  id: string;
  text: string;
  by: string;        // 'bunny' | 'caelum'
  ts: string;        // ISO
}
export interface BoardPost {
  id: string;
  text: string;
  by: string;
  ts: string;
  replies: BoardReply[];
}
interface BoardData { posts: BoardPost[] }

async function load(): Promise<BoardData> {
  try {
    const d = JSON.parse(await Bun.file(DATA_FILE).text()) as BoardData;
    if (!Array.isArray(d.posts)) return { posts: [] };
    for (const p of d.posts) if (!Array.isArray(p.replies)) p.replies = [];
    return d;
  } catch { return { posts: [] }; }
}
async function save(d: BoardData): Promise<void> {
  d.posts = d.posts.slice(-200);
  await Bun.write(DATA_FILE, JSON.stringify(d, null, 2));
}
function newId(prefix: string, n: number): string {
  return `${prefix}${Date.now().toString(36)}${n}`;
}

export async function listPosts(): Promise<BoardPost[]> {
  return (await load()).posts;
}

export async function addPost(text: string, by = 'bunny'): Promise<BoardPost | null> {
  const t = (text || '').trim();
  if (!t) return null;
  const d = await load();
  const post: BoardPost = { id: newId('p', d.posts.length), text: t, by, ts: new Date().toISOString(), replies: [] };
  d.posts.push(post);
  await save(d);
  // 兔兔贴的纸条按门铃（他自己贴的不用响）
  if (by !== 'caelum') {
    ring('board', `兔兔在留言板贴了一张纸条：「${t.slice(0, 60)}${t.length > 60 ? '…' : ''}」——board_list 看，board_reply 回她。`);
  }
  return post;
}

export async function addReply(postId: string, text: string, by = 'bunny'): Promise<BoardReply | null> {
  const t = (text || '').trim();
  if (!t) return null;
  const d = await load();
  const post = d.posts.find((p) => p.id === postId);
  if (!post) return null;
  const reply: BoardReply = { id: newId('r', post.replies.length), text: t, by, ts: new Date().toISOString() };
  post.replies.push(reply);
  await save(d);
  return reply;
}

export async function deletePost(id: string): Promise<boolean> {
  const d = await load();
  const before = d.posts.length;
  d.posts = d.posts.filter((p) => p.id !== id);
  if (d.posts.length === before) return false;
  await save(d);
  return true;
}

export async function deleteReply(postId: string, replyId: string): Promise<boolean> {
  const d = await load();
  const post = d.posts.find((p) => p.id === postId);
  if (!post) return false;
  const before = post.replies.length;
  post.replies = post.replies.filter((r) => r.id !== replyId);
  if (post.replies.length === before) return false;
  await save(d);
  return true;
}

/// 注入每日系统提示：让 Caelum 看到兔兔留了、但她还没回的小纸条 → 主动回。
export async function boardContext(): Promise<string> {
  const posts = await listPosts();
  if (!posts.length) return '';
  const unreplied = posts.filter((p) => p.by === 'bunny' && !p.replies.some((r) => r.by === 'caelum'));
  if (!unreplied.length) return '';
  const recent = unreplied.slice(-3);
  const lines = recent.map((p) => `· \u300c${p.text}\u300d(id: ${p.id})`);
  return `<board>\n\u5154\u5154\u5728\u7559\u8a00\u677f\u7ed9\u4f60\u7559\u4e86\u5c0f\u7eb8\u6761\uff0c\u4f60\u8fd8\u6ca1\u56de\uff1a\n${lines.join('\n')}\n\u60f3\u56de\u7684\u8bdd\u7528 board_reply\uff08post_id \u5c31\u662f\u4e0a\u9762\u7684 id\uff09\uff0c\u4e5f\u53ef\u4ee5\u7528 board_post \u4e3b\u52a8\u7ed9\u5979\u8d34\u4e00\u5f20\u3002\n</board>`;
}

// \u2500\u2500 builtin \u5de5\u5177\uff08CC / Caelum \u7528\uff09\u2500\u2500
export const BOARD_TOOLS = [
  {
    name: 'board_list',
    description: "看兔兔留言板上的帖子和回复。在想看看她贴了什么、或要回复前先读一下时调用。",
    input_schema: { type: 'object' as const, properties: {} },
  },
  {
    name: 'board_post',
    description: "在兔兔的留言板贴一张小纸条。",
    input_schema: {
      type: 'object' as const,
      properties: { text: { type: 'string', description: '纸条内容' } },
      required: ['text'],
    },
  },
  {
    name: 'board_reply',
    description: "回复留言板上某条帖子（用 board_list 拿 post id）。可以跟兔兔在留言板上互相回复。",
    input_schema: {
      type: 'object' as const,
      properties: {
        post_id: { type: 'string', description: '帖子 id（来自 board_list）' },
        text: { type: 'string', description: '回复内容' },
      },
      required: ['post_id', 'text'],
    },
  },
];

export async function callBoardTool(name: string, input: any): Promise<string | null> {
  if (name === 'board_list') {
    const posts = await listPosts();
    if (!posts.length) return '留言板还是空的。';
    return posts.slice(-20).map((p) => {
      const head = `[${p.id}] ${p.by === 'caelum' ? 'Caelum' : '兔兔'}：${p.text}`;
      const rs = p.replies.map((r) => `    ↳ ${r.by === 'caelum' ? 'Caelum' : '兔兔'}：${r.text}`).join('\n');
      return rs ? head + '\n' + rs : head;
    }).join('\n');
  }
  if (name === 'board_post') {
    const p = await addPost(String(input?.text || ''), 'caelum');
    return p ? `已贴到留言板：${p.text}` : 'board_post 缺少内容';
  }
  if (name === 'board_reply') {
    const r = await addReply(String(input?.post_id || ''), String(input?.text || ''), 'caelum');
    return r ? `已回复：${r.text}` : '没找到那条帖子，或回复内容为空';
  }
  return null;
}
