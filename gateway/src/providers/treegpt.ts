import { config } from '../config';
import { buildAnthropicPayload } from './anthropic-native';

const OAI_BASE = 'https://api.treegpt.cc/v1/chat/completions';
const NATIVE_BASE = 'https://api.treegpt.cc/v1/messages';

function isClaude(model: string): boolean {
  const m = (model || '').toLowerCase();
  return m.includes('claude') || m.includes('anthropic');
}

export async function forwardTreeChat(body: any): Promise<Response> {
  const localModel = (body.model || '').replace('tree-chat/', '');
  const upstreamModel = '[官]' + localModel;

  if (isClaude(localModel)) {
    const payload = buildAnthropicPayload(body, 'bunny-main');
    payload.model = upstreamModel;
    console.log('[tree-chat] native Anthropic:', upstreamModel, 'stream:', body.stream);

    const upstream = await fetch(NATIVE_BASE, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ' + config.treeChatKey,
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

  console.log('[tree-chat] upstream:', upstreamModel, 'stream:', body.stream);
  const upstream = await fetch(OAI_BASE, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ' + config.treeChatKey,
    },
    body: JSON.stringify({ ...body, model: upstreamModel }),
  });
  return new Response(upstream.body, {
    status: upstream.status,
    headers: {
      'Content-Type': upstream.headers.get('Content-Type') || 'text/event-stream',
      'Cache-Control': 'no-cache',
    },
  });
}

export async function forwardTreeApi(body: any): Promise<Response> {
  const upstreamModel = (body.model || '').replace('tree-api/', '');

  if (isClaude(upstreamModel)) {
    const payload = buildAnthropicPayload(body, 'bunny-main');
    payload.model = upstreamModel;
    console.log('[tree-api] native Anthropic:', upstreamModel, 'stream:', body.stream);

    const upstream = await fetch(NATIVE_BASE, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ' + config.treeApiKey,
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

  console.log('[tree-api] upstream:', upstreamModel, 'stream:', body.stream);
  const upstream = await fetch(OAI_BASE, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ' + config.treeApiKey,
    },
    body: JSON.stringify({ ...body, model: upstreamModel }),
  });
  return new Response(upstream.body, {
    status: upstream.status,
    headers: {
      'Content-Type': upstream.headers.get('Content-Type') || 'text/event-stream',
      'Cache-Control': 'no-cache',
    },
  });
}
