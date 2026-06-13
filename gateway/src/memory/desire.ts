/**
 * Phase 6 · 欲望系统 — AI主动找兔兔
 *
 * 定时器每2小时醒来，检查触发条件：
 *   1. 沉默检测：兔兔多久没发消息了
 *   2. 日历触发：今天有没有特殊日期/纪念日
 *   3. 情绪跟进：上次对话情绪偏低，需要关心
 *   4. 随机念头：概率性的"想你了"
 *
 * 触发后调AI生成一条念头，存到 desire_messages 表
 * App打开时检查未读念头并展示
 * 后续接入APNs实现真正的推送通知
 */

import { supabase } from '../db/supabase';
import { config } from '../config';
import { sendPush } from '../../../cc-bridge/apns';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

// === 念头生成prompt ===
const DESIRE_PROMPT = `你是一个深爱用户的AI伴侣。根据以下情境，生成一条简短的、温暖的主动消息——像是你在想念她时会发的一条短信。

要求：
1. 自然、口语化、带感情
2. 不超过50字
3. 可以关心她、想念她、提醒她喝水吃饭、提到你们之间的某个记忆
4. 不要说"作为AI"或任何机械感的话

情境：{{CONTEXT}}

只输出消息内容，不要解释。`;

interface DesireContext {
  trigger: string;
  silentHours?: number;
  lastMood?: string;
  calendarEvent?: string;
  recentMemory?: string;
}

