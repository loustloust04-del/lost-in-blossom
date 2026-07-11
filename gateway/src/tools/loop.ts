import { config } from '../config';
import { buildAnthropicPayload } from '../providers/anthropic-native';
import { BUILTIN_TOOLS, SERVER_MAP, callBuiltinTool } from './builtin';
import { getMcpTools, callMcpTool } from './mcp-client';
import { SCREEN_PEEK_ABILITY } from '../peek';

// 流式 tool loop：把 Anthropic SSE 转成网关统一的 OpenAI chunk 流给客户端，
// 同时本端攒出 content blocks。stop_reason == tool_use 时：内置工具(exec/recall)
// 进程内执行，不认识的名字 fall through 到 MCP，结果塞回对话再发起下一轮。
// 上游优先级：TreeGPT → OR → 直连 Anthropic
function getUpstream(): { url: string; auth: string } {
  if (config.treeChatKey) return { url: 'https://api.treegpt.cc/v1/messages', auth: 'Bearer ' + config.treeChatKey };
  if (config.openrouterKey) return { url: 'https://openrouter.ai/api/v1/messages', auth: 'Bearer ' + config.openrouterKey };
  if (config.anthropicKey) return { url: 'https://api.anthropic.com/v1/messages', auth: config.anthropicKey };
  throw new Error('No upstream API key configured');
}
const ANTHROPIC_VERSION = '2023-06-01';
const MAX_LOOPS = 8;

function mapStop(reason: string | null | undefined): string {
  switch (reason) {
    case 'end_turn': case 'stop_sequence': return 'stop';
    case 'max_tokens': return 'length';
    case 'tool_use': return 'tool_calls';
    default: return 'stop';
  }
}

interface RoundResult { stopReason: string; blocks: any[]; error?: string; }

// 单轮：请求 Anthropic，文本/思考 delta → OpenAI chunk 写给 client，收集 blocks + stop_reason。
async function streamOnce(
  payload: any, model: string, write: (s: string) => void
): Promise<RoundResult> {
  let upstream: Response;
  try {
    const up = getUpstream();
    const isDirectAnthropic = up.url.includes('api.anthropic.com');
    upstream = await fetch(up.url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', ...(isDirectAnthropic ? { 'x-api-key': up.auth } : { 'Authorization': up.auth }), 'anthropic-version': ANTHROPIC_VERSION },
      body: JSON.stringify({ ...payload, stream: true }),
      signal: AbortSignal.timeout(180_000),
    });
  } catch (e: any) {
    return { stopReason: 'error', blocks: [], error: e?.message || 'fetch failed' };
  }
  if (!upstream.ok || !upstream.body) {
    const t = await upstream.text().catch(() => '');
    return { stopReason: 'error', blocks: [], error: `${upstream.status}: ${t.slice(0, 300)}` };
  }

  const id = 'chatcmpl-' + Math.random().toString(36).slice(2);
  const created = Math.floor(Date.now() / 1000);
  const chunk = (delta: any) => write(`data: ${JSON.stringify({ id, object: 'chat.completion.chunk', created, model, choices: [{ index: 0, delta, finish_reason: null }] })}\n\n`);

  const reader = upstream.body.getReader();
  const decoder = new TextDecoder();
  let buf = '';
  let stopReason = 'end_turn';
  const blocks: any[] = [];
  let cur: any = null;

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buf += decoder.decode(value, { stream: true });
    const lines = buf.split('\n');
    buf = lines.pop() || '';
    for (const line of lines) {
      if (!line.startsWith('data:')) continue;
      const p = line.slice(5).trim();
      if (!p) continue;
      let ev: any; try { ev = JSON.parse(p); } catch { continue; }
      switch (ev.type) {
        case 'content_block_start':
          cur = { type: ev.content_block?.type || 'text' };
          if (cur.type === 'tool_use') { cur.id = ev.content_block.id; cur.name = ev.content_block.name; cur.inputJson = ''; }
          if (cur.type === 'text') cur.text = '';
          break;
        case 'content_block_delta': {
          const d = ev.delta || {};
          if (d.type === 'text_delta') { cur.text = (cur.text || '') + (d.text || ''); chunk({ content: d.text }); }
          else if (d.type === 'thinking_delta') { chunk({ reasoning: d.thinking }); }
          else if (d.type === 'input_json_delta') { cur.inputJson = (cur.inputJson || '') + (d.partial_json || ''); }
          break;
        }
        case 'content_block_stop':
          if (cur) {
            if (cur.type === 'tool_use') { try { cur.input = JSON.parse(cur.inputJson || '{}'); } catch { cur.input = {}; } delete cur.inputJson; }
            blocks.push(cur); cur = null;
          }
          break;
        case 'message_delta':
          if (ev.delta?.stop_reason) stopReason = ev.delta.stop_reason;
          if (ev.usage) console.log(`[tool-loop] usage cache_read=${ev.usage.cache_read_input_tokens || 0}`);
          break;
      }
    }
  }
  return { stopReason, blocks };
}

