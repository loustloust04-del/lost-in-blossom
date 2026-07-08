// 网关 Admin 层（App 内「网关控制台」Phase 2 后端）。
// 零侵入挂载：不改 app.ts —— 本文件把原 app 的 fetch 包一层，/api/admin/* 走
// admin 路由，其余原样透传。构建入口从 src/app.ts 换成 src/admin.ts
// （bun build src/admin.ts --outfile dist/app.js，tmux 运行命令不变）。
import { Hono } from 'hono';
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import appExport from './app';
import { auth } from './middleware/auth';
import { config } from './config';
import { supabase } from './db/supabase';
import { getMcpServerUrls, setMcpServers, probeMcpServer } from './tools/mcp-client';
import { searchWeb } from './tools/websearch';
import { listTodos, addTodo, toggleTodo, deleteTodo, clearDone } from './todos';

// ============ 通道 key 运行时覆盖（持久化 + 热生效） ============
// key 原本只来自启动时 Bun.env；admin 改 key 时写 overrides 文件并直接改 config
// 对象属性（各 provider 每次请求都读 config.xxxKey → 无需重启即生效）。
const OVERRIDES_PATH = new URL('../data/config-overrides.json', import.meta.url).pathname;

const CHANNEL_KEYS: Record<string, string> = {
  'deepseek': 'deepseekKey',
  'openrouter': 'openrouterKey',
  'anthropic': 'anthropicKey',
  'tree-chat': 'treeChatKey',
  'tree-api': 'treeApiKey',
  'tree-aws': 'treeAwsKey',
  'relay': 'relayKey',
  'gua': 'guaKey',
};
const FIELD_ENV: Record<string, string> = {
  deepseekKey: 'DEEPSEEK_API_KEY',
  openrouterKey: 'OPENROUTER_API_KEY',
  anthropicKey: 'ANTHROPIC_API_KEY',
  treeChatKey: 'TREE_CHAT_KEY',
  treeApiKey: 'TREE_API_KEY',
  treeAwsKey: 'TREE_AWS_KEY',
  relayKey: 'RELAY_API_KEY',
  guaKey: 'GUA_API_KEY',
};

function loadOverrides(): Record<string, string> {
  try {
    if (!existsSync(OVERRIDES_PATH)) return {};
    return JSON.parse(readFileSync(OVERRIDES_PATH, 'utf8'));
  } catch { return {}; }
}
function saveOverrides(o: Record<string, string>) {
  try {
    mkdirSync(dirname(OVERRIDES_PATH), { recursive: true });
    writeFileSync(OVERRIDES_PATH, JSON.stringify(o, null, 2));
  } catch (e: any) {
    console.error('[admin] save overrides failed:', e?.message);
  }
}
// 启动时应用覆盖
{
  const o = loadOverrides();
  let applied = 0;
  for (const [field, val] of Object.entries(o)) {
    if (field in config && typeof val === 'string') {
      (config as any)[field] = val;
      applied++;
    }
  }
  if (applied) console.log(`[admin] applied ${applied} config override(s)`);
}

function mask(k: string): string {
  if (!k) return '';
  if (k.length <= 10) return k.slice(0, 2) + '…';
  return k.slice(0, 6) + '…' + k.slice(-4);
}

// ============ crontab 读写 ============
async function readCrontab(): Promise<string[]> {
  const p = Bun.spawn(['crontab', '-l'], { stdout: 'pipe', stderr: 'pipe' });
  const out = await new Response(p.stdout).text();
  await p.exited;
  return out.replace(/\n$/, '').split('\n');
}
async function writeCrontab(lines: string[]): Promise<boolean> {
  const text = lines.join('\n') + '\n';
  const p = Bun.spawn(['crontab', '-'], { stdin: 'pipe', stderr: 'pipe' });
  p.stdin.write(text);
  await p.stdin.end();
  const code = await p.exited;
  return code === 0;
}

// ============ admin 路由 ============
const admin = new Hono().basePath('/api/admin');
admin.use('*', auth);

// ---- 记忆管理 ----
admin.delete('/memories/:id', async (c) => {
  const id = c.req.param('id');
  const { error } = await supabase.from('memories').delete().eq('id', id);
  if (error) return c.json({ ok: false, error: error.message }, 500);
  console.log(`[admin] memory deleted: ${id}`);
  return c.json({ ok: true });
});