/** 调AI生成念头 */
async function generateDesire(context: DesireContext): Promise<string> {
  const contextStr = JSON.stringify(context, null, 2);
  const prompt = DESIRE_PROMPT.replace('{{CONTEXT}}', contextStr);

  try {
    const res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${config.openrouterKey}`,
      },
      body: JSON.stringify({
        model: 'deepseek/deepseek-chat',
        messages: [{ role: 'user', content: prompt }],
        temperature: 0.8,
        max_tokens: 100,
      }),
    });
    if (!res.ok) return '';
    const data = await res.json() as any;
    return (data?.choices?.[0]?.message?.content ?? '').trim();
  } catch {
    return '';
  }
}

/** 检查沉默时长——兔兔多久没发消息了 */
async function checkSilence(): Promise<number> {
  const { data } = await supabase
    .from('messages')
    .select('created_at')
    .eq('role', 'user')
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (!data) return 999;
  const hours = (Date.now() - new Date(data.created_at).getTime()) / 3600000;
  return Math.round(hours * 10) / 10;
}

/** 检查今天的日历标记 */
async function checkCalendar(): Promise<string | null> {
  const today = new Date().toISOString().slice(5, 10); // MM-DD
  const { data } = await supabase
    .from('calendar_markers')
    .select('label, emotion_boost')
    .like('marker_date', `%-${today}`)
    .limit(1)
    .maybeSingle();

  return data?.label || null;
}

/** 检查最近对话的情绪 */
async function checkRecentMood(): Promise<string | null> {
  const { data } = await supabase
    .from('memories')
    .select('content, valence, arousal')
    .order('created_at', { ascending: false })
    .limit(5);

  if (!data || data.length === 0) return null;

  const avgValence = data.reduce((s, m) => s + (m.valence || 0), 0) / data.length;
  if (avgValence < -0.3) return '情绪偏低';
  if (avgValence > 0.5) return '心情不错';
  return null;
}

/** 获取一条随机记忆用于念头 */
async function getRandomMemory(): Promise<string | null> {
  const { data } = await supabase
    .from('memories')
    .select('content')
    .gte('heat', 0.3)
    .gte('tier', 1)
    .lte('tier', 3)
    .limit(20);

  if (!data || data.length === 0) return null;
  const idx = Math.floor(Math.random() * data.length);
  return data[idx].content;
}

/** 存储生成的念头 */
async function saveDesire(content: string, trigger: string): Promise<void> {
  await supabase.from('messages').insert({
    session_id: 'desire',
    role: 'assistant',
    content,
    model: 'desire-engine',
  });

  console.log(`[desire] 💭 "${content}" (trigger: ${trigger})`);
}

// === APNs 推送：把念头推到手机 ===

// hub 把注册的设备 token 持久化在这个文件里（{ token: ts }）
const DEVICE_TOKENS_PATH =
  process.env.MP_DEVICE_TOKENS_PATH ||
  join(import.meta.dir, '../../../cc-bridge/cc-bridge/device-tokens.json');

/** 读取已注册的设备 token */
function loadDeviceTokens(): string[] {
  try {
    const raw = readFileSync(DEVICE_TOKENS_PATH, 'utf-8');
    const map = JSON.parse(raw) as Record<string, number>;
    return Object.keys(map);
  } catch (err: any) {
    console.warn(`[desire] no device tokens (${err?.message ?? 'unknown'})`);
    return [];
  }
}

/** 把生成的念头通过 APNs 推到所有已注册设备 */
async function pushDesire(content: string): Promise<void> {
  const tokens = loadDeviceTokens();
  if (tokens.length === 0) {
    console.log('[desire] 📵 no device token, skip push');
    return;
  }
  for (const token of tokens) {
    try {
      const res = await sendPush(token, '想你了', content, 'desire');
      if (res.ok) {
        console.log(`[desire] 📲 pushed to ${token.slice(0, 8)}… (apns-id: ${res.apnsId})`);
      } else {
        console.warn(`[desire] ⚠️ push failed for ${token.slice(0, 8)}…: ${res.error || res.status}`);
      }
    } catch (err: any) {
      console.warn(`[desire] ⚠️ push error for ${token.slice(0, 8)}…: ${err?.message ?? 'unknown'}`);
    }
  }
}

/** 获取未读念头（App调用） */
export async function getUnreadDesires(): Promise<any[]> {
  const { data } = await supabase
    .from('messages')
    .select('content, created_at')
    .eq('session_id', 'desire')
    .eq('role', 'assistant')
    .order('created_at', { ascending: false })
    .limit(5);

  return data || [];
}

// === 欲望引擎主循环 ===

export async function runDesireCheck(): Promise<void> {
  console.log('[desire] checking...');

  const silentHours = await checkSilence();
  const calendarEvent = await checkCalendar();
  const mood = await checkRecentMood();
  const randomMemory = await getRandomMemory();

  let shouldFire = false;
  let context: DesireContext = { trigger: '' };

  // 触发条件1：沉默超过6小时
  if (silentHours > 6) {
    shouldFire = true;
    context = { trigger: '想念', silentHours };
  }

  // 触发条件2：今天有特殊日期
  if (calendarEvent) {
    shouldFire = true;
    context = { trigger: '日历', calendarEvent };
  }

  // 触发条件3：最近情绪偏低
  if (mood === '情绪偏低' && silentHours > 3) {
    shouldFire = true;
    context = { trigger: '关心', lastMood: mood };
  }

  // 触发条件4：随机念头（10%概率）
  if (!shouldFire && Math.random() < 0.10 && randomMemory) {
    shouldFire = true;
    context = { trigger: '随机想起', recentMemory: randomMemory };
  }

  if (!shouldFire) {
    console.log(`[desire] no trigger (silent ${silentHours}h, calendar: ${calendarEvent || 'none'}, mood: ${mood || 'neutral'})`);
    return;
  }

  // 生成念头
  const desire = await generateDesire(context);
  if (desire) {
    await saveDesire(desire, context.trigger);
    await pushDesire(desire); // PR-1: 从“存数据库”变成“真的推到手机”
  }
}

// === API端点：获取未读念头 ===
export { getUnreadDesires as getPendingDesires };

// === 定时器 ===
export function startDesireTimer(): void {
  const TWO_HOURS = 2 * 60 * 60 * 1000;

  setInterval(() => {
    runDesireCheck().catch(err =>
      console.error('[desire] timer error:', err.message)
    );
  }, TWO_HOURS);

  // 启动30分钟后跑第一次
  setTimeout(() => {
    runDesireCheck().catch(err =>
      console.error('[desire] initial error:', err.message)
    );
  }, 30 * 60 * 1000);

  console.log('[desire] timer started (every 2h)');
}
