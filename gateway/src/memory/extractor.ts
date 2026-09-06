import { supabase } from '../db/supabase';
import { embed } from './embedder';
import { config } from '../config';

/**
 * Phase 3 · 自动记忆提取器
 * 参考粟粟的MemoryExtractor + 兔兔的主记忆/侧翼记忆设计
 *
 * 对话结束后异步触发，用廉价模型分析对话，提取原子记忆
 * 支持 add / update / delete 三种操作
 * 带已有记忆做去重上下文
 */

const EXTRACTION_PROMPT = `你是记忆管理助手。分析最近的对话，决定是否需要更新用户的记忆库。

## 当前记忆
{{MEMORIES}}

## 规则
1. 提取原子事实 — 每条记忆是一个独立的陈述（"喜欢草莓蛋糕"而不是"有各种饮食偏好"）
2. 分类：preference（偏好）、fact（事实）、relationship（人际关系）、goal（目标/项目）、context（当前情境，有时效性）
3. 对每条新信息做出一个判断：
   - add: 全新信息，现有记忆未覆盖
   - update: 已有记忆需要修正或补充 — 提供要更新的记忆 ID
   - delete: 已有记忆被明确否定或过时 — 提供要删除的记忆 ID
   - 不操作: 已充分覆盖，或不值得存储
4. 只存用户明确说出或强烈暗示的信息。不要推断敏感信息。
5. 用简洁的第三人称：「用户喜欢...」而不是「你喜欢...」
6. 需要时加时间限定词：「用户目前在做...」
7. 新旧矛盾时，delete 旧记忆 + add 新版本。
8. 不存：日常闲聊、一次性问题、用户在问（而非陈述）的信息。
9. 判断情感属性：valence(-1到1，负面到正面)和arousal(0到1，平静到激烈)
10. 判断重要程度：tier 1核心 2重要 3普通 4碎片

## 输出格式
只输出 JSON，不要解释：
{"actions": [{"type": "add", "content": "记忆内容", "category": "分类", "tier": 3, "valence": 0, "arousal": 0}, {"type": "update", "id": "记忆ID", "content": "新内容"}, {"type": "delete", "id": "记忆ID"}]}
如果没有需要操作的，输出：{"actions": []}`;

interface MemoryAction {
  type: 'add' | 'update' | 'delete';
  content?: string;
  category?: string;
  tier?: number;
  valence?: number;
  arousal?: number;
  id?: string;
}

/** 构建提取请求 */
function buildExtractionPrompt(existingMemories: any[]): string {
  let memoriesJSON = '无';
  if (existingMemories.length > 0) {
    const items = existingMemories.map(m =>
      `  {"id": "${m.id}", "content": "${m.content}", "category": "${m.category || ''}"}`
    );
    memoriesJSON = `[\n${items.join(',\n')}\n]`;
  }
  return EXTRACTION_PROMPT.replace('{{MEMORIES}}', memoriesJSON);
}

/** 解析LLM返回的JSON */
function parseActions(raw: string): MemoryAction[] {
  // 直接解析
  try {
    const obj = JSON.parse(raw);
    if (obj?.actions && Array.isArray(obj.actions)) return obj.actions;
  } catch {}

  // Fallback: 从文本中提取JSON块
  const match = raw.match(/\{[\s\S]*\}/);
  if (match) {
    try {
      const obj = JSON.parse(match[0]);
      if (obj?.actions && Array.isArray(obj.actions)) return obj.actions;
    } catch {}
  }

  return [];
}

/** 执行提取到的操作 */
async function executeActions(actions: MemoryAction[]): Promise<void> {
  for (const action of actions) {
    try {
      switch (action.type) {
        case 'add':
          if (!action.content) continue;
          // 自动生成embedding向量
          const vec = await embed(action.content);
          const insertData: any = {
            content: action.content,
            category: action.category || 'fact',
            tier: action.tier || 3,
            valence: action.valence || 0,
            arousal: action.arousal || 0,
            heat: 1.0,
            source: 'auto',
          };
          if (vec.length > 0) insertData.embedding = vec;
          await supabase.from('memories').insert(insertData);
          console.log(`[extractor] ADD: ${action.content.slice(0, 50)}`);
          break;

        case 'update':
          if (!action.id || !action.content) continue;
          await supabase.from('memories')
            .update({
              content: action.content,
              updated_at: new Date().toISOString(),
            })
            .eq('id', action.id);
          console.log(`[extractor] UPDATE: ${action.id.slice(0, 8)}`);
          break;

        case 'delete':
          if (!action.id) continue;
          await supabase.from('memories')
            .delete()
            .eq('id', action.id);
          console.log(`[extractor] DELETE: ${action.id.slice(0, 8)}`);
          break;
      }
    } catch (err: any) {
      console.error(`[extractor] action error:`, err.message);
    }
  }
}

/**
 * 主函数：提取记忆（异步，不阻塞对话）
 * 在AI回复完成后被调用
 */
export async function extractMemoriesIfNeeded(
  recentMessages: { role: string; content: string }[],
  model?: string
): Promise<void> {
  // 至少需要2条消息（1轮对话）才提取
  if (recentMessages.length < 2) return;

  try {
    // 获取已有记忆做去重上下文（只取活跃的）
    const { data: existing } = await supabase
      .from('memories')
      .select('id, content, category')
      .gte('heat', 0.05)
      .order('heat', { ascending: false })
      .limit(50);

    const systemPrompt = buildExtractionPrompt(existing || []);

    // 格式化对话
    let conversationText = '';
    for (const msg of recentMessages.slice(-6)) {
      const label = msg.role === 'user' ? '用户' : 'AI';
      conversationText += `${label}: ${msg.content}\n\n`;
    }

    // 调廉价模型
    const extractModel = 'deepseek-chat';
    const apiUrl = 'https://api.deepseek.com/v1/chat/completions';

    const res = await fetch(apiUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${config.deepseekKey}`,
      },
      body: JSON.stringify({
        model: extractModel,
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: `以下是最近的对话，请分析并执行记忆操作：\n\n${conversationText}` },
        ],
        temperature: 0.1,
        max_tokens: 1000,
      }),
    });

    if (!res.ok) {
      console.error(`[extractor] API error: ${res.status}`);
      return;
    }

    const data = await res.json() as any;
    const raw = data?.choices?.[0]?.message?.content ?? '';

    if (!raw) {
      console.log('[extractor] empty response');
      return;
    }

    const actions = parseActions(raw);
    console.log(`[extractor] parsed ${actions.length} actions`);

    if (actions.length > 0) {
      await executeActions(actions);
    }
  } catch (err: any) {
    console.error(`[extractor] failed:`, err.message);
  }
}
