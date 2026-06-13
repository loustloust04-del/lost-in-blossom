import { config } from '../config';

const BASE_URL = 'https://api.treegpt.cc/v1/chat/completions';

export async function forwardTreeChat(body: any): Promise<Response> {
  const localModel = (body.model || '').replace('tree-chat/', '');
  const upstreamModel = '[官]' + localModel;
  console.log('[tree-chat] upstream:', upstreamModel, 'stream:', body.stream);

  const upstream = await fetch(BASE_URL, {
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
  console.log('[tree-api] upstream:', upstreamModel, 'stream:', body.stream);

  const upstream = await fetch(BASE_URL, {
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
