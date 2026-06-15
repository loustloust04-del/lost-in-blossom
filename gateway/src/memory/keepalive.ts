import { config } from '../config';
import { getTTL } from './rhythm';

// ═══ 缓存保活 ═══
// 发一个最小化请求保持1小时缓存活着。
// 只在1小时TTL模式下执行。5分钟模式不保活（96次太贵）。

const SYSTEM_ANCHOR = '你是 Lost in Blossom 的 AI。这是一条保活请求，请只回复一个字。';

export async function keepCacheAlive(): Promise<void> {
  if (getTTL() !== '1h') {
    console.log('[keepalive] skip (TTL=5m)');
    return;
  }

  if (!config.openrouterKey) {
    console.log('[keepalive] skip (no OR key)');
    return;
  }

  try {
    const res = await fetch('https://openrouter.ai/api/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${config.openrouterKey}`,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({
        model: 'anthropic/claude-haiku-4.5',  // 最便宜的模型做保活
        max_tokens: 5,
        metadata: { user_id: 'bunny-blossom-stable' },
        system: [{
          type: 'text',
          text: SYSTEM_ANCHOR,
          cache_control: { type: 'ephemeral', ttl: '1h' },
        }],
        messages: [{ role: 'user', content: 'ping' }],
      }),
    });

    if (!res.ok) {
      console.error('[keepalive] failed:', res.status);
      return;
    }

    const data = await res.json() as any;
    const usage = data?.usage || {};
    const read = usage.cache_read_input_tokens || 0;
    console.log(`[keepalive] ✅ cache_read=${read} (TTL refreshed)`);
  } catch (err: any) {
    console.error('[keepalive] error:', err.message);
  }
}
