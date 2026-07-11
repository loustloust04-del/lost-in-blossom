// IMAP 收信 — 复用 SMTP 的应用专用密码（Gmail 应用专用密码 SMTP/IMAP 通用），不走 OAuth。
// 供 gmail_inbox / gmail_read / gmail_search 在 OAuth 失效时收信。
import { ImapFlow } from 'imapflow';
import { simpleParser } from 'mailparser';

function creds() {
  return {
    user: process.env.IMAP_USER || process.env.SMTP_USER || '',
    pass: process.env.IMAP_PASS || process.env.SMTP_PASS || '',
    host: process.env.IMAP_HOST || 'imap.gmail.com',
    port: Number(process.env.IMAP_PORT || 993),
  };
}

/// IMAP 是否配好（有 user+pass 就行，默认复用 SMTP 那套）
export function imapConfigured(): boolean {
  const c = creds();
  return !!(c.user && c.pass);
}

async function withClient<T>(fn: (c: ImapFlow) => Promise<T>): Promise<T> {
  const c = creds();
  const client = new ImapFlow({ host: c.host, port: c.port, secure: true, auth: { user: c.user, pass: c.pass }, logger: false });
  await client.connect();
  try { return await fn(client); }
  finally { try { await client.logout(); } catch {} }
}

function fmtAddr(a: any): string {
  const arr = a?.value || a;
  if (Array.isArray(arr)) return arr.map((x: any) => x.name ? `${x.name} <${x.address}>` : x.address).join(', ');
  return a ? String(a) : '';
}

/// 最近 n 封（只给 From/Subject/Date + UID，快）
export async function imapInbox(n: number): Promise<string> {
  return withClient(async (c) => {
    const box = await c.mailboxOpen('INBOX');
    if (!box.exists) return 'Inbox is empty.';
    const start = Math.max(1, box.exists - n + 1);
    const out: string[] = [];
    for await (const msg of c.fetch(`${start}:*`, { envelope: true, uid: true })) {
      const e: any = msg.envelope || {};
      out.unshift(`[${msg.uid}] ${e.date ? new Date(e.date).toISOString() : ''}\nFrom: ${fmtAddr(e.from)}\nSubject: ${e.subject || '(no subject)'}`);
    }
    return out.join('\n---\n') || 'Inbox is empty.';
  });
}

/// 读一封全文（messageId 传 UID，即 inbox/search 列表里 [] 中的数字）
export async function imapRead(uid: string): Promise<string> {
  return withClient(async (c) => {
    await c.mailboxOpen('INBOX');
    const msg: any = await c.fetchOne(String(uid), { source: true }, { uid: true });
    if (!msg || !msg.source) return 'Message not found: ' + uid;
    const p = await simpleParser(msg.source);
    const body = (p.text || (p.html ? String(p.html).replace(/<[^>]+>/g, ' ') : '') || '(no body)').slice(0, 4000);
    return `From: ${p.from?.text || ''}\nTo: ${p.to?.text || ''}\nSubject: ${p.subject || ''}\nDate: ${p.date ? p.date.toISOString() : ''}\n\n${body}`;
  });
}

/// 搜索 — 用 Gmail X-GM-RAW，保留 from:/subject: 等完整语法
export async function imapSearch(query: string, n: number): Promise<string> {
  return withClient(async (c) => {
    await c.mailboxOpen('INBOX');
    const uids = await c.search({ gmailRaw: query } as any, { uid: true });
    if (!uids || !uids.length) return 'No results for: ' + query;
    const pick = uids.slice(-n);
    const out: string[] = [];
    for await (const msg of c.fetch(pick, { envelope: true, uid: true }, { uid: true })) {
      const e: any = msg.envelope || {};
      out.unshift(`[${msg.uid}] ${e.date ? new Date(e.date).toISOString() : ''}\nFrom: ${fmtAddr(e.from)}\nSubject: ${e.subject || '(no subject)'}`);
    }
    return out.join('\n---\n') || 'No results for: ' + query;
  });
}
