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
