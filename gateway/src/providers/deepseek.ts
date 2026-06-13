import { config } from '../config';

const BASE = 'https://api.deepseek.com/v1/chat/completions';

// DeepSeek renamed models in 2026: deepseek-chat → deepseek-v4-pro, deepseek-reasoner → deepseek-r1-0528
const MODEL_MAP: Record<string, string> = {
  'deepseek-chat': 'deepseek-v4-pro',
  'deepseek/deepseek-chat': 'deepseek-v4-pro',
  'deepseek-reasoner': 'deepseek-r1-0528',
  'deepseek/deepseek-reasoner': 'deepseek-r1-0528',
};

export async function forwardDeepSeek(body: any): Promise<Response> {
  const rawModel = body.model || '';
  const mapped = MODEL_MAP[rawModel] || rawModel.replace('deepseek/', '');
  console.log(`[deepseek] ${rawModel} → ${mapped}, stream: ${body.stream}`);

  const upstream = await fetch(BASE, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${config.deepseekKey}`,
    },
    body: JSON.stringify({ ...body, model: mapped }),
  });
  return new Response(upstream.body, {
    status: upstream.status,
    headers: {
      'Content-Type': upstream.headers.get('Content-Type') || 'text/event-stream',
      'Cache-Control': 'no-cache',
    },
  });
}
