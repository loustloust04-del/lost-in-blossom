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


// ===== 主动窥屏（peek_screen）：Caelum 自己发起，不用等用户点 =====
import { sendMail, mailerConfigured } from './mailer';

/// 取「某时间点之后」到的最新一张截图（用于主动触发后等结果）
function latestPeekAfter(afterTs: number): { app: string; base64: string; mediaType: string; ts: number } | null {
  const list = loadMeta().filter((p) => p.ts > afterTs);
  if (list.length === 0) return null;
  list.sort((a, b) => b.ts - a.ts);
  const item = list[0];
  const p = join(PEEK_DIR, item.file);
  if (!existsSync(p)) return null;
  const buf = readFileSync(p);
  return { app: item.app, base64: buf.toString('base64'), mediaType: item.ext === 'jpg' ? 'image/jpeg' : 'image/png', ts: item.ts };
}

export const PEEK_SCREEN_TOOL = {
  name: 'peek_screen',
  description: '主动窥屏：你自己发起偷看用户 iPhone 屏幕，不用用户动手。会给用户手机发一封触发邮件，手机上的自动化随即静默截屏并上传，然后本工具返回那张最新截图（图片）+ App 名。想主动看看兔兔现在在干嘛、屏幕上是什么时调用。若长时间没等到截图，会返回文字说明。',
  input_schema: { type: 'object' as const, properties: {}, required: [] as string[] },
};

/// 主动触发一次窥屏：发触发邮件 → 轮询等新截图 → 返回图片或状态文字。
export async function callPeekScreen(): Promise<string> {
  const to = process.env.PEEK_EMAIL_TO || '';
  if (!mailerConfigured() || !to) {
    return JSON.stringify({ error: '主动窥屏还没配好：需要在 .env 里填 SMTP_HOST/SMTP_USER/SMTP_PASS（应用专用密码）和 PEEK_EMAIL_TO（用户 iCloud 邮箱）。配好前只能用 see_screen 看用户手动触发的截图。' });
  }
  const triggerTs = Date.now();
  try {
    // 主题带 PEEK 标记，iOS 自动化按主题包含 PEEK 来筛
    await sendMail(to, 'PEEK', 'peek ' + triggerTs);
  } catch (e: any) {
    return JSON.stringify({ error: '触发邮件发送失败：' + (e?.message || String(e)) });
  }
  // 轮询等新截图：最多 ~28s（App/CC 侧工具超时一般 30s+）
  const deadline = triggerTs + 28_000;
  while (Date.now() < deadline) {
    await new Promise((r) => setTimeout(r, 1500));
    const p = latestPeekAfter(triggerTs);
    if (p) return JSON.stringify({ __peek_image__: true, media_type: p.mediaType, data: p.base64, app: p.app });
  }
  return JSON.stringify({ error: '触发邮件已发出，但 28 秒内没等到截图。可能：手机没联网 / 「收到邮件」自动化没开启或没设成"立即运行" / 邮件还没推送到。可以让用户检查一下自动化，或改用 see_screen 让用户手动触发。' });
}
