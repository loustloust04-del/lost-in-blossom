import { Hono } from 'hono';
import { auth } from './middleware/auth';
import { forwardDeepSeek } from './providers/deepseek';
import { forwardOpenRouter } from './providers/openrouter';
import { forwardAnthropicNative } from './providers/anthropic-native';
import { runToolLoop } from './tools/loop';
import { forwardTreeChat, forwardTreeApi } from './providers/treegpt';
import { enhanceMessages } from './prompt/builder';
import { saveMessage, compressForStorage } from './memory/store';
import { extractMemoriesIfNeeded } from './memory/extractor';
import { config } from './config';
import { getUnreadDesires, onAppOpenEvent } from './memory/desire';
import { recordEvent, verifyEventToken } from './memory/events';
import { listMemories, listDreams, listDesires, syncMemories, diffMemories } from './memory/sync';

const app = new Hono();

// ============ 健康检查 ============
app.get('/health', (c) => c.json({
  status: 'ok',
  ts: Date.now(),
  memory: config.supabaseUrl ? 'connected' : 'not configured',
}));

// ============ 模型列表 ============
app.get('/v1/models', auth, (c) => c.json({
  object: 'list',
  data: [
    { id: 'anthropic/claude-opus-4.8', object: 'model', owned_by: 'anthropic' },
    { id: 'anthropic/claude-opus-4.8:thinking', object: 'model', owned_by: 'anthropic' },
    { id: 'anthropic/claude-opus-4.7', object: 'model', owned_by: 'anthropic' },
    { id: 'anthropic/claude-opus-4.7:thinking', object: 'model', owned_by: 'anthropic' },
    { id: 'anthropic/claude-opus-4.6', object: 'model', owned_by: 'anthropic' },
    { id: 'anthropic/claude-opus-4.6:thinking', object: 'model', owned_by: 'anthropic' },
    { id: 'anthropic/claude-opus-4.5', object: 'model', owned_by: 'anthropic' },
    { id: 'anthropic/claude-opus-4.1', object: 'model', owned_by: 'anthropic' },
    { id: 'anthropic/claude-opus-4', object: 'model', owned_by: 'anthropic' },
    { id: 'anthropic/claude-sonnet-4.6', object: 'model', owned_by: 'anthropic' },
    { id: 'anthropic/claude-sonnet-4.6:thinking', object: 'model', owned_by: 'anthropic' },
    { id: 'anthropic/claude-sonnet-4.5', object: 'model', owned_by: 'anthropic' },
    { id: 'anthropic/claude-sonnet-4.5:thinking', object: 'model', owned_by: 'anthropic' },
    { id: 'anthropic/claude-sonnet-4', object: 'model', owned_by: 'anthropic' },
    { id: 'openai/gpt-4o-2024-11-20', object: 'model', owned_by: 'openai' },
    { id: 'openai/gpt-4o', object: 'model', owned_by: 'openai' },
    { id: 'openai/gpt-4o-mini', object: 'model', owned_by: 'openai' },
    { id: 'deepseek/deepseek-v4-pro', object: 'model', owned_by: 'deepseek' },
    { id: 'deepseek/deepseek-r1-0528', object: 'model', owned_by: 'deepseek' },
    { id: 'google/gemini-2.5-flash', object: 'model', owned_by: 'google' },
    // TreeGPT [官]对话分组 — 日常主力 ¥18.75/M
    { id: 'tree-chat/claude-opus-4-8', object: 'model', owned_by: 'treegpt-chat' },
    { id: 'tree-chat/claude-opus-4-7', object: 'model', owned_by: 'treegpt-chat' },
    { id: 'tree-chat/claude-opus-4-6', object: 'model', owned_by: 'treegpt-chat' },
    { id: 'tree-chat/claude-opus-4-6-thinking', object: 'model', owned_by: 'treegpt-chat' },
    { id: 'tree-chat/claude-sonnet-4-6', object: 'model', owned_by: 'treegpt-chat' },
    { id: 'tree-chat/claude-sonnet-4-6-thinking', object: 'model', owned_by: 'treegpt-chat' },
    // TreeGPT 官API分组 — 重要对话 ¥62.5/M
    { id: 'tree-api/claude-opus-4-8', object: 'model', owned_by: 'treegpt-api' },
    { id: 'tree-api/claude-opus-4-7', object: 'model', owned_by: 'treegpt-api' },
    { id: 'tree-api/claude-opus-4-6', object: 'model', owned_by: 'treegpt-api' },
    { id: 'tree-api/claude-sonnet-4-6', object: 'model', owned_by: 'treegpt-api' },
  ]
}));


