// Pocket Browser —— 让 Caelum 借兔兔手机里的 WKWebView 浏览网页（真机 Safari 渲染 + 已登录会话）。
// 架构：手机 App 经 wss /pocket/ws 注册为执行端；Caelum 工具/HTTP 经 /api/pocket/cmd 下发命令；
// 本模块在网关进程内做中继（id 关联请求-响应，超时回收）。参考 pocket-browser 协议，接进本网关。
import type { ServerWebSocket } from 'bun';
import { config } from './config';
import { randomUUID } from 'node:crypto';

interface Pending {
  resolve: (v: any) => void;
  reject: (e: Error) => void;
  timer: ReturnType<typeof setTimeout>;
}

let phone: ServerWebSocket<any> | null = null;
let lastSeen = 0;
const pending = new Map<string, Pending>();

export function isPocketToken(t: string): boolean {
  if (!t) return false;
  return t === config.pocketToken || t === config.gatewayToken || t === config.gatewayTokenAlt;
}

export function phoneConnected(): boolean { return !!phone; }
export function pocketLastSeen(): number { return lastSeen; }

// ── WebSocket 生命周期（由 index.ts 的 Bun.serve websocket handler 调用）──
export const pocketWSHandler = {
  open(ws: ServerWebSocket<any>) {
    if (phone && phone !== ws) { try { phone.close(); } catch {} }
    phone = ws;
    lastSeen = Date.now();
    console.log('[pocket] 📱 phone connected');
  },
  message(ws: ServerWebSocket<any>, raw: string | Buffer) {
    lastSeen = Date.now();
    let m: any;
    try { m = JSON.parse(raw.toString()); } catch { return; }
    if (!m || typeof m !== 'object') return;
    if (m.type === 'hello' || m.type === 'pong') return;   // 心跳/握手
    const p = pending.get(m.id);
    if (!p) return;
    pending.delete(m.id);
    clearTimeout(p.timer);
    if (m.ok) p.resolve(m.result);
    else p.reject(new Error(String(m.error || 'phone error')));
  },
  close(ws: ServerWebSocket<any>) {
    if (phone === ws) { phone = null; console.log('[pocket] 📴 phone disconnected'); }
  },
};

// 心跳：每 25s ping 一次手机（iOS 系统层自动回 pong，保活 WS）
setInterval(() => { if (phone) { try { phone.ping(); } catch {} } }, 25000);

/// 下发一条命令给手机，等待带同 id 的回复。timeout 默认 30s，上限 120s。
export function sendCommand(action: string, payload: Record<string, any>, timeoutMs?: number): Promise<any> {
  return new Promise((resolve, reject) => {
    if (!phone) { reject(new Error('手机未连接（pocket phone offline）')); return; }
    const id = randomUUID();
    const ms = Math.min(Math.max(timeoutMs || 30000, 1000), 120000);
    const timer = setTimeout(() => { pending.delete(id); reject(new Error('命令超时（timeout）')); }, ms);
    pending.set(id, { resolve, reject, timer });
    try {
      phone.send(JSON.stringify({ id, action, ...payload }));
    } catch (e: any) {
      pending.delete(id);
      clearTimeout(timer);
      reject(new Error(e?.message || 'send failed'));
    }
  });
}

// ── builtin 工具（供 Caelum 用）──
const HTML_CAP = 8000;

export const POCKET_TOOLS = [
  {
    name: 'pocket_status',
    description: "查看 Pocket Browser 是否可用（兔兔手机 App 里的 WKWebView 有没有在线）。用别的 pocket_* 前可以先查。",
    input_schema: { type: 'object' as const, properties: {} },
  },
  {
    name: 'pocket_goto',
    description: "让兔兔手机里的浏览器打开一个网址（用她真机的登录态）。之后可用 pocket_read 读正文、pocket_js 跑脚本。",
    input_schema: {
      type: 'object' as const,
      properties: { url: { type: 'string', description: '要打开的网址，含 https://' } },
      required: ['url'],
    },
  },
  {
    name: 'pocket_read',
    description: "读取兔兔手机浏览器当前页面的可见正文（innerText，已截断）。想知道页面上写了啥时用。",
    input_schema: { type: 'object' as const, properties: {} },
  },
  {
    name: 'pocket_js',
    description: "在兔兔手机浏览器的当前页面执行一段 JavaScript，返回结果。用于提取数据、点按钮、填表单等。谨慎使用。",
    input_schema: {
      type: 'object' as const,
      properties: { code: { type: 'string', description: '一段 JS 表达式或语句，结果会被返回' } },
      required: ['code'],
    },
  },
];

function clip(s: string): string {
  return s.length > HTML_CAP ? s.slice(0, HTML_CAP) + `\n…（已截断，共 ${s.length} 字）` : s;
}

export async function callPocketTool(name: string, input: any): Promise<string | null> {
  if (name === 'pocket_status') {
    return phone
      ? `Pocket Browser 在线（最近活跃 ${Math.round((Date.now() - lastSeen) / 1000)}s 前）。`
      : 'Pocket Browser 离线：兔兔手机 App 没连上，或她没开这个功能。';
  }
  if (name === 'pocket_goto') {
    try {
      await sendCommand('goto', { url: String(input?.url || '') }, 20000);
      return `已在兔兔手机上打开：${input?.url}`;
    } catch (e: any) { return 'pocket_goto 失败：' + e.message; }
  }
  if (name === 'pocket_read') {
    try {
      const r = await sendCommand('js', { code: 'document.body ? document.body.innerText : ""' }, 20000);
      const text = typeof r === 'string' ? r : JSON.stringify(r);
      return text.trim() ? clip(text) : '（页面暂无可见文本，可能还在加载或是空白页）';
    } catch (e: any) { return 'pocket_read 失败：' + e.message; }
  }
  if (name === 'pocket_js') {
    try {
      const r = await sendCommand('js', { code: String(input?.code || '') }, 30000);
      const out = typeof r === 'string' ? r : JSON.stringify(r);
      return out === undefined || out === null || out === '' ? '（执行完成，无返回值）' : clip(String(out));
    } catch (e: any) { return 'pocket_js 失败：' + e.message; }
  }
  return null;
}
