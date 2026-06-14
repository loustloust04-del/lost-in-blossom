import { config } from '../config';

// 直连 Anthropic 原生 Messages API，保留 cache_control 断点（OpenAI 兼容转发层会丢断点）。
const ANTHROPIC_BASE = 'https://api.anthropic.com/v1/messages';
const ANTHROPIC_VERSION = '2023-06-01';
const REQUEST_TIMEOUT_MS = 120_000;

// 上游配置：不同 provider 用不同的 base/key/模型名
export interface UpstreamOpts {
  baseUrl: string;
  apiKey: string;
  modelName: string;  // 已转换好的上游模型名
}

// gateway 模型名 → 真实 Anthropic model id
//   anthropic/claude-opus-4.8        → claude-opus-4-8
//   anthropic/claude-sonnet-4.6      → claude-sonnet-4-6
//   claude-opus-4                    → claude-opus-4-0
export function toAnthropicModel(model: string): string {
  let m = (model || '').replace(/^anthropic\//, '');
  m = m.replace(/(\d)\.(\d)/g, '$1-$2');            // 版本点号 → 短横线
  if (/^claude-(opus|sonnet|haiku)-\d$/.test(m)) m += '-0';
  return m;
}

type Block = { type: string; [k: string]: any };

// OpenAI content（string | 数组）→ Anthropic content blocks
function convertContent(content: any): any {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return content;
  return content.map((part: any) => {
    if (part?.type === 'text') return { type: 'text', text: part.text ?? '' };
    if (part?.type === 'image_url') {
      const url: string = part.image_url?.url || '';
      const m = url.match(/^data:([^;]+);base64,(.*)$/);
      if (m) return { type: 'image', source: { type: 'base64', media_type: m[1], data: m[2] } };
      return { type: 'image', source: { type: 'url', url } };
    }
    return part; // 透传已是 Anthropic 形态的块
  });
}

// 给某条 message 的最后一个 content block 挂 cache_control 断点
function withCacheOnLastBlock(content: any): any {
  if (typeof content === 'string') {
    return [{ type: 'text', text: content, cache_control: { type: 'ephemeral' } }];
  }
  if (Array.isArray(content) && content.length > 0) {
    const copy = content.map((b: any) => ({ ...b }));
    copy[copy.length - 1] = { ...copy[copy.length - 1], cache_control: { type: 'ephemeral' } };
    return copy;
  }
  return content;
}

// 把 OpenAI 格式请求体转成 Anthropic /v1/messages 请求体（含三层缓存断点）
export function buildAnthropicPayload(body: any, sessionId: string) {
  const messages: any[] = body.messages || [];
  const systemBlocks: Block[] = [];
  const anthropicMessages: any[] = [];

  for (const msg of messages) {
    if (msg.role === 'system') {
      if (typeof msg.content === 'string') {
        systemBlocks.push({ type: 'text', text: msg.content });
      } else if (Array.isArray(msg.content)) {
        for (const b of msg.content) {
          if (b?.type === 'text') systemBlocks.push({ type: 'text', text: b.text ?? '' });
          else systemBlocks.push(b);
        }
      }
    } else if (msg.role === 'user' || msg.role === 'assistant') {
      anthropicMessages.push({ role: msg.role, content: convertContent(msg.content) });
    }
  }

  // 断点 1+2：stableCore（首块）+ semiStable（末块）。volatile（时间/健康）由 App
  // 注入到最后一条 user 消息，天然落在所有断点之后。
  systemBlocks.forEach((b) => { delete (b as any).cache_control; });
  if (systemBlocks.length > 0) {
    systemBlocks[0].cache_control = { type: 'ephemeral' };
    systemBlocks[systemBlocks.length - 1].cache_control = { type: 'ephemeral' };
  }

  // 断点 3：倒数第二条 user turn（最后一条每轮都变，挂上去等于没挂）。
  const userIdx: number[] = [];
  anthropicMessages.forEach((m, i) => { if (m.role === 'user') userIdx.push(i); });
  if (userIdx.length >= 2) {
    const t = anthropicMessages[userIdx[userIdx.length - 2]];
    t.content = withCacheOnLastBlock(t.content);
  }

  const isThinking = !!body.reasoning || /:thinking$/.test(body.model || '');

  const payload: any = {
    model: toAnthropicModel(body.model),
    max_tokens: body.max_tokens ?? 8192,
    messages: anthropicMessages,
    stream: body.stream === true,
    metadata: { user_id: sessionId },
  };
  if (systemBlocks.length > 0) payload.system = systemBlocks;
  if (isThinking) payload.thinking = { type: 'adaptive' };
  return payload;
}

function mapStop(reason: string | null | undefined): string {
  switch (reason) {
    case 'end_turn':
    case 'stop_sequence': return 'stop';
    case 'max_tokens': return 'length';
    case 'tool_use': return 'tool_calls';
    default: return 'stop';
  }
}

function openAIUsage(u: any) {
  const cacheRead = u?.cache_read_input_tokens || 0;
  const cacheWrite = u?.cache_creation_input_tokens || 0;
  const input = u?.input_tokens || 0;
  return {
    prompt_tokens: input + cacheRead + cacheWrite,
    completion_tokens: u?.output_tokens || 0,
    total_tokens: input + cacheRead + cacheWrite + (u?.output_tokens || 0),
    prompt_tokens_details: { cached_tokens: cacheRead },
    cache_read_input_tokens: cacheRead,
    cache_creation_input_tokens: cacheWrite,
  };
}

function errorResponse(message: string, status = 502): Response {
  return new Response(
    JSON.stringify({ error: { message, type: 'upstream_error', code: status } }),
    { status, headers: { 'Content-Type': 'application/json' } },
  );
}

// Anthropic SSE → OpenAI chat.completion.chunk SSE（thinking 走 delta.reasoning，
// 与 app.ts 现有 :thinking 转换逻辑兼容）。
function translateStream(upstream: Response, model: string): Response {
  const { readable, writable } = new TransformStream();
  const writer = writable.getWriter();
  const encoder = new TextEncoder();
  const id = 'chatcmpl-' + Math.random().toString(36).slice(2);
  const created = Math.floor(Date.now() / 1000);

  const chunk = (delta: any, finish: string | null = null) =>
    `data: ${JSON.stringify({ id, object: 'chat.completion.chunk', created, model,
      choices: [{ index: 0, delta, finish_reason: finish }] })}\n\n`;

  (async () => {
    try {
      const reader = upstream.body!.getReader();
      const decoder = new TextDecoder();
      let buf = '';
      let curType = 'text';
      let finish = 'stop';
      await writer.write(encoder.encode(chunk({ role: 'assistant', content: '' })));

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        buf += decoder.decode(value, { stream: true });
        const lines = buf.split('\n');
        buf = lines.pop() || '';
        for (const line of lines) {
          if (!line.startsWith('data:')) continue;
          const payload = line.slice(5).trim();
          if (!payload) continue;
          let ev: any;
          try { ev = JSON.parse(payload); } catch { continue; }
          if (ev.type === 'message_start') {
            const u = ev.message?.usage || {};
            console.log(`[anthropic-native] cache_read=${u.cache_read_input_tokens || 0} cache_write=${u.cache_creation_input_tokens || 0} input=${u.input_tokens || 0}`);
          } else if (ev.type === 'content_block_start') {
            curType = ev.content_block?.type || 'text';
          } else if (ev.type === 'content_block_delta') {
            const d = ev.delta || {};
            if (d.type === 'text_delta' && d.text) {
              await writer.write(encoder.encode(chunk({ content: d.text })));
            } else if (d.type === 'thinking_delta' && d.thinking) {
              await writer.write(encoder.encode(chunk({ reasoning: d.thinking })));
            }
          } else if (ev.type === 'message_delta') {
            if (ev.delta?.stop_reason) finish = mapStop(ev.delta.stop_reason);
          }
        }
      }
      await writer.write(encoder.encode(chunk({}, finish)));
      await writer.write(encoder.encode('data: [DONE]\n\n'));
    } catch (e: any) {
      console.error('[anthropic-native] stream error:', e?.message);
    } finally {
      try { await writer.close(); } catch {}
    }
  })();

  return new Response(readable, {
    status: 200,
    headers: { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache' },
  });
}

export async function forwardAnthropicNative(body: any, sessionId: string, opts?: UpstreamOpts): Promise<Response> {
  const baseUrl = opts?.baseUrl || ANTHROPIC_BASE;
  const apiKey = opts?.apiKey || config.anthropicKey;
  if (!apiKey) return errorResponse('No API key for anthropic-native', 500);

  const payload = buildAnthropicPayload(body, sessionId);
  // 覆盖模型名（中转站可能需要不同格式）
  if (opts?.modelName) payload.model = opts.modelName;

  const isAnthropicDirect = baseUrl === ANTHROPIC_BASE;

  let upstream: Response;
  try {
    upstream = await fetch(baseUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        // 直连 Anthropic 用 x-api-key，中转站用 Authorization: Bearer
        ...(isAnthropicDirect
          ? { 'x-api-key': apiKey }
          : { 'Authorization': `Bearer ${apiKey}` }),
        'anthropic-version': ANTHROPIC_VERSION,
      },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    });
  } catch (e: any) {
    console.error('[anthropic-native] fetch failed:', e?.message);
    return errorResponse(`anthropic upstream unreachable: ${e?.message}`, 502);
  }

  if (!upstream.ok) {
    const text = await upstream.text().catch(() => '');
    console.error(`[anthropic-native] upstream ${upstream.status}: ${text.slice(0, 300)}`);
    return errorResponse(text || `anthropic upstream ${upstream.status}`, upstream.status);
  }

  if (payload.stream) return translateStream(upstream, body.model);

  // 非流式：Anthropic message → OpenAI chat.completion
  const data: any = await upstream.json().catch(() => null);
  if (!data) return errorResponse('invalid anthropic response', 502);
  const text = (data.content || []).filter((b: any) => b.type === 'text').map((b: any) => b.text).join('');
  const u = data.usage || {};
  console.log(`[anthropic-native] cache_read=${u.cache_read_input_tokens || 0} cache_write=${u.cache_creation_input_tokens || 0} input=${u.input_tokens || 0}`);
  const openai = {
    id: data.id || 'chatcmpl-' + Math.random().toString(36).slice(2),
    object: 'chat.completion',
    created: Math.floor(Date.now() / 1000),
    model: body.model,
    choices: [{ index: 0, message: { role: 'assistant', content: text }, finish_reason: mapStop(data.stop_reason) }],
    usage: openAIUsage(u),
  };
  return new Response(JSON.stringify(openai), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}