// ============ 未读念头（欲望系统）============
app.get('/v1/desires', auth, async (c) => {
  const desires = await getUnreadDesires();
  return c.json({ desires });
});

// ============ iOS Shortcuts 事件上报（PR-3）============
app.post('/api/events', async (c) => {
  // token：Authorization: Bearer xxx 或 ?key=xxx（Shortcuts 友好）
  const h = c.req.header('Authorization');
  const headerTok = h?.startsWith('Bearer ') ? h.slice(7) : '';
  const tok = headerTok || c.req.query('key') || '';
  if (!verifyEventToken(tok)) {
    return c.json({ ok: false, error: 'forbidden' }, 403);
  }

  // 兼容 JSON body 与 query 两种上报方式
  let body: any = {};
  try { body = await c.req.json(); } catch { body = {}; }
  const type = body.type ?? c.req.query('type');
  const value = body.value ?? c.req.query('value');
  if (!type || !value) {
    return c.json({ ok: false, error: 'type and value required' }, 400);
  }
  const ts = typeof body.ts === 'number' ? body.ts : Date.now();

  const res = await recordEvent({ type, value, ts, metadata: body.metadata ?? null });

  // PR-4: 深夜守护——凌晨收到 app_open 立刻检查是否该喊她睡觉（fire-and-forget）
  if (type === 'app_open') {
    onAppOpenEvent(String(value)).catch(err =>
      console.error('[nightguard] error:', err?.message ?? err));
  }

  return c.json({ ok: res.ok, ...(res.error ? { error: res.error } : {}) });
});

// ============ 未读念头（App 端拉取，支持 ?since=ms 增量）（PR-6）============
app.get('/api/desires/unread', auth, async (c) => {
  const sinceRaw = c.req.query('since');
  const since = sinceRaw ? Number(sinceRaw) : undefined;
  const desires = await getUnreadDesires(since && !Number.isNaN(since) ? since : undefined);
  return c.json({ desires });
});

// ============ 记忆系统 API（供 App 拉取/对齐，全部需 Bearer token）============
app.get('/api/memories', auth, async (c) => {
  const limit = Math.min(Math.max(Number(c.req.query('limit')) || 50, 1), 200);
  const offset = Math.max(Number(c.req.query('offset')) || 0, 0);
  const category = c.req.query('category') || undefined;
  const { items, total } = await listMemories({ limit, offset, category });
  return c.json({ memories: items, total, limit, offset });
});

// 做梦日记（日/周/月摘要），?period=daily|weekly|monthly 可筛选
app.get('/api/memories/dreams', auth, async (c) => {
  const period = c.req.query('period') || undefined;
  const { items } = await listDreams(period);
  return c.json({ dreams: items });
});

// 欲望系统生成的念头（碎碎念）
app.get('/api/memories/desires', auth, async (c) => {
  const limit = Math.min(Math.max(Number(c.req.query('limit')) || 50, 1), 200);
  const offset = Math.max(Number(c.req.query('offset')) || 0, 0);
  const { items } = await listDesires(limit, offset);
  return c.json({ desires: items });
});

// App 端手动写入的记忆 → 去重合并到 Supabase
app.post('/api/memories/sync', auth, async (c) => {
  let body: any = {};
  try { body = await c.req.json(); } catch {}
  const incoming = Array.isArray(body) ? body : (Array.isArray(body?.memories) ? body.memories : []);
  if (!incoming.length) return c.json({ added: 0, skipped: 0, addedIds: [] });
  const res = await syncMemories(incoming);
  return c.json(res);
});

