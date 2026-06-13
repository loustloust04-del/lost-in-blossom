import { supabase } from '../db/supabase';
import { embed } from './embedder';

// ============ 对话历史 ============

export async function saveMessage(
  sessionId: string,
  role: 'user' | 'assistant',
  content: string,
  model?: string
) {
  const { error } = await supabase.from('messages').insert({
    session_id: sessionId,
    role,
    content,
    model,
  });
  if (error) console.error('[store] saveMessage error:', error.message);
}

export async function getRecentMessages(sessionId: string, limit = 20) {
  const { data, error } = await supabase
    .from('messages')
    .select('role, content, created_at')
    .eq('session_id', sessionId)
    .order('created_at', { ascending: false })
    .limit(limit);

  if (error) {
    console.error('[store] getRecentMessages error:', error.message);
    return [];
  }
  return (data ?? []).reverse();
}

// ============ 记忆 CRUD ============

export async function saveMemory(opts: {
  content: string;
  tier?: number;
  category?: string;
  valence?: number;
  arousal?: number;
  source?: string;
  sourceMessageId?: string;
}) {
  // 生成向量嵌入
  const embedding = await embed(opts.content);

  const { data, error } = await supabase.from('memories').insert({
    content: opts.content,
    tier: opts.tier ?? 3,
    category: opts.category,
    valence: opts.valence ?? 0,
    arousal: opts.arousal ?? 0,
    source: opts.source ?? 'auto',
    source_message_id: opts.sourceMessageId,
    embedding: embedding.length > 0 ? embedding : null,
  }).select('id').single();

  if (error) console.error('[store] saveMemory error:', error.message);
  return data?.id;
}

export async function activateMemory(memoryId: string) {
  const { error } = await supabase.rpc('activate_memory', {
    mem_id: memoryId,
  });
  if (error) console.error('[store] activateMemory error:', error.message);
}

// ============ 年轮（水彩叠层） ============

export async function addRing(memoryId: string, content: string) {
  const { error } = await supabase.from('memory_rings').insert({
    memory_id: memoryId,
    content,
  });
  if (error) console.error('[store] addRing error:', error.message);
}

export async function getRings(memoryId: string) {
  const { data, error } = await supabase
    .from('memory_rings')
    .select('content, created_at')
    .eq('memory_id', memoryId)
    .order('created_at', { ascending: true });

  return data ?? [];
}

// ============ 日历标记 ============

export async function getTodayMarkers() {
  const today = new Date();
  const mmdd = `${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;

  const { data, error } = await supabase
    .from('calendar_markers')
    .select('*')
    .or(`marker_date.eq.${today.toISOString().split('T')[0]},recurring.eq.true`);

  if (error) {
    console.error('[store] getTodayMarkers error:', error.message);
    return [];
  }

  // 过滤周年日期（月-日匹配）
  return (data ?? []).filter(m => {
    const mDate = new Date(m.marker_date);
    return mDate.getMonth() === today.getMonth() && mDate.getDate() === today.getDate();
  });
}

// ============ Persona State（底色层） ============

export async function getPersonaState() {
  const { data, error } = await supabase
    .from('persona_state')
    .select('dimension, value, confidence')
    .order('confidence', { ascending: false });

  return data ?? [];
}

// ═══════════════════════════════════════
// 消息有损压缩 — 图片和工具调用结果的轻量化存储
// ═══════════════════════════════════════

/** 检测并压缩消息内容（存储前调用） */
export function compressForStorage(content: string): {
  compressed: string;
  needsVisionSummary: boolean;
  originalSize: number;
} {
  const originalSize = content.length;
  let compressed = content;
  let needsVisionSummary = false;

  // 1. 检测base64图片——替换为占位符
  // base64图片通常以 data:image/ 开头或者是很长的无空格字符串
  const base64Pattern = /data:image\/[^;]+;base64,[A-Za-z0-9+/=]{100,}/g;
  if (base64Pattern.test(compressed)) {
    compressed = compressed.replace(base64Pattern, '[图片：已提取描述，原始数据已压缩]');
    needsVisionSummary = true;
  }

  // 2. 检测工具调用结果——大JSON块替换为摘要
  // 工具结果通常是很长的JSON字符串
  const jsonBlockPattern = /\{[\s\S]{500,}\}/g;
  const jsonMatches = compressed.match(jsonBlockPattern);
  if (jsonMatches) {
    for (const block of jsonMatches) {
      try {
        const parsed = JSON.parse(block);
        // 如果是工具调用结果，提取关键信息
        if (parsed.type === 'tool_result' || parsed.tool_use_id || parsed.output) {
          const summary = `[工具调用结果：${JSON.stringify(parsed).slice(0, 150)}...]`;
          compressed = compressed.replace(block, summary);
        }
      } catch {
        // 不是有效JSON，跳过
      }
    }
  }

  // 3. 截断过长的单条消息（超过3000字的保留前后各1000字）
  if (compressed.length > 3000) {
    const head = compressed.slice(0, 1200);
    const tail = compressed.slice(-800);
    compressed = `${head}\n\n[...内容过长，中间部分已省略...]\n\n${tail}`;
  }

  if (compressed.length < originalSize) {
    console.log(`[compress] ${originalSize} → ${compressed.length} chars (saved ${Math.round((1 - compressed.length/originalSize) * 100)}%)`);
  }

  return { compressed, needsVisionSummary, originalSize };
}

/**
 * 异步生成图片描述（如果消息包含图片）
 * 调用轻量模型描述图片内容，回填到messages表
 */
export async function generateImageDescription(
  messageId: string,
  imageData: string
): Promise<void> {
  // TODO: 调用视觉模型（如gpt-4o-mini with vision）描述图片
  // 生成的描述替换messages表中的占位符
  // 暂时用占位——等配好视觉模型再启用
  console.log(`[compress] image description pending for message ${messageId}`);
}
