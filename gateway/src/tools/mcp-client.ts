// 最小 MCP 客户端 — 内置工具 fall-through 路径。模型调了内置工具不认识的名字才走这里。
// MCP_SERVERS：每行一个 streamable-http 端点 URL。
let cache: any[] | null = null;
let cacheTime = 0;

export async function getMcpTools(): Promise<any[]> {
  if (cache && Date.now() - cacheTime < 300_000) return cache;
  const urls = (process.env.MCP_SERVERS || '').split('\n').map(u => u.trim()).filter(Boolean);
  if (!urls.length) { cache = []; cacheTime = Date.now(); return []; }
  const tools: any[] = [];
  for (const url of urls) {
    try {
      const init = await fetch(url, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ jsonrpc: '2.0', id: 0, method: 'initialize', params: { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'blossom-gateway', version: '1.0' } } }),
        signal: AbortSignal.timeout(8000),
      });
      if (!init.ok || !(init.headers.get('content-type') || '').includes('application/json')) continue;
      await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized', params: {} }), signal: AbortSignal.timeout(8000) });
      const r = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/list', params: {} }), signal: AbortSignal.timeout(8000) });
      const data: any = await r.json();
      for (const t of (data.result?.tools || [])) {
        tools.push({ name: t.name, description: t.description || '', input_schema: t.inputSchema || { type: 'object', properties: {} }, _url: url });
      }
    } catch (e: any) { console.warn('[mcp] connect failed:', url, e?.message); }
  }
  cache = tools; cacheTime = Date.now();
  return tools;
}

export async function callMcpTool(name: string, input: any, tools: any[]): Promise<string> {
  const tool = tools.find(t => t.name === name);
  if (!tool) return 'Tool not found: ' + name;
  try {
    const res = await fetch(tool._url, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ jsonrpc: '2.0', id: Date.now(), method: 'tools/call', params: { name, arguments: input } }),
      signal: AbortSignal.timeout(60_000),
    });
    const data: any = await res.json();
    if (data.error) return 'Error: ' + (data.error.message || JSON.stringify(data.error));
    return (data.result?.content || []).map((c: any) => c.text || JSON.stringify(c)).join('\n');
  } catch (e: any) { return 'MCP call failed: ' + (e?.message || String(e)); }
}
