/**
 * PR-3 · iOS Shortcuts 事件上报
 *
 * iOS 快捷指令在「打开某个 App」时 POST 到 /api/events，
 * 事件存到 Supabase 的 dream_events 表。
 * 深夜守护（PR-4）会查询这些事件判断兔兔有没有在该睡觉的时候玩手机。
 */

import { supabase } from '../db/supabase';
import { config } from '../config';
import { timingSafeEqual } from 'node:crypto';

export interface DreamEvent {
  type: string;            // e.g. "app_open"
  value: string;           // e.g. "小红书"
  ts?: number;             // 客户端 epoch ms（可选，缺省用服务器时间）
  metadata?: Record<string, any> | null;
}

/** 校验上报 token：未配置 gatewayToken 则开放；否则常量时间比较 */
export function verifyEventToken(token: string): boolean {
  if (!config.gatewayToken) return true;
  if (!token) return false;
  const a = Buffer.from(token);
  const b = Buffer.from(config.gatewayToken);
  return a.length === b.length && timingSafeEqual(a, b);
}

/** 存一条事件到 dream_events */
export async function recordEvent(ev: DreamEvent): Promise<{ ok: boolean; error?: string }> {
  const row = {
    type: ev.type,
    value: ev.value,
    ts: ev.ts ?? Date.now(),
    metadata: ev.metadata ?? null,
  };
  const { error } = await supabase.from('dream_events').insert(row);
  if (error) {
    console.error('[events] insert error:', error.message);
    return { ok: false, error: error.message };
  }
  console.log(`[events] 📥 ${row.type}=${row.value} @${new Date(row.ts).toISOString()}`);
  return { ok: true };
}

/** 查询最近 withinMinutes 分钟内某类事件（按 ts 倒序），供深夜守护使用 */
export async function getRecentEvents(type: string, withinMinutes: number): Promise<any[]> {
  const sinceMs = Date.now() - withinMinutes * 60 * 1000;
  const { data } = await supabase
    .from('dream_events')
    .select('type, value, ts, created_at')
    .eq('type', type)
    .gte('ts', sinceMs)
    .order('ts', { ascending: false });
  return data || [];
}
