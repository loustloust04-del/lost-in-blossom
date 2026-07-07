// MCP streamable-http 客户端 — 支持 session ID + SSE 响应解析
// MCP_SERVERS 环境变量：逗号或换行分隔的端点 URL

interface McpTool { name: string; description: string; input_schema: any; _url: string; _sid: string; }

let cache: McpTool[] | null = null;
let cacheTime = 0;
const sessions: Map<string, string> = new Map(); // url → session-id

const MCP_HEADERS = {
  'Content-Type': 'application/json',
  'Accept': 'application/json, text/event-stream',
};

// 从 SSE 响应中提取 JSON data
async function parseSseResponse(res: Response): Promise<any> {
  const text = await res.text();
  // 尝试直接 JSON 解析
  try { return JSON.parse(text); } catch {}
  // SSE 格式：提取 data: 行
  for (const line of text.split('\n')) {
    if (line.startsWith('data: ')) {
      try { return JSON.parse(line.slice(6)); } catch {}
    }
  }
  return null;
}

async function mcpRequest(url: string, body: any): Promise<{ data: any; sid: string }> {
  const sid = sessions.get(url) || '';
  const headers: Record<string, string> = { ...MCP_HEADERS };
  if (sid) headers['mcp-session-id'] = sid;

  const res = await fetch(url, {
    method: 'POST', headers,
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(15000),
  });

  const newSid = res.headers.get('mcp-session-id') || sid;
  if (newSid) sessions.set(url, newSid);

  const data = await parseSseResponse(res);
  return { data, sid: newSid };
}

async function initSession(url: string): Promise<string> {
  const { sid } = await mcpRequest(url, {
    jsonrpc: '2.0', id: 0, method: 'initialize',
    params: { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'blossom-gateway', version: '1.0' } }
  });

  // Send initialized notification (with session ID)
  const headers: Record<string, string> = { ...MCP_HEADERS };
  if (sid) headers['mcp-session-id'] = sid;
  await fetch(url, {
    method: 'POST', headers,
    body: JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized', params: {} }),
    signal: AbortSignal.timeout(5000),
  }).catch(() => {});

  return sid;
}

// [admin] 服务器列表动态化：admin 层接管后走 override（data/mcp-servers.json），
// 否则维持 MCP_SERVERS 环境变量。setMcpServers 同时清缓存+会话，热生效。
let serverOverride: string[] | null = null;

export function getMcpServerUrls(): string[] {
  if (serverOverride) return serverOverride;
  return (process.env.MCP_SERVERS || '').split(/[,\n]/).map(u => u.trim()).filter(Boolean);
}

export function setMcpServers(urls: string[]) {
  serverOverride = urls;
  cache = null;
  cacheTime = 0;
  sessions.clear();
}

/// 探活：initialize + tools/list，返回可用性/工具数/耗时
export async function probeMcpServer(url: string): Promise<{ ok: boolean; toolCount: number; ms: number; error?: string }> {
  const t0 = Date.now();
  try {
    await initSession(url);
    const { data } = await mcpRequest(url, { jsonrpc: '2.0', id: 1, method: 'tools/list', params: {} });
    const list = data?.result?.tools;
    if (!Array.isArray(list)) {
      return { ok: false, toolCount: 0, ms: Date.now() - t0, error: 'no tools/list result' };
    }
    return { ok: true, toolCount: list.length, ms: Date.now() - t0 };
  } catch (e: any) {
    return { ok: false, toolCount: 0, ms: Date.now() - t0, error: e?.message || String(e) };
  }
}

export async function getMcpTools(): Promise<McpTool[]> {
  if (cache && Date.now() - cacheTime < 300_000) return cache;
  const urls = getMcpServerUrls();
  if (!urls.length) { cache = []; cacheTime = Date.now(); return []; }

  const tools: McpTool[] = [];
  for (const url of urls) {
    try {
      const sid = await initSession(url);
      const { data } = await mcpRequest(url, { jsonrpc: '2.0', id: 1, method: 'tools/list', params: {} });
      for (const t of (data?.result?.tools || [])) {
        tools.push({
          name: t.name,
          description: t.description || '',
          input_schema: t.inputSchema || { type: 'object', properties: {} },
          _url: url, _sid: sid,
        });
      }
      console.log(`[mcp] ${url}: ${data?.result?.tools?.length || 0} tools`);
    } catch (e: any) {
      console.warn('[mcp] connect failed:', url, e?.message);
    }
  }
  cache = tools; cacheTime = Date.now();
  return tools;
}

export async function callMcpTool(name: string, input: any, tools: McpTool[]): Promise<string> {
  const tool = tools.find(t => t.name === name);
  if (!tool) return 'Tool not found: ' + name;
  try {
    const { data } = await mcpRequest(tool._url, {
      jsonrpc: '2.0', id: Date.now(), method: 'tools/call',
      params: { name, arguments: input },
    });
    if (data?.error) return 'Error: ' + (data.error.message || JSON.stringify(data.error));
    return (data?.result?.content || []).map((c: any) => c.text || JSON.stringify(c)).join('\n');
  } catch (e: any) {
    return 'MCP call failed: ' + (e?.message || String(e));
  }
}
