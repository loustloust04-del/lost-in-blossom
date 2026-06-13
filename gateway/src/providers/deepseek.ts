import { config } from '../config';

const BASE = 'https://api.deepseek.com/v1/chat/completions';

export async function forwardDeepSeek(body: any): Promise<Response> {
  const upstream = await fetch(BASE, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${config.deepseekKey}`,
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