admin.post('/memories/:id/pin', async (c) => {
  const id = c.req.param('id');
  let body: any = {}; try { body = await c.req.json(); } catch {}
  const pinned = body?.pinned === true;
  const { error } = await supabase.from('memories').update({ is_pinned: pinned }).eq('id', id);
  if (error) return c.json({ ok: false, error: error.message }, 500);
  return c.json({ ok: true, pinned });
});

admin.patch('/memories/:id', async (c) => {
  const id = c.req.param('id');
  let body: any = {}; try { body = await c.req.json(); } catch {}
  const patch: any = {};
  if (typeof body.content === 'string' && body.content.trim()) patch.content = body.content.trim();
  if (typeof body.category === 'string' && body.category) patch.category = body.category;
  if (typeof body.tier === 'number' && body.tier >= 1 && body.tier <= 4) patch.tier = Math.round(body.tier);
  if (!Object.keys(patch).length) return c.json({ ok: false, error: 'empty patch' }, 400);
  patch.updated_at = new Date().toISOString();
  const { error } = await supabase.from('memories').update(patch).eq('id', id);
  if (error) return c.json({ ok: false, error: error.message }, 500);
  return c.json({ ok: true });
});

// ---- 通道 key 管理 ----
admin.get('/channels', (c) => {
  const overrides = loadOverrides();
  const channels = Object.entries(CHANNEL_KEYS).map(([name, field]) => ({
    name,
    configured: !!(config as any)[field],
    masked: mask((config as any)[field] || ''),
    overridden: field in overrides,
  }));
  return c.json({ channels });
});

admin.put('/channels/:name/key', async (c) => {
  const name = c.req.param('name');
  const field = CHANNEL_KEYS[name];
  if (!field) return c.json({ ok: false, error: 'unknown channel' }, 404);
  let body: any = {}; try { body = await c.req.json(); } catch {}
  const key = typeof body?.key === 'string' ? body.key.trim() : '';
  if (!key) return c.json({ ok: false, error: 'empty key' }, 400);
  (config as any)[field] = key;
  const o = loadOverrides(); o[field] = key; saveOverrides(o);
  console.log(`[admin] channel key updated: ${name} → ${mask(key)}`);
  return c.json({ ok: true, masked: mask(key) });
});

// 清除覆盖，回落到启动时的 env 值
admin.delete('/channels/:name/key', async (c) => {
  const name = c.req.param('name');
  const field = CHANNEL_KEYS[name];
  if (!field) return c.json({ ok: false, error: 'unknown channel' }, 404);
  const o = loadOverrides();
  delete o[field];
  saveOverrides(o);
  (config as any)[field] = Bun.env[FIELD_ENV[field]] || '';
  console.log(`[admin] channel key override cleared: ${name}`);
  return c.json({ ok: true, configured: !!(config as any)[field], masked: mask((config as any)[field] || '') });
});

// ---- 定时任务（VPS crontab） ----
admin.get('/cron', async (c) => {
  const lines = await readCrontab();
  const jobs = lines
    .map((line, idx) => ({ idx, line, enabled: !line.trim().startsWith('#') }))
    .filter((j) => j.line.trim().length > 0);
  return c.json({ jobs });
});