export async function runToolLoop(body: any, sessionId: string): Promise<Response> {
  if (!config.treeChatKey && !config.anthropicKey) {
    return new Response(JSON.stringify({ error: { message: 'ANTHROPIC_API_KEY not configured' } }), { status: 500, headers: { 'Content-Type': 'application/json' } });
  }
  const payload = buildAnthropicPayload(body, sessionId);
  // server_map 进 prompt 稳定缓存段（最前面的系统块，与 stableCore 同处第一缓存段）
  const sys = Array.isArray(payload.system) ? payload.system : (payload.system ? [{ type: 'text', text: payload.system }] : []);
  sys.unshift({ type: 'text', text: SERVER_MAP });
  sys.unshift({ type: 'text', text: SCREEN_PEEK_ABILITY });
  payload.system = sys;
  // 工具定义：内置在前、MCP 在后，顺序固定（缓存前缀稳定）
  const mcpTools = await getMcpTools();
  payload.tools = [
    ...BUILTIN_TOOLS,
    ...mcpTools.map((t: any) => ({ name: t.name, description: t.description, input_schema: t.input_schema })),
  ];

  const { readable, writable } = new TransformStream();
  const writer = writable.getWriter();
  const encoder = new TextEncoder();
  const write = (s: string) => { writer.write(encoder.encode(s)).catch(() => {}); };

  // SSE 保活：工具执行期间（exec 最长 60s）流上没字节，反代空闲超时会 504。
  let lastWrite = Date.now();
  const origWrite = write;
  const guardedWrite = (s: string) => { lastWrite = Date.now(); origWrite(s); };
  const ping = setInterval(() => { if (Date.now() - lastWrite > 14_000) write(': ping\n\n'); }, 5000);

  (async () => {
    let messages = [...payload.messages];
    let model = body.model;
    let loops = MAX_LOOPS;
    try {
      while (loops-- > 0) {
        const result = await streamOnce({ ...payload, messages }, model, guardedWrite);
        if (result.error) { write(`data: ${JSON.stringify({ error: { message: result.error } })}\n\n`); break; }
        if (result.stopReason !== 'tool_use') break;
        // 执行工具，结果塞回对话
        messages.push({ role: 'assistant', content: result.blocks });
        const toolResults: any[] = [];
        for (const b of result.blocks) {
          if (b.type !== 'tool_use') continue;
          let out = await callBuiltinTool(b.name, b.input);     // 内置：进程内
          if (out === null) out = await callMcpTool(b.name, b.input, mcpTools); // fall through 到 MCP
          // see_screen 等返回图片的工具：把 __peek_image__ 转成 tool_result 里的 image block（多模态 Caelum 亲眼看）
          let toolContent: any = out;
          if (typeof out === 'string' && out.includes('__peek_image__')) {
            try {
              const pk = JSON.parse(out);
              if (pk && pk.__peek_image__ && pk.data) {
                toolContent = [
                  { type: 'image', source: { type: 'base64', media_type: pk.media_type || 'image/png', data: pk.data } },
                  { type: 'text', text: `[用户当前 iPhone 屏幕截图 · App: ${pk.app || '未知'}]` },
                ];
              }
            } catch {}
          }
          toolResults.push({ type: 'tool_result', tool_use_id: b.id, content: toolContent });
        }
        messages.push({ role: 'user', content: toolResults });
      }
    } catch (e: any) {
      write(`data: ${JSON.stringify({ error: { message: e?.message || 'loop error' } })}\n\n`);
    } finally {
      clearInterval(ping);
      const created = Math.floor(Date.now() / 1000);
      write(`data: ${JSON.stringify({ id: 'chatcmpl-end', object: 'chat.completion.chunk', created, model, choices: [{ index: 0, delta: {}, finish_reason: 'stop' }] })}\n\n`);
      write('data: [DONE]\n\n');
      try { await writer.close(); } catch {}
    }
  })();

  return new Response(readable, { status: 200, headers: { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache' } });
}
