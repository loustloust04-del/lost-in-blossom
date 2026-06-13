import { config } from '../config';

const BASE_URL = 'https://openrouter.ai/api/v1/chat/completions';

export async function forwardOpenRouter(body: any): Promise<Response> {
  console.log('[openrouter] upstream:', body.model, 'stream:', body.stream);

  const upstream = await fetch(BASE_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ' + config.openrouterKey,
    },
    body: JSON.stringify(body),
  });
  return new Response(upstream.body, {
    status: upstream.status,
    headers: {
      'Content-Type': upstream.headers.get('Content-Type') || 'text/event-stream',
      'Cache-Control': 'no-cache',
    },
  });
}