// 开关一条任务（注释/解注释）。body 必须带当前 line 原文防并发漂移误改。
admin.post('/cron/toggle', async (c) => {
  let body: any = {}; try { body = await c.req.json(); } catch {}
  const idx = Number(body?.idx);
  const expect = typeof body?.line === 'string' ? body.line : null;
  const enabled = body?.enabled === true;
  const lines = await readCrontab();
  if (!Number.isInteger(idx) || idx < 0 || idx >= lines.length || !lines[idx].trim()) {
    return c.json({ ok: false, error: 'bad idx' }, 400);
  }
  if (expect !== null && lines[idx] !== expect) {
    return c.json({ ok: false, error: 'line changed, refresh first' }, 409);
  }
  if (enabled) {
    lines[idx] = lines[idx].replace(/^(\s*)#\s?/, '$1');
  } else if (!lines[idx].trim().startsWith('#')) {
    lines[idx] = '# ' + lines[idx];
  }
  const ok = await writeCrontab(lines);
  console.log(`[admin] cron toggle idx=${idx} enabled=${enabled} ok=${ok}`);
  return c.json({ ok });
});

admin.post('/cron/add', async (c) => {
  let body: any = {}; try { body = await c.req.json(); } catch {}
  const line = typeof body?.line === 'string' ? body.line.trim() : '';
  if (!line) return c.json({ ok: false, error: 'empty line' }, 400);
  const lines = await readCrontab();
  lines.push(line);
  const ok = await writeCrontab(lines);
  console.log(`[admin] cron add: ${line} ok=${ok}`);
  return c.json({ ok });
});

// 删除一条任务。body 必须带当前 line 原文防误删。
admin.post('/cron/delete', async (c) => {
  let body: any = {}; try { body = await c.req.json(); } catch {}
  const idx = Number(body?.idx);
  const expect = typeof body?.line === 'string' ? body.line : null;
  const lines = await readCrontab();
  if (!Number.isInteger(idx) || idx < 0 || idx >= lines.length || !lines[idx].trim()) {
    return c.json({ ok: false, error: 'bad idx' }, 400);
  }
  if (expect === null || lines[idx] !== expect) {
    return c.json({ ok: false, error: 'line mismatch, refresh first' }, 409);
  }
  lines.splice(idx, 1);
  const ok = await writeCrontab(lines);
  console.log(`[admin] cron delete idx=${idx} ok=${ok}`);
  return c.json({ ok });
});

// ---- MCP 服务器管理 ----
// 列表来源：data/mcp-servers.json（admin 接管后）；文件不存在时从 MCP_SERVERS env 派生。
// 任何增删都会物化到文件并 setMcpServers 热生效（清工具缓存+会话）。
const MCP_SERVERS_PATH = new URL('../data/mcp-servers.json', import.meta.url).pathname;

type McpServerEntry = { name: string; url: string };

function deriveName(url: string): string {
  try {
    const u = new URL(url);
    return u.port ? `${u.hostname}:${u.port}` : u.hostname;
  } catch { return url; }
}

function loadMcpServerFile(): McpServerEntry[] | null {
  try {
    if (!existsSync(MCP_SERVERS_PATH)) return null;
    const arr = JSON.parse(readFileSync(MCP_SERVERS_PATH, 'utf8'));
    if (!Array.isArray(arr)) return null;
    return arr.filter((e: any) => typeof e?.url === 'string' && e.url)
              .map((e: any) => ({ name: String(e.name || deriveName(e.url)), url: String(e.url) }));
  } catch { return null; }
}

function currentMcpServers(): McpServerEntry[] {
  const file = loadMcpServerFile();
  if (file) return file;
  return getMcpServerUrls().map((url) => ({ name: deriveName(url), url }));
}

function saveMcpServers(list: McpServerEntry[]) {
  mkdirSync(dirname(MCP_SERVERS_PATH), { recursive: true });
  writeFileSync(MCP_SERVERS_PATH, JSON.stringify(list, null, 2));
  setMcpServers(list.map((e) => e.url));
  console.log(`[admin] mcp servers updated: ${list.map((e) => e.name).join(', ') || '(empty)'}`);
}

// 启动时：文件存在则接管
{
  const file = loadMcpServerFile();
  if (file) {
    setMcpServers(file.map((e) => e.url));
    console.log(`[admin] mcp servers loaded from file: ${file.length}`);
  }
}

// 列表 + 逐台探活（并行）
admin.get('/mcp/servers', async (c) => {
  const list = currentMcpServers();
  const probes = await Promise.all(list.map((e) => probeMcpServer(e.url)));
  const servers = list.map((e, i) => ({ ...e, ...probes[i] }));
  return c.json({ servers, managed: loadMcpServerFile() !== null });
});

// 添加：先探活，探不通默认拒绝（body.force=true 强行加）
admin.post('/mcp/servers', async (c) => {
  let body: any = {}; try { body = await c.req.json(); } catch {}
  const url = typeof body?.url === 'string' ? body.url.trim() : '';
  if (!url || !/^https?:\/\//.test(url)) return c.json({ ok: false, error: 'bad url' }, 400);
  const name = (typeof body?.name === 'string' && body.name.trim()) ? body.name.trim() : deriveName(url);
  const list = currentMcpServers();
  if (list.some((e) => e.url === url)) return c.json({ ok: false, error: 'url exists' }, 409);
  if (list.some((e) => e.name === name)) return c.json({ ok: false, error: 'name exists' }, 409);
  const probe = await probeMcpServer(url);
  if (!probe.ok && body?.force !== true) {
    return c.json({ ok: false, error: `探活失败：${probe.error || 'unreachable'}（可 force）`, probe }, 422);
  }
  list.push({ name, url });
  saveMcpServers(list);
  return c.json({ ok: true, probe });
});

// 删除（按 name）
admin.delete('/mcp/servers/:name', async (c) => {
  const name = decodeURIComponent(c.req.param('name'));
  const list = currentMcpServers();
  const idx = list.findIndex((e) => e.name === name);
  if (idx < 0) return c.json({ ok: false, error: 'not found' }, 404);
  list.splice(idx, 1);
  saveMcpServers(list);
  return c.json({ ok: true });
});

// 手动刷新工具缓存（改动即刻反映到 /api/mcp/tools）
admin.post('/mcp/refresh', async (c) => {
  setMcpServers(currentMcpServers().map((e) => e.url));
  return c.json({ ok: true });
});

// ============ 提醒规则（P1-3：低电量/地点变化 → APNs）============
// 规则文件被 cc-bridge/alert-rules.ts（cron 每 15 分钟）读取；这里只管读写配置。
const ALERT_RULES_PATH = new URL('../data/alert-rules.json', import.meta.url).pathname;
const ALERT_RULES_DEFAULT = {
  lowBattery: { enabled: true, threshold: 20, cooldownMin: 120 },
  placeChange: { enabled: true, cooldownMin: 30 },
  quietHours: { start: 1, end: 9 },
};

admin.get('/alert-rules', (c) => {
  try {
    return c.json({ ...ALERT_RULES_DEFAULT, ...JSON.parse(readFileSync(ALERT_RULES_PATH, 'utf-8')) });
  } catch {
    return c.json(ALERT_RULES_DEFAULT);
  }
});

admin.put('/alert-rules', async (c) => {
  let body: any = {};
  try { body = await c.req.json(); } catch { return c.json({ error: 'invalid JSON' }, 400); }
  const merged = {
    lowBattery: { ...ALERT_RULES_DEFAULT.lowBattery, ...(body.lowBattery ?? {}) },
    placeChange: { ...ALERT_RULES_DEFAULT.placeChange, ...(body.placeChange ?? {}) },
    quietHours: { ...ALERT_RULES_DEFAULT.quietHours, ...(body.quietHours ?? {}) },
  };
  writeFileSync(ALERT_RULES_PATH, JSON.stringify(merged, null, 2));
  return c.json({ ok: true, rules: merged });
});

// ============ 联网搜索端点（App 客户端 search_web 走这里）============
// 网关侧真 Chrome 搜索，免 key。App 的「网关搜索」provider GET /api/search?q=...&count=
const search = new Hono().basePath('/api/search');
search.use('*', auth);
search.get('/', async (c) => {
  const q = (c.req.query('q') || '').trim();
  const count = Math.min(Math.max(parseInt(c.req.query('count') || '8', 10) || 8, 1), 15);
  if (!q) return c.json({ error: 'missing q' }, 400);
  try {
    const items = await searchWeb(q, count);
    return c.json({ query: q, items });
  } catch (e: any) {
    return c.json({ error: e?.message || 'search failed' }, 502);
  }
});

// ============ 待办（App 控制台读写；CC/API 也经 builtin 工具写）============
const todos = new Hono().basePath('/api/todos');
todos.use('*', auth);
todos.get('/', async (c) => c.json({ items: await listTodos() }));
todos.post('/', async (c) => {
  let b: any = {}; try { b = await c.req.json(); } catch {}
  const it = await addTodo(String(b?.text || ''), String(b?.source || 'bunny'));
  return it ? c.json({ ok: true, item: it }) : c.json({ error: 'empty text' }, 400);
});
todos.post('/:id/toggle', async (c) => {
  const ok = await toggleTodo(c.req.param('id'));
  return ok ? c.json({ ok: true }) : c.json({ error: 'not found' }, 404);
});
todos.delete('/done', async (c) => c.json({ ok: true, removed: await clearDone() }));
todos.delete('/:id', async (c) => {
  const ok = await deleteTodo(c.req.param('id'));
  return ok ? c.json({ ok: true }) : c.json({ error: 'not found' }, 404);
});

// ============ 导出：包一层 fetch ============
export default {
  ...appExport,
  fetch: (req: Request, env?: any, ctx?: any) => {
    const url = new URL(req.url);
    if (url.pathname.startsWith('/api/admin/')) {
      return admin.fetch(req, env, ctx);
    }
    if (url.pathname === '/api/search' || url.pathname.startsWith('/api/search/')) {
      return search.fetch(req, env, ctx);
    }
    if (url.pathname === '/api/todos' || url.pathname.startsWith('/api/todos/')) {
      return todos.fetch(req, env, ctx);
    }
    return (appExport as any).fetch(req, env, ctx);
  },
};
