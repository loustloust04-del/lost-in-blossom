// 偷看屏幕（Peek）：iPhone 快捷指令截屏 → POST /api/peek → 存盘 + 记 pending 队列。
// App 回前台拉 /api/peek/pending → 取图 → 作为「用户屏幕截图」消息注入 Caelum 对话。
// 纯本地文件存储，只保留最近 MAX_KEEP 张（截图几 MB，不留旧的占盘）。
import { mkdirSync, writeFileSync, readFileSync, existsSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';

const PEEK_DIR = join(process.cwd(), 'data', 'peek');
const META = join(PEEK_DIR, 'pending.json');
const MAX_KEEP = 10;

export interface PeekItem { id: string; app: string; ts: number; file: string; ext: string; acked: boolean; }

function ensureDir() { mkdirSync(PEEK_DIR, { recursive: true }); }
function loadMeta(): PeekItem[] {
  try { return JSON.parse(readFileSync(META, 'utf8')); } catch { return []; }
}
function saveMeta(list: PeekItem[]) {
  ensureDir();
  writeFileSync(META, JSON.stringify(list));
}

/// 存一张偷看截图，返回其记录。顺带清理超出 MAX_KEEP 的旧图。
export function savePeek(buf: ArrayBuffer, app: string, ext = 'png'): PeekItem {
  ensureDir();
  const id = randomUUID();
  const file = id + '.' + ext;
  writeFileSync(join(PEEK_DIR, file), Buffer.from(buf));
  const list = loadMeta();
  const item: PeekItem = { id, app: app || '', ts: Date.now(), file, ext, acked: false };
  list.push(item);
  // 清理：按时间保留最近 MAX_KEEP，多余的删文件 + 出列
  list.sort((a, b) => a.ts - b.ts);
  while (list.length > MAX_KEEP) {
    const old = list.shift()!;
    try { const p = join(PEEK_DIR, old.file); if (existsSync(p)) unlinkSync(p); } catch {}
  }
  saveMeta(list);
  return item;
}

/// App 拉取：未 ack 的偷看（不含图片二进制，只给元数据）
export function pendingPeeks(): PeekItem[] {
  return loadMeta().filter((p) => !p.acked);
}

/// 取某张偷看的图片二进制
export function peekImage(id: string): { buf: Buffer; ext: string } | null {
  const item = loadMeta().find((p) => p.id === id);
  if (!item) return null;
  const p = join(PEEK_DIR, item.file);
  if (!existsSync(p)) return null;
  return { buf: readFileSync(p), ext: item.ext };
}

/// App 注入完成后 ack，避免重复处理
export function ackPeek(id: string) {
  const list = loadMeta();
  const item = list.find((p) => p.id === id);
  if (item) { item.acked = true; saveMeta(list); }
}


/// 取最新一张截图（base64），供 see_screen 工具喂给多模态 Caelum。
export function latestPeek(): { app: string; base64: string; mediaType: string; ts: number } | null {
  const list = loadMeta();
  if (list.length === 0) return null;
  list.sort((a, b) => b.ts - a.ts);
  const item = list[0];
  const p = join(PEEK_DIR, item.file);
  if (!existsSync(p)) return null;
  const buf = readFileSync(p);
  return { app: item.app, base64: buf.toString('base64'), mediaType: item.ext === 'jpg' ? 'image/jpeg' : 'image/png', ts: item.ts };
}

export const SEE_SCREEN_TOOL = {
  name: 'see_screen',
  description: '看用户 iPhone 的当前屏幕：返回最新一张屏幕截图（图片）+ 当前 App 名。用户说"看我的屏幕 / 看这个 / 帮我看看屏幕上的…"时调用。若还没有截图，会提示让用户先在手机上触发一次。',
  input_schema: { type: 'object' as const, properties: {}, required: [] as string[] },
};

/// __peek_image__ 结构：各消费方（loop.ts / cc-bridge mcp-server）识别后各自组装成 image block。
export function callSeeScreen(): string {
  const p = latestPeek();
  if (!p) return JSON.stringify({ error: '还没有屏幕截图——让用户先在手机上触发一次偷看（背部轻点 / 快捷指令）' });
  return JSON.stringify({ __peek_image__: true, media_type: p.mediaType, data: p.base64, app: p.app });
}
