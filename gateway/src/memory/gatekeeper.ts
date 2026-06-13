import { supabase } from '../db/supabase';
import { activateMemory } from './store';

/**
 * 兔兔独创 · Gatekeeper 三级判断 + 概率性浮现
 * Phase 3更新：区分主记忆和侧翼记忆
 *
 * 主记忆（is_primary）→ 直接注入，不掷骰子
 * 侧翼记忆（is_flanking）→ 经过概率判断
 *
 * 三级判断：
 *   inject    — 显式注入（完整内容放进prompt）
 *   influence — 隐式影响（模糊感觉注入，不透露具体内容）
 *   suppress  — 压抑（不注入，但"想起来了"这件事被记录）
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
  is_primary?: boolean;
  is_flanking?: boolean;
  flank_type?: 'temporal' | 'emotional';
}

interface GatekeeperResult {
  inject: MemoryCandidate[];
  influence: MemoryCandidate[];
  suppress: MemoryCandidate[];
}

export async function gatekeeperFilter(
  candidates: MemoryCandidate[]
): Promise<GatekeeperResult> {
  const result: GatekeeperResult = {
    inject: [],
    influence: [],
    suppress: [],
  };

  for (const mem of candidates) {
    const dice = Math.random();
    let decision: 'inject' | 'influence' | 'suppress';

    // ═══ 主记忆：确定性注入 ═══
    if (mem.is_primary) {
      if (mem.tier <= 2 || mem.is_anchor) {
        decision = 'inject';
      } else if (mem.heat > 0.3) {
        decision = 'inject'; // 主记忆只要还有温度就注入
      } else {
        // 主记忆但已经很冷——还是注入，但标记为模糊
        decision = mem.heat > 0.1 ? 'inject' : 'influence';
      }

    // ═══ 侧翼记忆：概率性浮现 ═══
    } else {
      if (mem.tier <= 2 || mem.is_anchor) {
        decision = 'inject';

      } else if (mem.heat > 0.7) {
        decision = dice < 0.70 ? 'inject'
                 : dice < 0.90 ? 'influence'
                 : 'suppress';

      } else if (mem.heat > 0.4) {
        decision = dice < 0.40 ? 'inject'
                 : dice < 0.70 ? 'influence'
                 : 'suppress';

      } else if (mem.heat > 0.2) {
        decision = dice < 0.15 ? 'inject'
                 : dice < 0.45 ? 'influence'
                 : 'suppress';

      } else {
        decision = dice < 0.05 ? 'inject'
                 : dice < 0.15 ? 'influence'
                 : 'suppress';
      }

      // 日历加成的侧翼提高浮现概率
      if (mem.boosted && decision === 'suppress') {
        if (Math.random() < 0.6) decision = 'influence';
      }
    }

    result[decision].push(mem);

    // 激活被注入的记忆（热度回升）
    if (decision === 'inject') {
      activateMemory(mem.id).catch(() => {});
    }

    // 记录日志——包括压抑的
    supabase.from('gatekeeper_log').insert({
      memory_id: mem.id,
      decision,
      heat_at_decision: mem.heat,
      random_value: dice,
    }).then(({ error }) => {
      if (error) console.error('[gatekeeper] log error:', error.message);
    });
  }

  console.log(
    `[gatekeeper] inject:${result.inject.length} ` +
    `influence:${result.influence.length} ` +
    `suppress:${result.suppress.length} ` +
    `(primary:${candidates.filter(c => c.is_primary).length} ` +
    `flanking:${candidates.filter(c => c.is_flanking).length})`
  );

  return result;
}
