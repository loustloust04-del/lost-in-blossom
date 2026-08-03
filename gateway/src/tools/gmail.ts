// Gmail API 直连 — 用 OAuth refresh_token 自动刷新 access_token
import { config } from '../config';
import { sendMail, mailerConfigured } from '../mailer';
import { imapInbox, imapRead, imapSearch, imapConfigured } from '../imap-reader';

const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const GMAIL_API = 'https://gmail.googleapis.com/gmail/v1/users/me';

let accessToken = '';
let tokenExpiry = 0;

async function getAccessToken(): Promise<string> {
  if (accessToken && Date.now() < tokenExpiry - 60000) return accessToken;
  const res = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: process.env.GMAIL_CLIENT_ID || '',
      client_secret: process.env.GMAIL_CLIENT_SECRET || '',
      refresh_token: process.env.GMAIL_REFRESH_TOKEN || '',
      grant_type: 'refresh_token',
    }),
  });
  const d: any = await res.json();
  if (!d.access_token) throw new Error('Gmail token refresh failed: ' + JSON.stringify(d));
  accessToken = d.access_token;
  tokenExpiry = Date.now() + (d.expires_in || 3600) * 1000;
  return accessToken;
}

async function gmailFetch(path: string, options?: RequestInit): Promise<any> {
  const token = await getAccessToken();
  const res = await fetch(GMAIL_API + path, {
    ...options,
    headers: { 'Authorization': 'Bearer ' + token, ...(options?.headers || {}) },
  });
  return res.json();
}

// 内置 Gmail 工具定义
export const GMAIL_TOOLS = [
  {
    name: 'gmail_inbox',
    description: '看收件箱最近的邮件：主题、发件人、日期、摘要。',
    input_schema: { type: 'object', properties: { count: { type: 'number', description: 'number of emails (default 5, max 20)' } } },
  },
  {
    name: 'gmail_read',
    description: '按 message ID 读一封邮件的全文。',
    input_schema: { type: 'object', properties: { messageId: { type: 'string', description: 'Gmail message ID' } }, required: ['messageId'] },
  },
  {
    name: 'gmail_send',
    description: '发一封邮件。',
    input_schema: { type: 'object', properties: { to: { type: 'string' }, subject: { type: 'string' }, body: { type: 'string' } }, required: ['to', 'subject', 'body'] },
  },
  {
    name: 'gmail_search',
    description: '用 Gmail 的搜索语法找邮件，比如 from:someone subject:hello。',
    input_schema: { type: 'object', properties: { query: { type: 'string', description: 'Gmail search query' }, count: { type: 'number' } }, required: ['query'] },
  },
];

export async function callGmailTool(name: string, input: any): Promise<string | null> {
  // gmail_send 优先走 SMTP（应用专用密码，不会过期）；SMTP 没配或失败再退回 OAuth。
  if (name === 'gmail_send' && mailerConfigured()) {
    try {
      await sendMail(String(input?.to || ''), String(input?.subject || ''), String(input?.body || ''));
      return `Sent to ${input?.to} (via SMTP)`;
    } catch (e: any) {
      if (!process.env.GMAIL_REFRESH_TOKEN) return 'Send failed (SMTP): ' + (e?.message || String(e));
      // 有 OAuth 就继续往下当退路
    }
  }
  // 收信优先走 IMAP（复用 SMTP 应用专用密码，绕开死掉的 OAuth）；失败且无 OAuth 才报错
  if (imapConfigured()) {
    const imapCatch = (e: any) => process.env.GMAIL_REFRESH_TOKEN ? null : ('IMAP error: ' + (e?.message || String(e)));
    if (name === 'gmail_inbox') { try { return await imapInbox(Math.min(input?.count || 5, 20)); } catch (e) { const r = imapCatch(e); if (r !== null) return r; } }
    if (name === 'gmail_read' && input?.messageId) { try { return await imapRead(String(input.messageId)); } catch (e) { const r = imapCatch(e); if (r !== null) return r; } }
    if (name === 'gmail_search') { try { return await imapSearch(String(input?.query || ''), Math.min(input?.count || 5, 20)); } catch (e) { const r = imapCatch(e); if (r !== null) return r; } }
  }
  if (!process.env.GMAIL_REFRESH_TOKEN) return null;

  try {
    if (name === 'gmail_inbox') {
      const n = Math.min(input?.count || 5, 20);
      const list = await gmailFetch(`/messages?maxResults=${n}&labelIds=INBOX`);
      if (!list.messages?.length) return 'Inbox is empty.';
      const details = [];
      for (const msg of list.messages.slice(0, n)) {
        const m = await gmailFetch(`/messages/${msg.id}?format=metadata&metadataHeaders=From&metadataHeaders=Subject&metadataHeaders=Date`);
        const headers = m.payload?.headers || [];
        const get = (n: string) => headers.find((h: any) => h.name === n)?.value || '';
        details.push(`[${msg.id}] ${get('Date')}\nFrom: ${get('From')}\nSubject: ${get('Subject')}\n${m.snippet || ''}`);
      }
      return details.join('\n---\n');
    }

    if (name === 'gmail_read') {
      const m = await gmailFetch(`/messages/${input.messageId}?format=full`);
      const headers = m.payload?.headers || [];
      const get = (n: string) => headers.find((h: any) => h.name === n)?.value || '';
      let body = '';
      const parts = m.payload?.parts || [m.payload];
      for (const p of parts) {
        if (p?.mimeType === 'text/plain' && p?.body?.data) {
          body += Buffer.from(p.body.data, 'base64url').toString('utf-8');
        }
      }
      if (!body && m.payload?.body?.data) {
        body = Buffer.from(m.payload.body.data, 'base64url').toString('utf-8');
      }
      return `From: ${get('From')}\nTo: ${get('To')}\nSubject: ${get('Subject')}\nDate: ${get('Date')}\n\n${body || m.snippet || '(no body)'}`;
    }

    if (name === 'gmail_send') {
      const raw = Buffer.from(
        `To: ${input.to}\r\nSubject: ${input.subject}\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n${input.body}`
      ).toString('base64url');
      const res = await gmailFetch('/messages/send', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ raw }),
      });
      return res.id ? `Sent! Message ID: ${res.id}` : 'Send failed: ' + JSON.stringify(res);
    }

    if (name === 'gmail_search') {
      const n = Math.min(input?.count || 5, 20);
      const list = await gmailFetch(`/messages?maxResults=${n}&q=${encodeURIComponent(input.query)}`);
      if (!list.messages?.length) return 'No results for: ' + input.query;
      const details = [];
      for (const msg of list.messages.slice(0, n)) {
        const m = await gmailFetch(`/messages/${msg.id}?format=metadata&metadataHeaders=From&metadataHeaders=Subject&metadataHeaders=Date`);
        const headers = m.payload?.headers || [];
        const get = (n: string) => headers.find((h: any) => h.name === n)?.value || '';
        details.push(`[${msg.id}] ${get('Date')}\nFrom: ${get('From')}\nSubject: ${get('Subject')}\n${m.snippet || ''}`);
      }
      return details.join('\n---\n');
    }
  } catch (e: any) {
    return 'Gmail error: ' + (e?.message || String(e));
  }

  return null; // not a gmail tool
}
