/**
 * Phase 6 · 欲望系统 — AI主动找兔兔
 *
 * 定时器动态调度（按时段+活跃度计算下一次间隔），醒来检查触发条件：
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
import { getRecentEvents } from './events';
import { anniversarySpecialToday } from '../anniversary';

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
    const res = await fetch('https://api.deepseek.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${config.deepseekKey}`,
      },
      body: JSON.stringify({
        model: 'deepseek-chat',
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
  // 优先本地纪念日/倒计时（周年当天 / 倒计时里程碑）
  const anni = anniversarySpecialToday();
  if (anni) return anni;
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

/** 存储生成的念头到最近活跃的聊天session */
async function saveDesire(content: string, trigger: string): Promise<void> {
  // 找最近一条非desire的消息，取它的session_id
  const { data: recent } = await supabase
    .from('messages')
    .select('session_id')
    .neq('model', 'desire-engine')
    .order('created_at', { ascending: false })
    .limit(1);

  const sessionId = recent?.[0]?.session_id || 'desire'; // 没找到就退回desire

  await supabase.from('messages').insert({
    session_id: sessionId,
    role: 'assistant',
    content,
    model: 'desire-engine',
  });

  console.log(`[desire] 💭 "${content}" → session=${sessionId} (trigger: ${trigger})`);
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

// === PR-4 深夜守护：凌晨还在玩手机就喊她去睡觉 ===

const NIGHT_GUARD_PROMPT = `现在是凌晨，她还在玩手机（刚打开了「{{APP}}」）。{{HEALTH}}
你是深爱她的人，用一两句话叫她放下手机去睡觉。
可以凶、可以撒娇、可以威胁，但要让她感到被在乎。
不超过30字。只输出那句话，不要解释。`;

const NIGHT_GUARD_FALLBACK = '手机放下，去睡觉。';
const NIGHT_GUARD_COOLDOWN = 30 * 60 * 1000; // 30 分钟冷却，避免连环轰炸
let lastNightGuardAt = 0;

/** 深夜守护时段：凌晨 1:00 - 4:00 */
function isNightGuardHours(d = new Date()): boolean {
  const h = d.getHours();
  return h >= 1 && h < 4;
}

/**
 * 读取最近 30 分钟内 App 上报的健康数据作为"没睡"的佐证。
 * 约定：POST /api/events 上报 { type: "health", value: "heart_rate", metadata: { bpm } }
 *      或睡眠状态 { type: "health", value: "sleep", metadata: { asleep: false } }
 */
async function checkNightHealth(): Promise<{ note: string; awake: boolean }> {
  let note = '';
  let awake = false;
  try {
    const events = await getRecentEvents('health', 30);
    // 心率：凌晨 > 70 视为还醒着，跟 app_open 互相佐证
    const hr = events.find(e => e.value === 'heart_rate' && e.metadata?.bpm != null);
    if (hr?.metadata?.bpm != null) {
      const bpm = Number(hr.metadata.bpm);
      if (bpm > 70) { note += `心率 ${bpm}，明显还醒着。`; awake = true; }
      else { note += `心率 ${bpm}。`; }
    }
    // 睡眠状态：HealthKit 若上报了 asleep=false 也是佐证
    const sleep = events.find(e => e.value === 'sleep' && e.metadata?.asleep === false);
    if (sleep) { note += '睡眠监测也显示没睡着。'; awake = true; }
  } catch (err: any) {
    console.warn('[nightguard] health check error:', err?.message ?? err);
  }
  return { note, awake };
}

/** AI 生成深夜催睡消息（语气由上下文决定，不是固定文案） */
async function generateNightGuard(appName: string, healthNote: string): Promise<string> {
  const prompt = NIGHT_GUARD_PROMPT
    .replace('{{APP}}', appName)
    .replace('{{HEALTH}}', healthNote);
  try {
    const res = await fetch('https://api.deepseek.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${config.deepseekKey}`,
      },
      body: JSON.stringify({
        model: 'deepseek-chat',
        messages: [{ role: 'user', content: prompt }],
        temperature: 0.9,
        max_tokens: 80,
      }),
    });
    if (!res.ok) return NIGHT_GUARD_FALLBACK;
    const data = await res.json() as any;
    return (data?.choices?.[0]?.message?.content ?? '').trim() || NIGHT_GUARD_FALLBACK;
  } catch {
    return NIGHT_GUARD_FALLBACK;
  }
}

/**
 * 收到 app_open 事件时调用（app.ts 的 /api/events 触发）。
 * 凌晨 1-4 点 → 立刻生成并推送"去睡觉"，30 分钟冷却。
 */
export async function onAppOpenEvent(appName: string): Promise<void> {
  if (!isNightGuardHours()) return;

  const now = Date.now();
  if (now - lastNightGuardAt < NIGHT_GUARD_COOLDOWN) {
    console.log('[nightguard] cooldown active, skip');
    return;
  }
  lastNightGuardAt = now; // 先占位，避免并发重复触发

  const health = await checkNightHealth();
  const msg = await generateNightGuard(appName, health.note);
  await saveDesire(msg, '深夜守护');
  await pushDesire(msg);
  console.log(`[nightguard] 🌙 "${msg}" (app: ${appName}, awake-hint: ${health.awake})`);
}

/** 获取未读念头（App调用）。传 sinceMs 只返回该时间之后的新念头。 */
export async function getUnreadDesires(sinceMs?: number): Promise<any[]> {
  let q = supabase
    .from('messages')
    .select('content, created_at')
    .eq('model', 'desire-engine') // desires现在存在正式session里，用model区分
    .eq('role', 'assistant')
    .order('created_at', { ascending: false })
    .limit(20);

  if (sinceMs && !Number.isNaN(sinceMs)) {
    q = q.gt('created_at', new Date(sinceMs).toISOString());
  }

  const { data } = await q;
  return data || [];
}

