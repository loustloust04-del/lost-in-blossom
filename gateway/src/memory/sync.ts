// 记忆系统 API 的查询/对齐逻辑 —— 供 app.ts 的 /api/memories/* 端点调用。
// 单独成文件，尽量不动 app.ts 主体（降低与并行改动的合并冲突）。
import { supabase } from '../db/supabase';
import { embed } from './embedder';
import { saveMemory } from './store';

const MEMORY_FIELDS =
  'id, content, tier, category, valence, arousal, heat, is_anchor, is_pinned, resolved, source, created_at, updated_at';

export interface ListOpts {
  limit: number;
  offset: number;
  category?: string;
}

// 给每条记忆附上最近一次 gatekeeper 判定（inject / influence / suppress），供 App 标注。
async function attachGatekeeper(items: any[]): Promise<any[]> {
  if (!items.length) return items;
  const ids = items.map((m) => m.id);
  const { data } = await supabase
    .from('gatekeeper_log')
    .select('memory_id, decision, created_at')
    .in('memory_id', ids)
    .order('created_at', { ascending: false });
  const latest = new Map<string, string>();
  for (const row of data ?? []) {
    if (!latest.has(row.memory_id)) latest.set(row.memory_id, row.decision);
  }
  return items.map((m) => ({ ...m, gatekeeper: latest.get(m.id) ?? null }));
}

// 全部记忆（置顶 > 热度 > 时间），分页 + 可选 category 筛选。
export async function listMemories(opts: ListOpts) {
  let q = supabase
    .from('memories')
    .select(MEMORY_FIELDS, { count: 'exact' })
    .order('is_pinned', { ascending: false })
    .order('heat', { ascending: false })
    .order('created_at', { ascending: false })
    .range(opts.offset, opts.offset + opts.limit - 1);
  if (opts.category) q = q.eq('category', opts.category);
  const { data, error, count } = await q;
  if (error) {
    console.error('[mem-api] listMemories error:', error.message);
    return { items: [] as any[], total: 0 };
  }
  const items = await attachGatekeeper(data ?? []);
  return { items, total: count ?? 0 };
}

// 做梦日记（日/周/月摘要）。兼容两种历史 schema：
//   新：run_date / layer('daily_summary'...) / output:{summary}
//   旧：dream_type / output_summary
export async function listDreams(period?: string) {
  const { data, error } = await supabase
    .from('dream_log')
    .select('*')
    .order('created_at', { ascending: false })
    .limit(200);
  if (error) {
    console.error('[mem-api] listDreams error:', error.message);
    return { items: [] as any[] };
  }
  const norm = (r: any) => {
    const layer = r.layer || r.dream_type || 'daily';
    return {
      id: r.id,
      date: r.run_date || (r.created_at ? String(r.created_at).slice(0, 10) : null),
      layer,
      summary: r.output?.summary ?? r.output_summary ?? '',
      created_at: r.created_at,
    };
  };
  let items = (data ?? []).map(norm);
  if (period) {
    const want = period.toLowerCase();
    items = items.filter((d) => String(d.layer || '').toLowerCase().includes(want));
  }
  return { items };
}

// 欲望系统生成的念头：存在 messages 表，session_id='desire'。
export async function listDesires(limit = 50, offset = 0) {
  const { data, error } = await supabase
    .from('messages')
    .select('id, content, created_at')
    .eq('session_id', 'desire')
    .eq('role', 'assistant')
    .order('created_at', { ascending: false })
    .range(offset, offset + limit - 1);
  if (error) {
    console.error('[mem-api] listDesires error:', error.message);
    return { items: [] as any[] };
  }
  return { items: data ?? [] };
}

// ============ 对齐：App → 网关 ============

const DEDUP_THRESHOLD = 0.8;

export interface IncomingMemory {
  content: string;
  category?: string;
  tier?: number;
  valence?: number;
  arousal?: number;
}

// content 相似度 > 0.8 视为重复。有向量走 match_memories；无向量退化为精确文本匹配。
export async function isDuplicate(content: string): Promise<boolean> {
  const emb = await embed(content);
  if (emb.length === 0) {
    const { data } = await supabase
      .from('memories')
      .select('id')
      .eq('content', content)
      .limit(1);
    return (data?.length ?? 0) > 0;
  }
  const { data } = await supabase.rpc('match_memories', {
    query_embedding: emb,
    match_threshold: DEDUP_THRESHOLD,
    match_count: 1,
  });
  return (data?.length ?? 0) > 0 && (data[0]?.similarity ?? 0) >= DEDUP_THRESHOLD;
}

// 接收 App 端手动写入的记忆，去重后合并入库。source='manual'。
export async function syncMemories(incoming: IncomingMemory[]) {
  let added = 0;
  let skipped = 0;
  const addedIds: string[] = [];
  for (const m of incoming) {
    const content = String(m?.content || '').trim();
    if (!content) {
      skipped++;
      continue;
    }
    if (await isDuplicate(content)) {
      skipped++;
      continue;
    }
    const t = Number(m?.tier);
    const tier = Number.isFinite(t) && t >= 1 && t <= 4 ? Math.round(t) : 3;
    const id = await saveMemory({
      content,
      category: m?.category,
      tier,
      valence: m?.valence,
      arousal: m?.arousal,
      source: 'manual',
    });
    if (id) {
      added++;
      addedIds.push(id);
    } else {
      skipped++;
    }
  }
  return { added, skipped, addedIds };
}

// ============ 对齐：网关 → App ============

// 网关有、App 可能没有的记忆。App 传 since(ms) 做增量拉取（按 updated_at）。
export async function diffMemories(sinceMs?: number, limit = 200) {
  let q = supabase
    .from('memories')
    .select(MEMORY_FIELDS)
    .order('updated_at', { ascending: false })
    .limit(limit);
  if (sinceMs && !Number.isNaN(sinceMs)) {
    q = q.gt('updated_at', new Date(sinceMs).toISOString());
  }
  const { data, error } = await q;
  if (error) {
    console.error('[mem-api] diffMemories error:', error.message);
    return { items: [] as any[] };
  }
  return { items: data ?? [] };
}
