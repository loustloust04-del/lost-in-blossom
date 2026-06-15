// Gmail API 直连 — 用 OAuth refresh_token 自动刷新 access_token
import { config } from '../config';

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
    description: 'List recent emails from inbox. Returns subject, sender, date, snippet for each.',
    input_schema: { type: 'object', properties: { count: { type: 'number', description: 'number of emails (default 5, max 20)' } } },
  },
  {
    name: 'gmail_read',
    description: 'Read full content of a specific email by message ID.',
    input_schema: { type: 'object', properties: { messageId: { type: 'string', description: 'Gmail message ID' } }, required: ['messageId'] },
  },
  {
    name: 'gmail_send',
    description: 'Send an email.',
    input_schema: { type: 'object', properties: { to: { type: 'string' }, subject: { type: 'string' }, body: { type: 'string' } }, required: ['to', 'subject', 'body'] },
  },
  {
    name: 'gmail_search',
    description: 'Search emails with Gmail query syntax (e.g. "from:someone subject:hello").',
    input_schema: { type: 'object', properties: { query: { type: 'string', description: 'Gmail search query' }, count: { type: 'number' } }, required: ['query'] },
  },
];

export async function callGmailTool(name: string, input: any): Promise<string | null> {
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
