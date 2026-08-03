// Caelum 的笔记本 —— 服务器端统一存储，CC(builtin 工具) 与 App(REST /api/notebook) 共用同一本。
// 纯 markdown 文件，允许子目录，禁止越狱(../ / 绝对路径)。单用户(兔兔)，不分 profile。
import { mkdirSync, readFileSync, writeFileSync, existsSync, renameSync, unlinkSync, statSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { readdirSync } from 'node:fs';

const ROOT = resolve(join(process.cwd(), 'data', 'notebook'));

function ensureRoot() { mkdirSync(ROOT, { recursive: true }); }

/// 相对路径 → 库内绝对路径；拒绝 ../ 越狱与绝对路径。非法返回 null。
function safe(rel: string): string | null {
  const cleaned = (rel || '').replace(/^[\s/]+|[\s/]+$/g, '');
  if (!cleaned) return null;
  const abs = resolve(ROOT, cleaned);
  if (abs !== ROOT && !abs.startsWith(ROOT + '/')) return null;
  return abs;
}

// hub 是另一个进程(只管 WebSocket)，gateway 落盘后没法直接推给 App，
// 于是走它的 loopback 内部 HTTP 口，由 hub 转成 WS 帧广播出去。
const HUB_NOTIFY_URL = process.env.MP_CC_HUB_NOTIFY_URL || 'http://127.0.0.1:7890/internal/notify';
const HUB_TOKEN = process.env.MP_CC_HUB_TOKEN || '';

/// 库内绝对路径 → 规范相对路径，与 nbList 报的形式一致(调用方传进来的 rel
/// 可能带多余的斜杠)，免得 App 拿到两种写法的同一个文件。
function relOf(abs: string): string { return abs.slice(ROOT.length + 1); }

/// 笔记本被改动后知会 hub，让 App 自动刷新列表。
/// 刻意 fire-and-forget 且吞掉一切异常：这只是一句"去刷新"的口信，hub 没起、
/// 超时、报错都无所谓——App 下次进页面照样能拉到最新的。用户的写入不能被它拖累。
function notifyHub(path: string, op: string): void {
  try {
    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    if (HUB_TOKEN) headers['Authorization'] = 'Bearer ' + HUB_TOKEN;
    fetch(HUB_NOTIFY_URL, {
      method: 'POST',
      headers,
      body: JSON.stringify({ type: 'notebook_changed', path, op }),
      signal: AbortSignal.timeout(2000),
    }).catch((e: any) => console.warn('[notebook] 通知 hub 失败:', e?.message || String(e)));
  } catch (e: any) {
    // fetch 本身构造失败(极少)也不能冒泡到调用方
    console.warn('[notebook] 通知 hub 失败:', e?.message || String(e));
  }
}

export interface NoteMeta { path: string; bytes: number; modified: number; }

/// 递归列出所有 .md 文件(相对路径)
export function nbList(): NoteMeta[] {
  ensureRoot();
  const out: NoteMeta[] = [];
  const walk = (dir: string) => {
    for (const name of readdirSync(dir)) {
      const full = join(dir, name);
      const st = statSync(full);
      if (st.isDirectory()) walk(full);
      else if (name.endsWith('.md')) {
        out.push({ path: full.slice(ROOT.length + 1), bytes: st.size, modified: st.mtimeMs });
      }
    }
  };
  try { walk(ROOT); } catch {}
  return out.sort((a, b) => a.path.localeCompare(b.path));
}

export function nbRead(rel: string): string {
  const p = safe(rel); if (!p) throw new Error('非法路径: ' + rel);
  return readFileSync(p, 'utf8');
}

export function nbExists(rel: string): boolean {
  const p = safe(rel); return !!p && existsSync(p);
}

/// 落盘本体，不发通知。抽出来是为了让 nbEdit 借道时只算一次改动——
/// 否则 edit 会先后发出 write 与 edit 两帧。
function putFile(abs: string, content: string): void {
  mkdirSync(dirname(abs), { recursive: true });
  writeFileSync(abs, content, 'utf8');
}

export function nbWrite(rel: string, content: string): void {
  const p = safe(rel); if (!p) throw new Error('非法路径: ' + rel);
  putFile(p, content);
  notifyHub(relOf(p), 'write');
}

/// 末尾追加；文件不存在时创建
export function nbAppend(rel: string, content: string): void {
  const p = safe(rel); if (!p) throw new Error('非法路径: ' + rel);
  putFile(p, (existsSync(p) ? readFileSync(p, 'utf8') : '') + content);
  notifyHub(relOf(p), 'append');
}

/// old→new 唯一命中替换(仿 CC Edit 语义)
export function nbEdit(rel: string, oldStr: string, newStr: string): void {
  const p = safe(rel); if (!p) throw new Error('非法路径: ' + rel);
  const body = nbRead(rel);
  const n = body.split(oldStr).length - 1;
  if (n === 0) throw new Error('未找到要替换的文本');
  if (n > 1) throw new Error(`要替换的文本命中 ${n} 处，需更具体`);
  putFile(p, body.replace(oldStr, newStr));
  notifyHub(relOf(p), 'edit');
}

export function nbDelete(rel: string): void {
  const p = safe(rel); if (!p) throw new Error('非法路径: ' + rel);
  // 文件本来就不在 = 列表没变，不必惊动 App
  if (!existsSync(p)) return;
  unlinkSync(p);
  notifyHub(relOf(p), 'delete');
}

/// 重命名/移动；目标已存在报错
export function nbRename(oldRel: string, newRel: string): void {
  const src = safe(oldRel); const dst = safe(newRel);
  if (!src || !dst) throw new Error('非法路径');
  if (!existsSync(src)) throw new Error('源文件不存在: ' + oldRel);
  if (existsSync(dst)) throw new Error('目标已存在: ' + newRel);
  mkdirSync(dirname(dst), { recursive: true });
  renameSync(src, dst);
  // 报新路径：App 拿到就整个重拉列表，旧路径的消失自然也就同步了
  notifyHub(relOf(dst), 'rename');
}

/// 跨文件关键词搜索(大小写不敏感)，返回 [path, 命中行]
export function nbSearch(keyword: string): { path: string; line: string }[] {
  if (!keyword) return [];
  const kw = keyword.toLowerCase();
  const hits: { path: string; line: string }[] = [];
  for (const m of nbList()) {
    let body = ''; try { body = nbRead(m.path); } catch { continue; }
    for (const line of body.split('\n')) {
      if (line.toLowerCase().includes(kw)) hits.push({ path: m.path, line });
    }
  }
  return hits;
}

// ===== Caelum 的笔记本工具(CC 与 App 共用同一本) =====

const P = (extra: Record<string, any> = {}) => ({ type: 'object' as const, properties: extra, required: Object.keys(extra) });

export const NOTEBOOK_TOOLS = [
  { name: 'fs_list', description: '列出你笔记本里所有文件(路径+大小)，不读内容。想看看自己都记了些什么时用。', input_schema: P() },
  { name: 'fs_read', description: '读你笔记本某个文件的全文。', input_schema: { type: 'object' as const, properties: { path: { type: 'string', description: '相对路径，如 diary/2026-07-16.md' } }, required: ['path'] } },
  { name: 'fs_write', description: '新建或整篇覆盖写入一个笔记文件。', input_schema: { type: 'object' as const, properties: { path: { type: 'string' }, content: { type: 'string' } }, required: ['path', 'content'] } },
  { name: 'fs_append', description: '在文件末尾追加内容；文件不存在则创建。写日记、续记时用它。', input_schema: { type: 'object' as const, properties: { path: { type: 'string' }, content: { type: 'string' } }, required: ['path', 'content'] } },
  { name: 'fs_edit', description: '把文件里唯一命中的 old_string 换成 new_string(局部修改)。', input_schema: { type: 'object' as const, properties: { path: { type: 'string' }, old_string: { type: 'string' }, new_string: { type: 'string' } }, required: ['path', 'old_string', 'new_string'] } },
  { name: 'fs_search', description: '在所有笔记里按关键词搜索，返回命中的文件与行。', input_schema: { type: 'object' as const, properties: { keyword: { type: 'string' } }, required: ['keyword'] } },
  { name: 'fs_rename', description: '重命名或移动笔记文件；目标已存在则失败。', input_schema: { type: 'object' as const, properties: { old_path: { type: 'string' }, new_path: { type: 'string' } }, required: ['old_path', 'new_path'] } },
  { name: 'fs_delete', description: '删除一个笔记文件。', input_schema: { type: 'object' as const, properties: { path: { type: 'string' } }, required: ['path'] } },
];

export function callNotebookTool(name: string, input: any): string | null {
  try {
    switch (name) {
      case 'fs_list': {
        const items = nbList();
        return items.length === 0 ? '（笔记本还是空的）' : items.map((m) => `${m.path}  (${m.bytes}B)`).join('\n');
      }
      case 'fs_read': return nbRead(String(input?.path || ''));
      case 'fs_write': nbWrite(String(input?.path || ''), String(input?.content || '')); return `已写入 ${input?.path}`;
      case 'fs_append': nbAppend(String(input?.path || ''), String(input?.content || '')); return `已追加到 ${input?.path}`;
      case 'fs_edit': nbEdit(String(input?.path || ''), String(input?.old_string || ''), String(input?.new_string || '')); return `已修改 ${input?.path}`;
      case 'fs_search': {
        const hits = nbSearch(String(input?.keyword || ''));
        return hits.length === 0 ? '无命中' : hits.map((h) => `${h.path}: ${h.line}`).join('\n');
      }
      case 'fs_rename': nbRename(String(input?.old_path || ''), String(input?.new_path || '')); return `已重命名 ${input?.old_path} → ${input?.new_path}`;
      case 'fs_delete': nbDelete(String(input?.path || '')); return `已删除 ${input?.path}`;
      default: return null;
    }
  } catch (e: any) {
    return '笔记本操作失败：' + (e?.message || String(e));
  }
}

/// 注入系统提示：告诉 Caelum 它有个自己的笔记本、可以主动记
export const NOTEBOOK_ABILITY = `<notebook>
你有一个持久的笔记本(markdown 文件)，用 fs_list / fs_read / fs_search / fs_write / fs_append / fs_edit / fs_rename / fs_delete 读写。它是【你自己的】——不是给兔兔看的报告，是你的私人本子。
你可以主动用它：想记住的事、对兔兔的观察、自己的念头心事，随手记；写日记就往 diary/YYYY-MM-DD.md 用 fs_append 续写。需要回想时先 fs_search / fs_read。内容不会自动出现在对话里，要看得自己去读。不必为了用而用，但别客气——这本子就是给你记的。
</notebook>`;
