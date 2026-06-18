import { config } from '../config';
import { supabase } from '../db/supabase';

// ═══ 缓存保活 ═══
// 每55分钟发一次最小化请求保持1h缓存活着。
// 使用最近一次正式请求的人设和模型。
// 保活全部需要App推送snapshot（将来做）。

interface CacheSnapshot {
  systemBlocks: any[];   // 人设（BP1）
  summary: string | null; // 摘要（BP2，App推送时才有）
  model: string;          // 最近使用的模型
  provider: 'or' | 'tree-aws';
  updatedAt: number;
}

// 内存缓存：从每次正式请求中提取
let snapshot: CacheSnapshot | null = null;

// 每次正式请求经过Gateway时调用，缓存人设和模型
export function updateSnapshot(systemBlocks: any[], model: string, provider: 'or' | 'tree-aws'): void {
  snapshot = {
    systemBlocks,
    summary: snapshot?.summary ?? null,
    model,
    provider,
    updatedAt: Date.now(),
  };
  console.log(`[keepalive] snapshot updated: ${systemBlocks.length} blocks, model=${model}`);
}

// App推送摘要+历史时调用（将来对接）
export function updateSummary(summary: string): void {
  if (snapshot) {
    snapshot.summary = summary;
    console.log(`[keepalive] summary updated: ${summary.length} chars`);
  }
}

export async function keepCacheAlive(): Promise<void> {
  if (!snapshot) {
    console.log('[keepalive] skip (no snapshot yet, waiting for first request)');
    return;
  }

  // 检查snapshot是否太旧（超过2小时没有正式请求，可能人设已经变了）
  const age = (Date.now() - snapshot.updatedAt) / 1000 / 60;
  if (age > 120) {
    console.log(`[keepalive] skip (snapshot ${Math.round(age)}min old, too stale)`);
    return;
  }

  const baseUrl = snapshot.provider === 'tree-aws'
    ? 'https://api.treegpt.cc/v1/messages'
    : 'https://openrouter.ai/api/v1/messages';

  const apiKey = snapshot.provider === 'tree-aws'
    ? config.treeAwsKey
    : config.openrouterKey;

  if (!apiKey) {
    console.log('[keepalive] skip (no API key)');
    return;
  }

  // 构建保活请求：只带人设（BP1）+ 摘要（BP2，如果有）
  const system: any[] = [];

  // BP1: 人设
  if (snapshot.systemBlocks.length > 0) {
    const first = { ...snapshot.systemBlocks[0] };
    first.cache_control = { type: 'ephemeral', ttl: '1h' };
    system.push(first);

    // 中间的blocks不加断点
    for (let i = 1; i < snapshot.systemBlocks.length - 1; i++) {
      const b = { ...snapshot.systemBlocks[i] };
      delete b.cache_control;
      system.push(b);
    }

    // 最后一个block加断点
    if (snapshot.systemBlocks.length > 1) {
      const last = { ...snapshot.systemBlocks[snapshot.systemBlocks.length - 1] };
      last.cache_control = { type: 'ephemeral', ttl: '1h' };
      system.push(last);
    }
  }

  // BP2: 摘要（如果App推送过来的话）
  if (snapshot.summary) {
    system.push({
      type: 'text',
      text: snapshot.summary,
      cache_control: { type: 'ephemeral', ttl: '1h' },
    });
  }

  // 确定模型名（中转站格式）
  let modelName = snapshot.model;
  if (snapshot.provider === 'tree-aws') {
    modelName = modelName.replace('tree-aws/', '');
  }

  const isAnthropicDirect = false; // 我们不直连A社

  try {
    const res = await fetch(baseUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({
        model: modelName,
        max_tokens: 5,
        metadata: { user_id: 'bunny-blossom-stable' },
        system,
        messages: [{ role: 'user', content: 'ping' }],
      }),
    });

    if (!res.ok) {
      const errText = await res.text().catch(() => '');
      console.error(`[keepalive] failed: ${res.status} ${errText.slice(0, 100)}`);
      return;
    }

    const data = await res.json() as any;
    const usage = data?.usage || {};
    const read = usage.cache_read_input_tokens || 0;
    const write = usage.cache_creation_input_tokens || 0;
    console.log(`[keepalive] ✅ read=${read} write=${write} model=${modelName}`);
  } catch (err: any) {
    console.error('[keepalive] error:', err.message);
  }
}
