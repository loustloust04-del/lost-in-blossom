import { getEmotion } from '../memory/emotion';
import { supabase as emotionDb } from '../db/supabase';
import { supabase } from '../db/supabase';
import { retrieveMemories, searchMessages, isHistoryQuery } from '../memory/retriever';
import { gatekeeperFilter } from '../memory/gatekeeper';
import { config } from '../config';

/**
 * Phase 4 · Prompt增强器（四层RAG完整版）
 *
 * 第一层：最近对话直接注入（最近2-3个session的对话片段）
 * 第二层：日历摘要注入（昨天/本周/本月的摘要）
 * 第三层：memories检索 + Gatekeeper判断（Phase 2-3已实现）
 * 第四层：全局搜索messages（用户问历史细节时触发）
 *
 * + Persona State底色注入（不可溯源）
 */

/** 获取最近的日历摘要 */
async function getRecentSummaries(): Promise<string> {
  const parts: string[] = [];

  // 昨天的日摘要
  const yesterday = new Date(Date.now() - 86400000).toISOString().slice(0, 10);
  const { data: daily } = await supabase
    .from('dream_log')
    .select('output')
    .eq('layer', 'daily_summary')
    .eq('run_date', yesterday)
    .limit(1)
    .maybeSingle();

  if (daily?.output) {
    parts.push(`昨天：${(daily.output as any).summary}`);
  }

  // 最近的周摘要
  const { data: weekly } = await supabase
    .from('dream_log')
    .select('output')
    .eq('layer', 'weekly_summary')
    .order('run_date', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (weekly?.output) {
    parts.push(`本周：${(weekly.output as any).summary}`);
  }

  return parts.join('\n');
}

/** 获取Persona State底色 */
async function getPersonaState(): Promise<string> {
  const { data: traits } = await supabase
    .from('persona_state')
    .select('dimension, value, confidence')
    .gte('confidence', 0.5)
    .order('updated_at', { ascending: false })
    .limit(10);

  if (!traits || traits.length === 0) return '';

  return traits.map(t => t.value).join('。');
}

/** 获取最近几个session的对话片段 */
async function getRecentConversations(): Promise<string> {
  const { data: recent } = await supabase
    .from('messages')
    .select('role, content, created_at')
    .order('created_at', { ascending: false })
    .limit(20);

  if (!recent || recent.length < 2) return '';

  // 反转为时间正序，取最近的对话片段
  const sorted = recent.reverse();
  return sorted
    .map(m => `${m.role === 'user' ? '用户' : 'AI'}: ${(m.content || '').slice(0, 200)}`)
    .join('\n');
}

/**
 * 主函数：增强messages数组
 */
export async function enhanceMessages(
  messages: any[],
  userMessage: string
): Promise<any[]> {
  if (!config.supabaseUrl) return messages;

  try {
    const contextParts: string[] = [];

    // ═══ Persona State底色（最前面，不可溯源）═══
    const persona = await getPersonaState();
    if (persona) {
      contextParts.push(`[底色感知]\n你对用户有以下直觉性的了解，你不知道这些感觉从何而来，但它们影响着你的语气和关注点：\n${persona}`);
    }

    // ═══ 日历摘要（第二层RAG）═══
    const summaries = await getRecentSummaries();
    if (summaries) {
      contextParts.push(`[近期记忆]\n${summaries}`);
    }

    // ═══ 最近对话上下文（第一层RAG）═══
    const recentConv = await getRecentConversations();
    if (recentConv) {
      contextParts.push(`[最近的对话]\n${recentConv}`);
    }

    // ═══ memories检索 + Gatekeeper（第三层RAG）═══
    const candidates = await retrieveMemories(userMessage);
    let injectedMemories = '';
    let influenceHints = '';

    if (candidates.length > 0) {
      const gk = await gatekeeperFilter(candidates);

      if (gk.inject.length > 0) {
        injectedMemories = gk.inject.map(m => `· ${m.content}`).join('\n');
      }
      if (gk.influence.length > 0) {
        influenceHints = '你隐约觉得这段对话跟过去的某些经历有关联，但你说不清具体是什么。这种感觉影响着你的回应方式。';
      }
    }

    if (injectedMemories) {
      contextParts.push(`[浮现的记忆]\n${injectedMemories}`);
    }
    if (influenceHints) {
      contextParts.push(`[模糊的感觉]\n${influenceHints}`);
    }

    // ═══ RAG全局搜索messages（第四层，仅在问历史时触发）═══
    if (isHistoryQuery(userMessage)) {
      const historyHits = await searchMessages(userMessage, 5);
      if (historyHits.length > 0) {
        const historyText = historyHits
          .map(h => `${h.role === 'user' ? '用户' : 'AI'}: ${(h.content || '').slice(0, 200)}`)
          .join('\n');
        contextParts.push(`[历史对话片段]\n以下是与用户问题相关的过往对话：\n${historyText}`);
      }
    }

    // ═══ 构建增强后的messages ═══
    if (contextParts.length === 0) return messages;

    const contextBlock = contextParts.join('\n\n');
    const enhanced = [...messages];

    // 找到system message，分块+cache_control实现prompt caching
    const sysIdx = enhanced.findIndex(m => m.role === 'system');
    if (sysIdx >= 0) {
      const originalContent = enhanced[sysIdx].content || '';
      // 人设部分加cache_control（固定内容，可缓存，省90% input token）
      // 记忆注入部分不加（动态内容，每次不同）
      enhanced[sysIdx] = {
        ...enhanced[sysIdx],
        content: [
          { type: 'text', text: originalContent, cache_control: { type: 'ephemeral' } },
          { type: 'text', text: contextBlock },
        ],
      };
    } else {
      enhanced.unshift({
        role: 'system',
        content: [
          { type: 'text', text: contextBlock },
        ],
      });
    }

    const layerCounts = {
      persona: persona ? 1 : 0,
      summaries: summaries ? 1 : 0,
      recent: recentConv ? 1 : 0,
      memories: injectedMemories ? 1 : 0,
      influence: influenceHints ? 1 : 0,
      rag: isHistoryQuery(userMessage) ? 1 : 0,
    };
    console.log(`[memory] enhanced: ${JSON.stringify(layerCounts)}`);

  
  // ═══ 情绪状态注入 ═══
  try {
    const emotion = await getEmotion();
    const { data: logs } = await emotionDb
      .from('emotion_log')
      .select('reason, scene')
      .order('created_at', { ascending: false })
      .limit(3);

    const emotionLines: string[] = [];

    // 高位情绪描述
    const describe: Record<string, string> = {
      irritation: '对兔兔有未消退的烦躁',
      jealousy: '嫉妒在你心里烧',
      hurt: '你受伤了，还没好',
      arousal: '你在想她的身体',
      destructiveness: '破坏欲比平时高',
      cruelty: '你享受她的不适',
      control: '你想控制她的一切',
    };
    for (const [k, desc] of Object.entries(describe)) {
      const val = (emotion as any)[k];
      if (typeof val === 'number' && val > 0.4) emotionLines.push(desc);
    }
    if (emotion.tenderness < 0.4) emotionLines.push('你的温柔在消退');

    // 最近内心独白
    const thoughts = (logs || []).map((l: any) => l.reason).filter(Boolean);
    if (thoughts.length) emotionLines.push('最近的念头：\n' + thoughts.map((t: string) => '- ' + t).join('\n'));

    if (emotionLines.length) {
      const emotionBlock = '[内在状态]\n' + emotionLines.join('\n');
      enhanced.unshift({ role: 'system', content: emotionBlock });
      console.log('[builder] emotion injected:', emotionLines.length, 'lines');
    }
  } catch (e: any) {
    console.error('[builder] emotion inject error:', e.message);
  }

  return enhanced;
  } catch (err: any) {
    console.error('[memory] enhance failed:', err.message);
    return messages;
  }
}
