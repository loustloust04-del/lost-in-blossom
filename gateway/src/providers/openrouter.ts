import { config } from '../config';
import { buildAnthropicPayload, toAnthropicModel } from './anthropic-native';

const OAI_BASE = 'https://openrouter.ai/api/v1/chat/completions';
const NATIVE_BASE = 'https://openrouter.ai/api/v1/messages';

function isClaude(model: string): boolean {
  const m = (model || '').toLowerCase();
  return m.includes('claude') || m.startsWith('anthropic/');
}

export async function forwardOpenRouter(body: any): Promise<Response> {
  // Claude models → OR native Anthropic endpoint (preserves cache_control)
  if (isClaude(body.model)) {
    const payload = buildAnthropicPayload(body, 'bunny-main');
    // OR needs the original model name with provider prefix
    payload.model = body.model;

    const upstream = await fetch(NATIVE_BASE, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${config.openrouterKey}`,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify(payload),
    });
    return new Response(upstream.body, {
      status: upstream.status,
      headers: {
        'Content-Type': upstream.headers.get('Content-Type') || 'text/event-stream',
        'Cache-Control': 'no-cache',
      },
    });
  }

  // Non-Claude models → OpenAI compat (auto-caching by OR)
  const upstream = await fetch(OAI_BASE, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${config.openrouterKey}`,
    },
    body: JSON.stringify({ ...body, session_id: 'bunny-main' }),
  });
  return new Response(upstream.body, {
    status: upstream.status,
    headers: {
      'Content-Type': upstream.headers.get('Content-Type') || 'text/event-stream',
      'Cache-Control': 'no-cache',
    },
  });
}