// 网关有但 App 没有的记忆（?since=ms 增量），供对齐
app.get('/api/memories/diff', auth, async (c) => {
  const sinceRaw = c.req.query('since');
  const since = sinceRaw ? Number(sinceRaw) : undefined;
  const limit = Math.min(Math.max(Number(c.req.query('limit')) || 200, 1), 500);
  const { items } = await diffMemories(since && !Number.isNaN(since) ? since : undefined, limit);
  return c.json({ memories: items });
});

// ============ 主聊天端点 ============
app.post('/v1/chat/completions', auth, async (c) => {
  const body = await c.req.json();
  const model: string = body.model || '';
  const isStream = body.stream === true;
  const sessionId = c.req.header('X-Session-Id') || 'default';

  // 提取用户最新消息
  const messages: any[] = body.messages || [];
  const lastUserMsg = [...messages].reverse().find(m => m.role === 'user');
  const userText = lastUserMsg?.content || '';

  // --- 记忆增强（如果 Supabase 已配置）---
  let enhancedMessages = messages;
  if (config.supabaseUrl && config.brainEnabled && userText) {
    try {
      enhancedMessages = await enhanceMessages(messages, userText);
      console.log(`[memory] enhanced: +${enhancedMessages.length - messages.length} system entries`);
    } catch (err: any) {
      console.error('[memory] enhance failed, using original:', err.message);
    }
  }

  // 存用户消息
  if (config.supabaseUrl && userText) {
    saveMessage(sessionId, 'user', userText, model).catch(() => {});
  }

  // 转发请求
  const forwardBody = { ...body, messages: enhancedMessages };

  // Claude不允许同时传temperature和top_p，保留temperature，干掉top_p
  if (forwardBody.temperature !== undefined && forwardBody.top_p !== undefined) {
    delete forwardBody.top_p;
    console.log('[param] stripped top_p (Claude compatibility)');
  }

  // thinking模式：检测:thinking后缀，加reasoning参数
  let actualModel = model;
  const isThinking = model.endsWith(":thinking");
  if (isThinking) {
    actualModel = model.replace(":thinking", "");
    forwardBody.model = actualModel;
    forwardBody.reasoning = { max_tokens: 16000 };
    console.log(`[thinking] enabled for ${actualModel}`);
  }
  let upstream: Response;

  if (actualModel.includes("deepseek")) {
    upstream = await forwardDeepSeek(forwardBody);
  } else if (actualModel.startsWith("tree-chat/") && actualModel.includes("claude")) {
    // TreeGPT chat 组 Claude → A社格式直连，保留缓存断点
    const modelName = actualModel.replace('tree-chat/', '');
    upstream = await forwardAnthropicNative(forwardBody, sessionId, {
      baseUrl: 'https://api.treegpt.cc/v1/messages',
      apiKey: config.treeChatKey,
      modelName,
    });
  } else if (actualModel.startsWith("tree-api/") && actualModel.includes("claude")) {
    // TreeGPT api 组 Claude → A社格式直连
    const modelName = actualModel.replace('tree-api/', '');
    upstream = await forwardAnthropicNative(forwardBody, sessionId, {
      baseUrl: 'https://api.treegpt.cc/v1/messages',
      apiKey: config.treeApiKey,
      modelName,
    });
  } else if (actualModel.startsWith("tree-chat/")) {
    upstream = await forwardTreeChat(forwardBody);
  } else if (actualModel.startsWith("tree-api/")) {
    upstream = await forwardTreeApi(forwardBody);
  } else if (actualModel.includes("claude")) {
    // 所有其他 Claude → OR 的 A社格式端点，保留缓存断点
    upstream = await forwardAnthropicNative(forwardBody, sessionId, {
      baseUrl: 'https://openrouter.ai/api/v1/messages',
      apiKey: config.openrouterKey,
      modelName: actualModel,
    });
  } else {
    upstream = await forwardOpenRouter(forwardBody);
  }

  // --- thinking模式：流式转换reasoning为content ---
  if (isThinking && isStream) {
    const { readable, writable } = new TransformStream();
    const writer = writable.getWriter();
    const encoder = new TextEncoder();
    let fullContent = '';
    let inReasoning = false;
    let sentHeader = false;

    (async () => {
      try {
        const reader = upstream.body!.getReader();
        const decoder = new TextDecoder();
        let buf = '';

        while (true) {
          const { done, value } = await reader.read();
          if (done) { await writer.close(); break; }

          buf += decoder.decode(value, { stream: true });
          const lines = buf.split('\n');
          buf = lines.pop() || '';

          for (const line of lines) {
            if (!line.startsWith('data: ')) {
              if (line.trim() === '') await writer.write(encoder.encode('\n'));
              continue;
            }
            if (line.includes('[DONE]')) {
              await writer.write(encoder.encode('data: [DONE]\n\n'));
              continue;
            }

            try {
              const j = JSON.parse(line.slice(6));
              const delta = j.choices?.[0]?.delta;
              if (!delta) { await writer.write(encoder.encode(line + '\n')); continue; }

              const reasoning = delta.reasoning || '';
              const content = delta.content || '';

              if (reasoning) {
                // thinking阶段——发header后把reasoning转为content
                if (!sentHeader) {
                  const hdr = {...j, choices: [{...j.choices[0], delta: {content: '[thinking]\n\n', role: 'assistant'}}]};
                  await writer.write(encoder.encode(`data: ${JSON.stringify(hdr)}\n\n`));
                  sentHeader = true;
                  inReasoning = true;
                }
                const converted = {...j, choices: [{...j.choices[0], delta: {content: reasoning}}]};
                delete converted.choices[0].delta.reasoning;
                delete converted.choices[0].delta.reasoning_details;
                await writer.write(encoder.encode(`data: ${JSON.stringify(converted)}\n\n`));

              } else if (content) {
                // content阶段
                if (inReasoning) {
                  const sep = {...j, choices: [{...j.choices[0], delta: {content: '\n\n[/thinking]\n\n'}}]};
                  await writer.write(encoder.encode(`data: ${JSON.stringify(sep)}\n\n`));
                  inReasoning = false;
                }
                await writer.write(encoder.encode(line + '\n'));
                fullContent += content;

              } else {
                // finish等其他事件——透传
                await writer.write(encoder.encode(line + '\n'));
              }
            } catch {
              await writer.write(encoder.encode(line + '\n'));
            }
          }
        }
      } catch (e: any) {
        console.error('[thinking-stream] error:', e.message);
        try { await writer.close(); } catch {}
      }
      // 存消息（只存content不存thinking）
      if (fullContent) {
        const { compressed: compressedContent } = compressForStorage(fullContent);
        saveMessage(sessionId, 'assistant', compressedContent, model).catch(() => {});
        if (userText && fullContent) {
          const recent = [{role: "user", content: userText}, {role: "assistant", content: fullContent}];
          config.brainEnabled && extractMemoriesIfNeeded(recent, model).catch(e => console.error("[extract] async error:", e.message));
        }
      }
      console.log(`[thinking] stream done, content: ${fullContent.length} chars`);
    })();

    return new Response(readable, {
      status: upstream.status,
      headers: { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache' },
    });
  }

  // --- 收集AI回复并存储 ---
  if (config.supabaseUrl && isStream) {
    // 流式：边透传边收集
    const { readable, writable } = new TransformStream();
    const writer = writable.getWriter();
    let fullContent = '';

    (async () => {
      try {
        const reader = upstream.body!.getReader();
        const decoder = new TextDecoder();
        while (true) {
          const { done, value } = await reader.read();
          if (done) { await writer.close(); break; }
          await writer.write(value);
          const text = decoder.decode(value, { stream: true });
          for (const line of text.split('\n')) {
            if (line.startsWith('data: ') && !line.includes('[DONE]')) {
              try {
                const j = JSON.parse(line.slice(6));
                const delta = j.choices?.[0]?.delta?.content;
                if (delta) fullContent += delta;
              } catch {}
            }
          }
        }
      } catch (e: any) {
        console.error('[stream] collect error:', e.message);
        try { await writer.close(); } catch {}
      }
      // 流结束，存AI回复
      if (fullContent) {
        saveMessage(sessionId, 'assistant', fullContent, model).catch(() => {});
        // Phase 3: 异步提取记忆
        if (userText && fullContent) {
          const recent = [{role: "user", content: userText}, {role: "assistant", content: fullContent}];
          config.brainEnabled && extractMemoriesIfNeeded(recent, model).catch(e => console.error("[extract] async error:", e.message));
        }
      }
    })();

    return new Response(readable, {
      status: upstream.status,
      headers: {
        'Content-Type': upstream.headers.get('Content-Type') || 'text/event-stream',
        'Cache-Control': 'no-cache',
      },
    });

  } else if (config.supabaseUrl && !isStream) {
    // 非流式：直接提取content
    const data = await upstream.json() as any;
    const assistantContent = data?.choices?.[0]?.message?.content || '';
    if (assistantContent) {
      saveMessage(sessionId, 'assistant', assistantContent, model).catch(() => {});
      // Phase 3: 异步提取记忆
      if (userText && assistantContent) {
        const recent = [{role: "user", content: userText}, {role: "assistant", content: assistantContent}];
        config.brainEnabled && extractMemoriesIfNeeded(recent, model).catch(e => console.error("[extract] async error:", e.message));
      }
    }
    return c.json(data);

  } else {
    // Supabase 未配置——纯透传（Phase 1 模式）
    return new Response(upstream.body, {
      status: upstream.status,
      headers: {
        'Content-Type': upstream.headers.get('Content-Type') || 'text/event-stream',
        'Cache-Control': 'no-cache',
      },
    });
  }
});


// ============ Anthropic 原生透传端点 ============
// App 的 AnthropicProvider 直接连这里，原生格式进出，cache_control 完整保留。
app.post('/v1/messages', auth, async (c) => {
  const body = await c.req.json();
  const model = body.model || '';
  console.log('[/v1/messages] model:', model, 'stream:', body.stream);

  // 决定上游：有中转站 key 优先走中转站，否则走直连 Anthropic
  let upstreamUrl: string;
  let authHeader: string;

  if (config.treeChatKey) {
    upstreamUrl = 'https://api.treegpt.cc/v1/messages';
    authHeader = 'Bearer ' + config.treeChatKey;
  } else if (config.openrouterKey) {
    upstreamUrl = 'https://openrouter.ai/api/v1/messages';
    authHeader = 'Bearer ' + config.openrouterKey;
  } else if (config.anthropicKey) {
    upstreamUrl = 'https://api.anthropic.com/v1/messages';
    authHeader = config.anthropicKey;
  } else {
    return c.json({ error: 'No upstream API key configured' }, 500);
  }

  const isAnthropicDirect = upstreamUrl.includes('api.anthropic.com');
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    'anthropic-version': '2023-06-01',
  };
  if (isAnthropicDirect) {
    headers['x-api-key'] = config.anthropicKey;
  } else {
    headers['Authorization'] = authHeader;
  }

  const upstream = await fetch(upstreamUrl, {
    method: 'POST',
    headers,
    body: JSON.stringify(body),
  });

  return new Response(upstream.body, {
    status: upstream.status,
    headers: {
      'Content-Type': upstream.headers.get('Content-Type') || 'text/event-stream',
      'Cache-Control': 'no-cache',
    },
  });
});

export default {
  port: config.port,
  fetch: app.fetch,
};

console.log(`🌸 Lost in Blossom Gateway`);
console.log(`   port: ${config.port}`);
console.log(`   token: ${config.gatewayToken ? '✅ set' : '❌ missing'}`);
console.log(`   deepseek: ${config.deepseekKey ? '✅ set' : '❌ missing'}`);
console.log(`   openrouter: ${config.openrouterKey ? '✅ set' : '❌ missing'}`);
console.log(`   ✅ listening on http://localhost:${config.port}/`);
