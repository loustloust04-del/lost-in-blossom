import { config } from '../config';

const BASE = 'https://openrouter.ai/api/v1/chat/completions';

export async function forwardOpenRouter(body: any): Promise<Response> {
  const upstream = await fetch(BASE, {
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
