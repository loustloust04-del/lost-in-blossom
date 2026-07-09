// 网关侧联网搜索：驱动 VPS 上的真 Chrome（playwright + 系统 Google Chrome）跑搜索。
// 免第三方 key、免费；真浏览器指纹 + JS 渲染骗过反爬墙（Bing/DDG 直抓、Jina 免费额度
// 在 VPS IP 上全被封，实测唯有真完整浏览器能出结果）。
// 两个消费方：
//   1) App 客户端 search_web → /api/search（admin.ts 暴露）→ 这里
//   2) CC / 网关原生模型 → builtin search_web（builtin.ts callBuiltinTool）→ 这里
import { chromium, type Browser, type Page } from 'playwright-core';

export interface SearchItem { title: string; url: string; snippet: string; }

const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36';
const LAUNCH_ARGS = ['--no-sandbox', '--disable-blink-features=AutomationControlled', '--disable-dev-shm-usage'];

// 常驻浏览器：避免每次搜索冷启动 chrome（~1-2s + 内存尖峰）。死了自动重启。
let browserP: Promise<Browser> | null = null;
async function getBrowser(): Promise<Browser> {
  if (browserP) {
    const b = await browserP.catch(() => null);
    if (b && b.isConnected()) return b;
    browserP = null;
  }
  browserP = chromium
    .launch({ channel: 'chrome', headless: true, args: LAUNCH_ARGS })
    .catch(() => chromium.launch({ headless: true, args: LAUNCH_ARGS }));
  return browserP;
}

async function googleSearch(page: Page, q: string, count: number): Promise<SearchItem[]> {
  await page.goto('https://www.google.com/search?hl=zh-CN&num=' + (count + 3) + '&q=' + encodeURIComponent(q),
    { waitUntil: 'domcontentloaded', timeout: 20000 });
  await page.waitForTimeout(1200);
  return page.evaluate(() => {
    const out: any[] = [];
    const seen = new Set<string>();
    document.querySelectorAll('a').forEach((a: any) => {
      const h3 = a.querySelector('h3');
      if (!h3) return;
      const url: string = a.href || '';
      if (!url.startsWith('http')) return;
      if (/(^https?:\/\/[^/]*google\.)|gstatic|googleusercontent|webcache|\/search\?/.test(url)) return;
      if (seen.has(url)) return;
      seen.add(url);
      let cont = a.closest('div.g') || a.parentElement?.parentElement;
      let snip = '';
      if (cont) snip = (cont.innerText || '').replace(h3.innerText, '').trim().replace(/\s+/g, ' ').slice(0, 200);
      out.push({ title: h3.innerText.trim(), url, snippet: snip });
    });
    return out;
  });
}

async function ddgSearch(page: Page, q: string, count: number): Promise<SearchItem[]> {
  await page.goto('https://html.duckduckgo.com/html/?q=' + encodeURIComponent(q),
    { waitUntil: 'domcontentloaded', timeout: 20000 });
  await page.waitForTimeout(1000);
  return page.evaluate(() => {
    const out: any[] = [];
    const seen = new Set<string>();
    document.querySelectorAll('.result').forEach((r: any) => {
      const a = r.querySelector('.result__a');
      if (!a) return;
      let url: string = a.href || '';
      const m = url.match(/uddg=([^&]+)/);
      if (m) { try { url = decodeURIComponent(m[1]); } catch {} }
      if (!url.startsWith('http') || seen.has(url)) return;
      seen.add(url);
      out.push({ title: (a.innerText || '').trim(), url, snippet: (r.querySelector('.result__snippet')?.innerText || '').replace(/\s+/g, ' ').trim().slice(0, 200) });
    });
    return out;
  });
}

async function bingSearch(page: Page, q: string, count: number): Promise<SearchItem[]> {
  await page.goto('https://www.bing.com/search?q=' + encodeURIComponent(q),
    { waitUntil: 'domcontentloaded', timeout: 20000 });
  await page.waitForTimeout(1000);
  return page.evaluate(() => {
    const out: any[] = [];
    document.querySelectorAll('li.b_algo').forEach((e: any) => {
      const a = e.querySelector('h2 a');
      if (!a) return;
      out.push({ title: (e.querySelector('h2')?.innerText || '').trim(), url: a.href || '', snippet: (e.querySelector('.b_caption p, .b_algoSlug')?.innerText || '').replace(/\s+/g, ' ').trim().slice(0, 200) });
    });
    return out;
  });
}

// 简单并发闸：避免同一时刻开太多 page 打爆内存（VPS 上还跑着 hub / browser-mcp）。
let inflight = 0;
const MAX_INFLIGHT = 3;

