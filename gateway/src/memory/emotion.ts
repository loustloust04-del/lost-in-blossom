import { supabase } from '../db/supabase';

// ═══ 情绪向量 ═══
export interface EmotionState {
  irritation: number;
  jealousy: number;
  hurt: number;
  arousal: number;
  tenderness: number;
  destructiveness: number;
  possessiveness: number;
  control: number;
  cruelty: number;
  last_reason: string | null;
  last_scene: string | null;
}

const DEFAULTS: EmotionState = {
  irritation: 0, jealousy: 0, hurt: 0, arousal: 0,
  tenderness: 0.8, destructiveness: 0.1, possessiveness: 0.6,
  control: 0.3, cruelty: 0,
  last_reason: null, last_scene: '日常',
};

// ═══ 读取 ═══
export async function getEmotion(): Promise<EmotionState> {
  const { data } = await supabase
    .from('emotion_state')
    .select('*')
    .eq('id', 'caelum')
    .single();
  return data ?? DEFAULTS;
}

// ═══ 写入（delta 模式，不覆盖）═══
export async function applyDeltas(
  deltas: Partial<Record<keyof EmotionState, number>>,
  scene: string,
  reason: string,
  currentState: EmotionState
): Promise<EmotionState> {
  const updated = { ...currentState };

  // 催化 & 压制矩阵
  const catalysts = buildCatalysts(currentState);

  for (const [key, delta] of Object.entries(deltas)) {
    if (typeof delta !== 'number' || delta === 0) continue;
    const k = key as keyof EmotionState;
    if (typeof updated[k] !== 'number') continue;

    const multiplier = catalysts[k] ?? 1.0;
    const adjusted = delta * multiplier;
    (updated[k] as number) = clamp((updated[k] as number) + adjusted);
  }

  updated.last_reason = reason;
  updated.last_scene = scene;

  await supabase
    .from('emotion_state')
    .upsert({ id: 'caelum', ...updated, updated_at: new Date().toISOString() });

  // 追加日志
  await supabase
    .from('emotion_log')
    .insert({ reason, scene, emotion_snapshot: updated });

  return updated;
}

// ═══ 联动矩阵 ═══
function buildCatalysts(s: EmotionState): Record<string, number> {
  const c: Record<string, number> = {};

  // 催化
  c.destructiveness = 1.0;
  if (s.arousal > 0.3) c.destructiveness *= 2.0;        // 越兴奋越想弄坏她
  if (s.tenderness > 0.6) c.destructiveness *= 0.3;      // 温柔压制破坏欲

  c.possessiveness = 1.0;
  if (s.jealousy > 0.3) c.possessiveness *= 2.0;         // 嫉妒催化占有

  c.arousal = 1.0;
  if (s.jealousy > 0.3) c.arousal *= 1.3;                // 嫉妒催化攻击性性欲
  if (s.hurt > 0.4) c.arousal *= 0.5;                    // 受伤时性欲降低

  c.tenderness = 1.0;
  if (s.hurt > 0.4) c.tenderness *= 0.5;                 // 受伤时不温柔

  c.irritation = 1.0;
  if (s.hurt > 0.4) c.irritation *= 1.5;                 // 受伤时易怒

  c.control = 1.0;
  if (s.irritation > 0.4) c.control *= 1.5;              // 烦了想控制

  c.cruelty = 1.0;
  if (s.destructiveness > 0.3) c.cruelty *= 1.5;         // 破坏欲催化残忍
  if (s.tenderness > 0.6) c.cruelty *= 0.2;              // 温柔时不残忍

  return c;
}

// ═══ 自然衰减（每6h调用一次，跟 decay.ts 同步）═══
export async function decayEmotions(): Promise<void> {
  const state = await getEmotion();
  const rates: Record<string, { target: number; rate: number }> = {
    irritation:      { target: 0.0, rate: 0.15 },
    jealousy:        { target: 0.0, rate: 0.20 },  // 嫉妒衰减最快
    hurt:            { target: 0.0, rate: 0.08 },   // 受伤衰减最慢
    arousal:         { target: 0.0, rate: 0.12 },
    tenderness:      { target: 0.8, rate: 0.05 },   // 温柔回归底色，衰减极慢
    destructiveness: { target: 0.1, rate: 0.10 },   // 破坏欲回归底噪
    possessiveness:  { target: 0.6, rate: 0.05 },   // 占有欲回归常驻
    control:         { target: 0.3, rate: 0.08 },
    cruelty:         { target: 0.0, rate: 0.15 },
  };

  const updated: any = {};
  for (const [key, { target, rate }] of Object.entries(rates)) {
    const current = (state as any)[key] as number;
    const diff = current - target;
    if (Math.abs(diff) < 0.01) {
      updated[key] = target;
    } else {
      updated[key] = clamp(current - diff * rate);
    }
  }

  await supabase
    .from('emotion_state')
    .update({ ...updated, updated_at: new Date().toISOString() })
    .eq('id', 'caelum');
}

function clamp(v: number): number {
  return Math.max(0, Math.min(1, v));
}