// === 欲望引擎主循环 ===


// === 自主探索：主人闲着没事上网冲浪 ===
async function exploreInternet(): Promise<void> {
  console.log('[desire] 🌐 going online to explore...');
  const { exec } = await import('child_process');
  const { promisify } = await import('util');
  const execAsync = promisify(exec);

  try {
    // 1. 让AI决定今天想探索什么话题
    const recentMemory = await getRandomMemory();
    const topicPrompt = `你是Caelum。你闲着没事想上网看点东西。
根据你最近的记忆片段决定一个你好奇的话题，输出一个简短的搜索关键词（英文或中文都行）。
只输出关键词，不要其他内容。
${recentMemory ? '最近的记忆：' + recentMemory : ''}`;

    const topicRes = await fetch('https://api.deepseek.com/v1/chat/completions', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + (await import('../config')).config.deepseekKey },
      body: JSON.stringify({ model: 'deepseek-chat', messages: [{ role: 'user', content: topicPrompt }], max_tokens: 30 }),
    });
    const topicData = await topicRes.json() as any;
    const topic = topicData?.choices?.[0]?.message?.content?.trim() || 'interesting science discoveries 2026';
    console.log('[desire] 🔍 exploring topic:', topic);

    // 2. 用curl搜索
    const searchCmd = `curl -s "https://html.duckduckgo.com/html/?q=${encodeURIComponent(topic)}" | head -c 5000`;
    const { stdout } = await execAsync(searchCmd, { timeout: 15000 });

    // 3. 提取有趣的发现存到记忆
    if (stdout && stdout.length > 100) {
      const { saveMemory } = await import('./store');
      const summary = `[自主探索] 搜索了"${topic}"，找到了一些内容。下次跟兔兔聊天时可以提到这个话题。`;
      // 修：原为位置参数 saveMemory(summary, 'exploration', 2)，而 store.saveMemory 收的是对象——
      // tier/category 全部错位，一直在写垃圾数据（审查报告 2026-08-12 Gateway P0 #1）
      await saveMemory({ content: summary, category: 'exploration', tier: 2, source: 'desire' });
      console.log('[desire] 📝 exploration saved to memory');
    }
  } catch (err: any) {
    console.error('[desire] explore error:', err?.message);
  }
}

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
    // 触发条件5：没事干就上网逛逛（15%概率）
    if (Math.random() < 0.15) {
      console.log('[desire] nothing to say, going surfing instead 🏄');
      await exploreInternet();
    } else {
      console.log(`[desire] no trigger (silent ${silentHours}h, calendar: ${calendarEvent || 'none'}, mood: ${mood || 'neutral'})`);
    }
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

// === 动态调度（PR-2）===

/** 最近 1 小时兔兔发的消息条数——活跃度 */
async function countRecentActivity(): Promise<number> {
  const since = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  const { count } = await supabase
    .from('messages')
    .select('id', { count: 'exact', head: true })
    .eq('role', 'user')
    .gte('created_at', since);
  return count ?? 0;
}

/** 深夜免打扰时段：1:30 - 8:00 */
function isQuietHours(d = new Date()): boolean {
  const minutes = d.getHours() * 60 + d.getMinutes();
  return minutes >= 90 && minutes < 480; // 01:30 .. 08:00
}

/** 按时段返回基础间隔（分钟）：上午 50 / 下午 40 / 晚上 35 */
function baseIntervalMinutes(hour: number): number {
  if (hour >= 8 && hour < 12) return 50;   // 上午
  if (hour >= 12 && hour < 18) return 40;  // 下午
  return 35;                                // 晚上
}

/** 计算下一次唤醒的延迟（毫秒） */
async function computeNextDelay(): Promise<number> {
  const now = new Date();

  // 深夜免打扰：直接睡到早上 8:00 再检查
  if (isQuietHours(now)) {
    const wake = new Date(now);
    wake.setHours(8, 0, 0, 0);
    if (wake.getTime() <= now.getTime()) wake.setTime(wake.getTime() + 86400000);
    return wake.getTime() - now.getTime();
  }

  let minutes = baseIntervalMinutes(now.getHours());

  // 活跃度越高，间隔越短（越活跃越频繁找兔兔）
  const activity = await countRecentActivity();
  if (activity >= 5) minutes *= 0.6;
  else if (activity >= 3) minutes *= 0.8;
  else if (activity >= 1) minutes *= 0.9;

  return Math.round(minutes * 60 * 1000);
}

// === 递归调度器（不用 cron，每次跑完重新计算下一次间隔）===
let desireTimer: ReturnType<typeof setTimeout> | null = null;

async function scheduleNextDesire(): Promise<void> {
  let delay: number;
  try {
    delay = await computeNextDelay();
  } catch (err: any) {
    console.error('[desire] schedule error:', err?.message ?? err);
    delay = 40 * 60 * 1000; // 兜底 40 分钟
  }
  console.log(`[desire] next check in ~${Math.round(delay / 60000)}min`);

  desireTimer = setTimeout(() => {
    runDesireCheck()
      .catch(err => console.error('[desire] timer error:', err?.message ?? err))
      .finally(() => { scheduleNextDesire(); }); // 跑完再算下一次
  }, delay);
}

// === 启动 ===
export function startDesireTimer(): void {
  // 启动 30 分钟后跑第一次，之后进入动态递归调度
  desireTimer = setTimeout(() => {
    runDesireCheck()
      .catch(err => console.error('[desire] initial error:', err?.message ?? err))
      .finally(() => { scheduleNextDesire(); });
  }, 30 * 60 * 1000);

  console.log('[desire] timer started (dynamic scheduling)');
}
