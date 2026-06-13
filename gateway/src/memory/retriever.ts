import { supabase } from '../db/supabase';
import { embed } from './embedder';
import { getTodayMarkers } from './store';

/**
 * Phase 3 · 两层检索器（兔兔的主记忆/侧翼记忆设计）
 *
 * 第一层：确定性检索 → 主记忆（直接匹配，一定想得起来）
 * 第二层：扩散激活 → 侧翼记忆（被主记忆牵动，概率性浮现）
 *   - 时间侧翼：主记忆创建时间附近的其他记忆
 *   - 情感侧翼：跟主记忆情感色调相似的其他记忆
 *
 * 主记忆跳过Gatekeeper直接注入
 * 侧翼记忆经过Gatekeeper掷骰子
 */

interface MemoryCandidate {
  id: string;
  content: string;
  tier: number;
  heat: number;
  valence: number;
  arousal: number;
  is_anchor: boolean;
  is_pinned: boolean;
  similarity?: number;
  boosted?: boolean;
  is_primary?: boolean;   // 主记忆标记
  is_flanking?: boolean;  // 侧翼标记
  flank_type?: 'temporal' | 'emotional'; // 侧翼类型
}

/** 中文友好的关键词提取——双字滑动窗口 */
function extractKeywords(text: string): string[] {
  const clean = text.replace(/[。，！？、；：""''（）\[\]【】\s\n\r\t.!?,;:'"()\-]+/g, '');
  const stopChars = new Set('的了吗呢吧呀啊哦嗯是在有不也很都把被让我你他她它们这那什么怎样如何可以知道');
  const bigrams: string[] = [];
  for (let i = 0; i < clean.length - 1; i++) {
    const bi = clean.slice(i, i + 2);
    if (!stopChars.has(bi[0]) && !stopChars.has(bi[1])) {
      bigrams.push(bi);
    }
  }
  return [...new Set(bigrams)].slice(0, 10);
}

export async function retrieveMemories(
  query: string,
  limit = 12
): Promise<MemoryCandidate[]> {
  const primaryMap: Map<string, MemoryCandidate> = new Map();
  const flankingMap: Map<string, MemoryCandidate> = new Map();

  // ═══════════════════════════════════════
  // 第一层：确定性检索 → 主记忆
  // ═══════════════════════════════════════

  // 1a. 向量搜索
  const queryEmbedding = await embed(query);
  if (queryEmbedding.length > 0) {
    const { data: vectorHits } = await supabase.rpc('match_memories', {
      query_embedding: queryEmbedding,
      match_threshold: 0.55,
      match_count: 6,
    });
    for (const hit of vectorHits ?? []) {
      primaryMap.set(hit.id, { ...hit, similarity: hit.similarity, is_primary: true });
    }
  }

  // 1b. 关键词搜索
  const keywords = extractKeywords(query);
  console.log('[retriever] keywords:', keywords.join(', '));

  if (keywords.length > 0) {
    const orFilter = keywords.map(k => `content.ilike.%${k}%`).join(',');
    const { data: keywordHits } = await supabase
      .from('memories')
      .select('id, content, tier, heat, valence, arousal, is_anchor, is_pinned, created_at')
      .or(orFilter)
      .order('heat', { ascending: false })
      .limit(6);

    for (const hit of keywordHits ?? []) {
      if (!primaryMap.has(hit.id)) {
        primaryMap.set(hit.id, { ...hit, similarity: 0.5, is_primary: true });
      }
    }
    console.log('[retriever] keyword hits:', keywordHits?.length ?? 0);
  }

  // 1c. 锚点记忆始终在场
  const { data: anchors } = await supabase
    .from('memories')
    .select('id, content, tier, heat, valence, arousal, is_anchor, is_pinned, created_at')
    .eq('is_anchor', true)
    .limit(3);
  for (const a of anchors ?? []) {
    if (!primaryMap.has(a.id)) {
      primaryMap.set(a.id, { ...a, similarity: 0.3, is_primary: true });
    }
  }

  const primaryResults = Array.from(primaryMap.values());
  console.log('[retriever] primary memories:', primaryResults.length);

  // ═══════════════════════════════════════
  // 第二层：扩散激活 → 侧翼记忆
  // ═══════════════════════════════════════

  if (primaryResults.length > 0) {
    const primaryIds = new Set(primaryResults.map(m => m.id));

    // 2a. 时间侧翼：主记忆时间附近±7天的其他记忆
    for (const primary of primaryResults.slice(0, 3)) {
      const pCreated = (primary as any).created_at;
      if (!pCreated) continue;
      const date = new Date(pCreated);
      const before = new Date(date.getTime() - 7 * 86400000).toISOString();
      const after = new Date(date.getTime() + 7 * 86400000).toISOString();

      const { data: temporal } = await supabase
        .from('memories')
        .select('id, content, tier, heat, valence, arousal, is_anchor, is_pinned')
        .gte('created_at', before)
        .lte('created_at', after)
        .neq('id', primary.id)
        .order('heat', { ascending: false })
        .limit(3);

      for (const t of temporal ?? []) {
        if (!primaryIds.has(t.id) && !flankingMap.has(t.id)) {
          flankingMap.set(t.id, {
            ...t, similarity: 0.3, is_flanking: true, flank_type: 'temporal'
          });
        }
      }
    }

    // 2b. 情感侧翼：Russell坐标距离相近的记忆
    for (const primary of primaryResults.slice(0, 3)) {
      const v = primary.valence;
      const a = primary.arousal;
      const vRange = 0.3;
      const aRange = 0.3;

      const { data: emotional } = await supabase
        .from('memories')
        .select('id, content, tier, heat, valence, arousal, is_anchor, is_pinned')
        .gte('valence', v - vRange)
        .lte('valence', v + vRange)
        .gte('arousal', a - aRange)
        .lte('arousal', a + aRange)
        .neq('id', primary.id)
        .order('heat', { ascending: false })
        .limit(3);

      for (const e of emotional ?? []) {
        if (!primaryIds.has(e.id) && !flankingMap.has(e.id)) {
          flankingMap.set(e.id, {
            ...e, similarity: 0.25, is_flanking: true, flank_type: 'emotional'
          });
        }
      }
    }
  }

  const flankingResults = Array.from(flankingMap.values());
  console.log('[retriever] flanking memories:', flankingResults.length,
    `(temporal: ${flankingResults.filter(f => f.flank_type === 'temporal').length},`,
    `emotional: ${flankingResults.filter(f => f.flank_type === 'emotional').length})`);

  // ═══════════════════════════════════════
  // 日历加成
  // ═══════════════════════════════════════
  const todayMarkers = await getTodayMarkers();
  const boostedIds = new Set(todayMarkers.flatMap(m => m.related_memory_ids ?? []));
  const boostAmount = todayMarkers.reduce((max, m) => Math.max(max, m.emotion_boost ?? 0), 0);

  const allResults = [...primaryResults, ...flankingResults];
  for (const r of allResults) {
    if (boostedIds.has(r.id)) { r.heat += boostAmount; r.boosted = true; }
  }

  // 排序：主记忆优先，然后按综合分
  allResults.sort((a, b) => {
    if (a.is_primary && !b.is_primary) return -1;
    if (!a.is_primary && b.is_primary) return 1;
    if (a.is_anchor && !b.is_anchor) return -1;
    if (!a.is_anchor && b.is_anchor) return 1;
    const tierScore = (t: number) => [0, 1.0, 0.7, 0.4, 0.2][t] ?? 0.3;
    const scoreA = (a.similarity ?? 0) * 0.4 + a.heat * 0.3 + tierScore(a.tier) * 0.3;
    const scoreB = (b.similarity ?? 0) * 0.4 + b.heat * 0.3 + tierScore(b.tier) * 0.3;
    return scoreB - scoreA;
  });

  console.log('[retriever] total candidates:', allResults.length);
  return allResults.slice(0, limit);
}

// ═══════════════════════════════════════
// RAG · 全局搜索messages表（四层架构第四层）
// ═══════════════════════════════════════

/** 检测用户是否在问历史细节 */
function isHistoryQuery(text: string): boolean {
  const markers = ['之前', '上次', '我们聊过', '我们讨论', '我说过', '你说过',
    '记不记得', '还记得', '那次', '以前', '过去', '历史', '之前说',
    '讲过', '提到过', '前几天', '昨天说', '上周'];
  return markers.some(m => text.includes(m));
}

/** 搜索messages表的历史对话 */
export async function searchMessages(
  query: string,
  limit = 5
): Promise<{ role: string; content: string; created_at: string }[]> {
  const keywords = extractKeywords(query);
  if (keywords.length === 0) return [];

  const orFilter = keywords.map(k => `content.ilike.%${k}%`).join(',');
  const { data, error } = await supabase
    .from('messages')
    .select('role, content, created_at')
    .or(orFilter)
    .order('created_at', { ascending: false })
    .limit(limit * 2); // 多取一些，后面按对话对配对

  if (error || !data) return [];

  console.log(`[rag] messages search: ${data.length} hits for "${keywords.join(', ')}"`);
  return data.slice(0, limit);
}

export { isHistoryQuery };
