const express = require('express');
const { Client } = require('@modelcontextprotocol/sdk/client/index.js');
const { StreamableHTTPClientTransport } = require('@modelcontextprotocol/sdk/client/streamableHttp.js');

const app = express();
app.use(express.json());

const PORT = process.env.MCP_BRIDGE_PORT || 3200;
const BRIDGE_TOKEN = process.env.MCP_BRIDGE_TOKEN || 'bunny-mcp-2026';

const connections = new Map();

function auth(req, res, next) {
  const token = req.headers['authorization']?.replace('Bearer ', '');
  if (token !== BRIDGE_TOKEN) return res.status(401).json({ error: 'unauthorized' });
  next();
}

async function connectMCP(name, url) {
  try {
    const transport = new StreamableHTTPClientTransport(new URL(url));
    const client = new Client({ name: `bridge-${name}`, version: '1.0.0' });
    await client.connect(transport);
    const { tools } = await client.listTools();
    connections.set(name, { client, tools, url });
    console.log(`[mcp-bridge] Connected: ${name} @ ${url} (${tools.length} tools)`);
    return tools;
  } catch (e) {
    console.error(`[mcp-bridge] Failed: ${name} — ${e.message}`);
    throw e;
  }
}

app.get('/mcp/tools', auth, (req, res) => {
  const allTools = [];
  for (const [name, conn] of connections) {
    for (const tool of conn.tools) {
      allTools.push({
        server: name,
        name: tool.name,
        description: tool.description || '',
        inputSchema: tool.inputSchema || {}
      });
    }
  }
  res.json({ tools: allTools });
});

app.post('/mcp/call', auth, async (req, res) => {
  const { server, tool, arguments: args } = req.body;
  const conn = connections.get(server);
  if (!conn) return res.status(404).json({ error: `server '${server}' not connected` });
  try {
    const result = await conn.client.callTool({ name: tool, arguments: args || {} });
    res.json({ result: result.content });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.post('/mcp/connect', auth, async (req, res) => {
  const { name, url } = req.body;
  if (!name || !url) return res.status(400).json({ error: 'name and url required' });
  try {
    const tools = await connectMCP(name, url);
    res.json({ connected: name, tools: tools.length });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.get('/mcp/status', auth, (req, res) => {
  const status = [];
  for (const [name, conn] of connections) {
    status.push({ name, url: conn.url, tools: conn.tools.length });
  }
  res.json({ connections: status });
});

app.listen(PORT, '0.0.0.0', async () => {
  console.log(`[mcp-bridge] REST API on port ${PORT}`);
  const defaults = process.env.MCP_DEFAULT_SERVERS;
  if (defaults) {
    for (const pair of defaults.split(',')) {
      const [name, url] = pair.split('=');
      if (name && url) {
        try { await connectMCP(name.trim(), url.trim()); }
        catch (e) { console.error(`[mcp-bridge] Auto-connect ${name} failed: ${e.message}`); }
      }
    }
  }
});
