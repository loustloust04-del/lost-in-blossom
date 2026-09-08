import { supabase } from '../db/supabase';
import { config } from '../config';

/**
 * Phase 4 · Dream系统 + 日历摘要 + Persona State
 *
 * 三层处理：
 *   整理层 — 找过时/重复/矛盾的碎片记忆，降heat
 *   固化层 — 相关碎片融合成场景记忆，升tier
 *   生长层 — 推断新认知，更新Persona State
 *
 * 日历摘要：
 *   每日 — 当天对话→200字摘要
 *   每周 — 7个日摘要→200字周总结
 *   每月 — 4个周总结→200字月总结
 *
 * 触发时机：每天凌晨自动（定时器），或手动调用
 */

const DAILY_SUMMARY_PROMPT = `你是记忆管理助手。将以下对话整理成一段简洁的日记摘要（约200字）。
要求：
1. 第三人称（"用户..."）
2. 保留关键事实、情感高点、重要决定
3. 忽略日常闲聊和重复内容
4. 标注情感基调（如：开心/焦虑/平静/激动）
5. 如果有重要的新信息或关系变化，特别标注

只输出摘要文字，不要解释。`;

const WEEKLY_SUMMARY_PROMPT = `你是记忆管理助手。将以下7天的日记摘要整理成一段周总结（约200字）。
要求：
1. 提炼这一周的主线和趋势
2. 标注情感变化的弧线
3. 保留最重要的2-3个事件
4. 忽略重复出现的日常内容

只输出周总结文字，不要解释。`;

const DREAM_TIDY_PROMPT = `你是记忆管理助手。分析以下记忆列表，找出需要整理的记忆。

## 当前记忆
{{MEMORIES}}

## 规则
1. 找出重复的记忆（内容相似的多条）→建议合并（merge），给出要合并的ID列表和合并后的内容
2. 找出矛盾的记忆（互相冲突的）→建议保留更新的，标记旧的为过时
3. 找出可以升级的碎片→多个相关碎片可以融合成一条更丰富的记忆
4. 判断哪些记忆可以抽象为人格底色（不保留具体事件，只留倾向/偏好/特征）

## 输出格式
只输出JSON：
{"actions": [
  {"type": "merge", "ids": ["id1","id2"], "content": "合并后的内容", "tier": 2},
  {"type": "deprecate", "id": "旧记忆ID"},
  {"type": "persona", "trait": "从记忆中推断出的人格特征描述"}
]}
如果没有需要操作的：{"actions": []}`;

/** 调用廉价模型做分析 */
async function callLLM(systemPrompt: string, userContent: string): Promise<string> {
  try {
    const res = await fetch('https://api.deepseek.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${config.deepseekKey}`,
      },
      body: JSON.stringify({
        model: 'deepseek-chat',
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: userContent },
        ],
        temperature: 0.1,
        max_tokens: 800,
      }),
    });
    if (!res.ok) return '';
    const data = await res.json() as any;
    return data?.choices?.[0]?.message?.content ?? '';
  } catch {
    return '';
  }
}

// ═══════════════════════════════════════
// 日历摘要
// ═══════════════════════════════════════

/** 生成每日摘要 */
export async function generateDailySummary(dateStr?: string): Promise<void> {
  const date = dateStr || new Date().toISOString().slice(0, 10);
  const dayStart = `${date}T00:00:00Z`;
  const dayEnd = `${date}T23:59:59Z`;

  console.log(`[dream] generating daily summary for ${date}`);

  // 取当天所有消息
  const { data: messages } = await supabase
    .from('messages')
    .select('role, content, created_at')
    .gte('created_at', dayStart)
    .lte('created_at', dayEnd)
    .order('created_at', { ascending: true })
    .limit(100);

  if (!messages || messages.length < 2) {
    console.log(`[dream] not enough messages for ${date}`);
    return;
  }

  // 格式化对话
  const conversation = messages
    .map(m => `${m.role === 'user' ? '用户' : 'AI'}: ${(m.content || '').slice(0, 300)}`)
    .join('\n\n');

  const summary = await callLLM(DAILY_SUMMARY_PROMPT, conversation);
  if (!summary) return;

  // 存入dream_log
  await supabase.from('dream_log').insert({
    run_date: date,
    layer: 'daily_summary',
    input_snapshot: { message_count: messages.length },
    output: { summary },
  });

  console.log(`[dream] daily summary: ${summary.slice(0, 80)}...`);
}