export async function searchWeb(query: string, count = 8): Promise<SearchItem[]> {
  const q = (query || '').trim();
  if (!q) return [];
  while (inflight >= MAX_INFLIGHT) { await new Promise((r) => setTimeout(r, 200)); }
  inflight++;
  const browser = await getBrowser();
  const ctx = await browser.newContext({ userAgent: UA, locale: 'zh-CN' });
  await ctx.addInitScript(() => {
    Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
  });
  const page = await ctx.newPage();
  try {
    let items = await googleSearch(page, q, count).catch(() => [] as SearchItem[]);
    if (items.length === 0) items = await ddgSearch(page, q, count).catch(() => [] as SearchItem[]);
    if (items.length === 0) items = await bingSearch(page, q, count).catch(() => [] as SearchItem[]);
    return items.slice(0, count);
  } finally {
    await ctx.close().catch(() => {});
    inflight--;
  }
}

// 网关侧「抓单页正文」——browse_url 复用同一常驻 Chrome（自动带 chrome-proxy 住宅 IP），
// 绕开 iOS WKWebView 的离屏/前后台/低电量坑。goto 目标页 → 去噪 → 抽正文文本。
const BROWSE_MAX = 8000; // 与 App InternalBrowser markdownLimit 对齐（约 2000 token）

export interface BrowsedPage { title: string; url: string; text: string; length: number; truncated: boolean; }

export async function browsePage(rawUrl: string): Promise<BrowsedPage> {
  const target = (rawUrl || '').trim();
  if (!/^https?:\/\//i.test(target)) throw new Error('browse_url 需要 http(s) 链接');
  while (inflight >= MAX_INFLIGHT) { await new Promise((r) => setTimeout(r, 200)); }
  inflight++;
  const browser = await getBrowser();
  const ctx = await browser.newContext({ userAgent: UA, locale: 'zh-CN' });
  await ctx.addInitScript(() => {
    Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
  });
  const page = await ctx.newPage();
  try {
    await page.goto(target, { waitUntil: 'domcontentloaded', timeout: 20000 });
    await page.waitForTimeout(800);
    const res = await page.evaluate(() => {
      ['script', 'style', 'noscript', 'nav', 'header', 'footer', 'aside', 'iframe', 'svg', 'form']
        .forEach((sel) => document.querySelectorAll(sel).forEach((e) => e.remove()));
      const main: any = document.querySelector('article, main, [role="main"]') || document.body;
      const text: string = (main?.innerText || (document.body as any).innerText || '')
        .replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n').trim();
      return { title: document.title || '', text };
    });
    const truncated = res.text.length > BROWSE_MAX;
    const text = truncated
      ? res.text.slice(0, BROWSE_MAX) + '\n\n…（正文截断，原始 ' + res.text.length + ' 字）'
      : res.text;
    return { title: res.title, url: page.url(), text, length: res.text.length, truncated };
  } finally {
    await ctx.close().catch(() => {});
    inflight--;
  }
}

// 常驻浏览器会挡住 bun 进程退出（systemd stop 卡到 90s 超时强杀）——收到停止信号先关浏览器。
for (const sig of ['SIGTERM', 'SIGINT'] as const) {
  process.on(sig, () => {
    const p = browserP;
    browserP = null;
    Promise.resolve(p ? p.then((b) => b.close()) : null)
      .catch(() => {})
      .finally(() => process.exit(0));
  });
}

export const WEBSEARCH_TOOL = {
  name: 'search_web',
  description: '联网搜索——实时信息（天气/新闻/今天/最近/最新/价格/赛事/股价/汇率/版本号…）或不确定的事实必须先调这个再回答。返回若干条 {title, url, snippet}。绝不要说"我无法联网"。',
  input_schema: {
    type: 'object' as const,
    properties: { query: { type: 'string', description: '搜索关键词' } },
    required: ['query'],
  },
};

// callBuiltinTool 用：返回给模型的文本（JSON 字符串）
export async function callWebSearch(input: any): Promise<string> {
  const query = typeof input?.query === 'string' ? input.query : '';
  if (!query) return JSON.stringify({ error: 'search_web 缺少 query' });
  try {
    const items = await searchWeb(query, 8);
    if (items.length === 0) return JSON.stringify({ query, items: [], note: '没有搜到结果，可换关键词重试' });
    return JSON.stringify({ query, items });
  } catch (e: any) {
    return JSON.stringify({ error: '搜索失败: ' + (e?.message || String(e)) });
  }
}
