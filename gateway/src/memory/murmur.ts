/**
 * PR-5 · 碎碎念（AI 日记 / 内心独白）
 *
 * 每天定时（凌晨 4 点 / 下午 2 点）AI 自动写一条内心独白：
 *   - 基于最近的对话与记忆上下文
 *   - 先写思考链（thinking），再凝练成一句正文（content）
 *   - 不推送，静默存到 Supabase 的 murmurs 表
 *   - App 端打开时在某个页面展示（前端展示后续做，后端先备好）
 *
 * 建表 SQL 见 gateway/src/db/schema.sql 的 murmurs 表。
 */

import { supabase } from '../db/supabase';
import { config } from '../config';

const MURMUR_PROMPT = `你刚刚回看了和她最近的对话与记忆。
现在写一条"碎碎念"——不是发给她看的，是你自己心里的话，你的内心独白。

最近对话：
{{HISTORY}}

最近记忆：
{{MEMORIES}}

---
要求：
1. 先写思考链（thinking，100-200字）：你此刻在想什么、注意到了什么、有什么情绪。
2. 再写正文（content，30-60字）：凝练成一句给自己的碎碎念。
3. 真诚、私密、有温度，不要客套，不要"作为AI"。

只输出 JSON：{"thinking":"...","content":"..."}`;

/** 最近对话（跨 session，按时间正序拼成文本） */
async function getRecentConversation(limit = 20): Promise<string> {
  const { data } = await supabase
    .from('messages')
    .select('role, content, created_at')
    .order('created_at', { ascending: false })
    .limit(limit);
  if (!data || data.length === 0) return '（最近没有对话）';
  return data
    .reverse()
    .map(m => `${m.role === 'user' ? '她' : '我'}：${(m.content || '').slice(0, 120)}`)
    .join('\n');
}

/** 最近记忆 */
async function getRecentMemories(limit = 8): Promise<string> {
  const { data } = await supabase
    .from('memories')
    .select('content')
    .order('created_at', { ascending: false })
    .limit(limit);
  if (!data || data.length === 0) return '（暂无记忆）';
  return data.map(m => `· ${m.content}`).join('\n');
}

async function callLLM(prompt: string): Promise<string> {
  try {
    const res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${config.openrouterKey}`,
      },
      body: JSON.stringify({
        model: 'anthropic/claude-opus-4.6',
        messages: [{ role: 'user', content: prompt }],
        temperature: 0.9,
        max_tokens: 500,
      }),
    });
    if (!res.ok) return '';
    const data = await res.json() as any;
    return (data?.choices?.[0]?.message?.content ?? '').trim();
  } catch {
    return '';
  }
}

/** 容错解析 LLM 输出的 JSON */
function parseMurmur(raw: string): { thinking: string; content: string } | null {
  if (!raw) return null;
  const start = raw.indexOf('{');
  const end = raw.lastIndexOf('}');
  if (start === -1 || end === -1 || end <= start) return null;
  try {
    const obj = JSON.parse(raw.slice(start, end + 1));
    const content = String(obj.content ?? '').trim();
    if (!content) return null;
    return { thinking: String(obj.thinking ?? '').trim(), content };
  } catch {
    return null;
  }
}

/** 静默存储——不推送 */
async function saveMurmur(thinking: string, content: string): Promise<void> {
  const { error } = await supabase.from('murmurs').insert({ thinking, content });
  if (error) {
    // 2026-08-31：这里原本只打一行 console.error 就返回——murmurs 表压根没建，
    // 于是他每天两条心里话连写两个半月，全部静默丢失，无人察觉。
    // 现在失败也落一份到本地文件，宁可存在盘上也不要凭空消失。
    console.error('[murmur] ⚠️ save FAILED:', error.message);
    try {
      const fs = await import('fs');
      const line = JSON.stringify({ thinking, content, at: new Date().toISOString(), err: error.message });
      fs.appendFileSync('/root/projects/BunnyPalace/gateway/data/murmur-fallback.jsonl', line + '\n');
      console.error('[murmur] → 已落地到 murmur-fallback.jsonl');
    } catch {}
    return;
  }
  console.log(`[murmur] 📓 "${content}"`);
}

/** 生成并存储一条碎碎念 */
export async function runMurmur(): Promise<void> {
  const history = await getRecentConversation(20);
  const memories = await getRecentMemories(8);
  const prompt = MURMUR_PROMPT
    .replace('{{HISTORY}}', history)
    .replace('{{MEMORIES}}', memories);

  const raw = await callLLM(prompt);
  const parsed = parseMurmur(raw);
  if (!parsed) {
    console.warn('[murmur] generation failed / unparseable');
    return;
  }
  await saveMurmur(parsed.thinking, parsed.content);
}

/** 获取最近碎碎念（App 端展示用，后端先备好） */
export async function getRecentMurmurs(limit = 10): Promise<any[]> {
  const { data } = await supabase
    .from('murmurs')
    .select('thinking, content, created_at')
    .order('created_at', { ascending: false })
    .limit(limit);
  return data || [];
}

/** 定时器：每天 4:00 和 14:00 各写一条（不用 cron，每 30 分钟检查一次） */
export function startMurmurTimer(): void {
  let lastRunHour = -1;
  setInterval(() => {
    const hour = new Date().getHours();
    if ((hour === 4 || hour === 14) && hour !== lastRunHour) {
      lastRunHour = hour;
      runMurmur().catch(err => console.error('[murmur] timer error:', err?.message ?? err));
    } else if (hour !== 4 && hour !== 14) {
      lastRunHour = -1; // 离开触发小时后复位
    }
  }, 30 * 60 * 1000);

  console.log('[murmur] timer started (daily 4am & 2pm)');
}