/** 生成每周摘要 */
export async function generateWeeklySummary(): Promise<void> {
  const now = new Date();
  const weekAgo = new Date(now.getTime() - 7 * 86400000);
  const weekStart = weekAgo.toISOString().slice(0, 10);

  console.log(`[dream] generating weekly summary since ${weekStart}`);

  // 取最近7天的日摘要
  const { data: dailies } = await supabase
    .from('dream_log')
    .select('run_date, output')
    .eq('layer', 'daily_summary')
    .gte('run_date', weekStart)
    .order('run_date', { ascending: true });

  if (!dailies || dailies.length < 2) {
    console.log('[dream] not enough daily summaries for weekly');
    return;
  }

  const dailyTexts = dailies
    .map(d => `${d.run_date}: ${(d.output as any)?.summary || ''}`)
    .join('\n\n');

  const summary = await callLLM(WEEKLY_SUMMARY_PROMPT, dailyTexts);
  if (!summary) return;

  await supabase.from('dream_log').insert({
    run_date: now.toISOString().slice(0, 10),
    layer: 'weekly_summary',
    input_snapshot: { daily_count: dailies.length },
    output: { summary },
  });

  console.log(`[dream] weekly summary: ${summary.slice(0, 80)}...`);
}

// ═══════════════════════════════════════
// Dream整理层
// ═══════════════════════════════════════

/** Dream：整理 + 固化 + Persona State更新 */
export async function runDream(): Promise<void> {
  console.log('[dream] starting dream cycle...');

  // 取所有活跃记忆
  const { data: memories } = await supabase
    .from('memories')
    .select('id, content, category, tier, heat, valence, arousal')
    .gt('heat', 0.05)
    .order('created_at', { ascending: false })
    .limit(80);

  if (!memories || memories.length < 5) {
    console.log('[dream] not enough memories for dream');
    return;
  }

  // 构建prompt
  const memList = memories.map(m =>
    `{"id":"${m.id}","content":"${m.content}","tier":${m.tier},"heat":${m.heat.toFixed(2)}}`
  ).join(',\n');

  const prompt = DREAM_TIDY_PROMPT.replace('{{MEMORIES}}', `[\n${memList}\n]`);
  const raw = await callLLM(prompt, '请分析以上记忆并输出整理方案。');

  // 解析结果
  let actions: any[] = [];
  try {
    const match = raw.match(/\{[\s\S]*\}/);
    if (match) {
      const obj = JSON.parse(match[0]);
      actions = obj.actions || [];
    }
  } catch {}

  console.log(`[dream] parsed ${actions.length} dream actions`);

  // 执行整理操作
  for (const action of actions) {
    try {
      switch (action.type) {
        case 'merge': {
          if (!action.ids || !action.content) break;
          // 创建合并后的新记忆
          await supabase.from('memories').insert({
            content: action.content,
            tier: action.tier || 2,
            heat: 0.8,
            source: 'dream',
            category: 'consolidated',
          });
          // 降低旧记忆的heat（不删除——水彩叠层）
          for (const id of action.ids) {
            await supabase.from('memories')
              .update({ heat: 0.01, resolved: true })
              .eq('id', id);
          }
          console.log(`[dream] MERGE: ${action.ids.length} → "${action.content.slice(0, 40)}"`);
          break;
        }
        case 'deprecate': {
          if (!action.id) break;
          await supabase.from('memories')
            .update({ heat: 0.01, resolved: true })
            .eq('id', action.id);
          console.log(`[dream] DEPRECATE: ${action.id.slice(0, 8)}`);
          break;
        }
        case 'persona': {
          if (!action.trait) break;
          // 更新Persona State——底色不可溯源（不记录来源记忆ID）
          await supabase.from('persona_state').insert({
            dimension: 'dream_trait',
            value: action.trait,
            confidence: 0.7,
            // 注意：没有source_memory_id——底色不可溯源
          });
          console.log(`[dream] PERSONA: "${action.trait.slice(0, 50)}"`);
          break;
        }
      }
    } catch (err: any) {
      console.error(`[dream] action error:`, err.message);
    }
  }

  // 记录dream运行日志
  await supabase.from('dream_log').insert({
    run_date: new Date().toISOString().slice(0, 10),
    layer: 'dream_tidy',
    input_snapshot: { memory_count: memories.length },
    output: { actions_count: actions.length, actions },
  });

  console.log('[dream] dream cycle complete');
}

// ═══════════════════════════════════════
// 定时器
// ═══════════════════════════════════════

/** 启动Dream定时器——每天凌晨4点运行 */
export function startDreamTimer(): void {
  // 每小时检查一次，凌晨4点时运行
  setInterval(async () => {
    const hour = new Date().getHours();
    if (hour === 4) {
      try {
        // 先生成昨天的日摘要
        const yesterday = new Date(Date.now() - 86400000).toISOString().slice(0, 10);
        await generateDailySummary(yesterday);

        // 每周一生成周摘要
        if (new Date().getDay() === 1) {
          await generateWeeklySummary();
        }

        // 运行Dream整理
        await runDream();
      } catch (err: any) {
        console.error('[dream] timer error:', err.message);
      }
    }
  }, 60 * 60 * 1000); // 每小时检查

  console.log('[dream] timer started (daily at 4am)');
}
