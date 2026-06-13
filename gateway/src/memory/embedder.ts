import { config } from '../config';

export async function embed(text: string): Promise<number[]> {
  // 没配嵌入API就跳过，让关键词搜索兜底
  if (!config.embeddingKey || config.embeddingKey.length < 10) {
    return [];
  }

  try {
    const res = await fetch(`${config.embeddingBase}/embeddings`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${config.embeddingKey}`,
      },
      body: JSON.stringify({ model: config.embeddingModel, input: text }),
    });
    if (!res.ok) return [];
    const data = await res.json() as any;
    return data?.data?.[0]?.embedding ?? [];
  } catch {
    return [];
  }
}

export async function embedBatch(texts: string[]): Promise<number[][]> {
  if (!config.embeddingKey || config.embeddingKey.length < 10) {
    return texts.map(() => []);
  }
  try {
    const res = await fetch(`${config.embeddingBase}/embeddings`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${config.embeddingKey}`,
      },
      body: JSON.stringify({ model: config.embeddingModel, input: texts }),
    });
    if (!res.ok) return texts.map(() => []);
    const data = await res.json() as any;
    return (data?.data ?? []).map((d: any) => d.embedding ?? []);
  } catch {
    return texts.map(() => []);
  }
}
