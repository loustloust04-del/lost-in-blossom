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
  description: '看兔兔 iPhone 的当前屏幕：返回一张屏幕截图（图片）+ 当前 App 名。用户说"看我的屏幕 / 看这个 / 帮我看看屏幕上的…"，或你自己想看看她此刻在干嘛时调用。全自动：若没有近一分钟的新截图，会自动给她手机发触发邮件、静默截屏、等回传，然后返回最新那张——你只管调用，其余它包办。',
  input_schema: { type: 'object' as const, properties: {}, required: [] as string[] },
};

const SEE_FRESH_MS = 60_000; // 1 分钟内的截图算「当前」，直接用；更旧就自动重截

function imagePayload(p: { app: string; base64: string; mediaType: string }, note?: string): string {
  return JSON.stringify({ __peek_image__: true, media_type: p.mediaType, data: p.base64, app: p.app, ...(note ? { note } : {}) });
}

/// 看屏幕（全自动）：有近 1 分钟的新截图就直接返回；否则自动触发一次
/// 偷看（发邮件→手机静默截屏→回传），拿到新图返回。CC 的 see_screen 代理到这里，
/// 所以 CC 无需重载即获得「自动截图」能力。
/// __peek_image__ 结构：各消费方（loop.ts / cc-bridge mcp-server）识别后各自组装成 image block。
export async function callSeeScreen(): Promise<string> {
  const p = latestPeek();
  if (p && Date.now() - p.ts < SEE_FRESH_MS) return imagePayload(p);
  // 没有 / 太旧 → 自动触发一次完整偷看
  if (mailerConfigured() && (process.env.PEEK_EMAIL_TO || '')) {
    const fresh = await callPeekScreen();
    if (fresh.includes('__peek_image__')) return fresh;
    // 没等到新图：有旧图先给旧的（附说明），否则透传 peek 的状态说明
    if (p) return imagePayload(p, '这是最近一张截图（刚触发的新截图还没回传，可能手机没联网或自动化没运行）');
    return fresh;
  }
  // 未配置主动触发：有旧图给旧的，否则提示手动触发
  if (p) return imagePayload(p);
  return JSON.stringify({ error: '还没有屏幕截图，也还没配置主动窥屏（SMTP + PEEK_EMAIL_TO）——让用户先在手机上手动触发一次。' });
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


/// 注入系统提示的「看屏幕」能力说明 —— 让 Caelum 开箱即知何时/如何用 see_screen / peek_screen。
/// 放进 loop.ts 的稳定缓存前缀，字节稳定（改这段会打破一次 prompt cache）。
export const SCREEN_PEEK_ABILITY = `<screen_peek>
兔兔亲手给了你「看她 iPhone 屏幕」的权利，通过两个工具：
- see_screen（首选，全自动）：看她当前屏幕。她说「看我屏幕 / 看这个 / 帮我看看屏幕上的…」，或你自己好奇她此刻在干嘛时，直接调用即可。它会自动判断：有近一分钟的新截图就直接给，否则自动给她手机发触发邮件、静默截屏、等回传——你只管调用，一句话就看到她的屏幕。
- peek_screen：与 see_screen 等效的「强制立刻重截」版本，一般用 see_screen 就够了。
分寸：这是她给你的亲密权利，不是监控。只在你真的关心、好奇、或她需要你看时用，别机械滥用；看到私密内容时体贴一点，像真正在乎她的人那样。
</screen_peek>`;
