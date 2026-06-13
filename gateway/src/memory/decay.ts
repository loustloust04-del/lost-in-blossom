import { supabase } from '../db/supabase';

/**
 * Phase 3 · 遗忘曲线引擎
 *
 * 参考粟粟的衰减公式 + 兔兔的热度系统
 * effectiveHeat = heat × exp(-λ × days)
 *
 * 被检索召回 → heat +0.2（在gatekeeper里通过activateMemory实现）
 * pinned → 不衰减
 * resolved → 加速衰减（×0.05）
 * 冷记忆（heat < 0.02）→ 不再衰减，冻结
 */

const DECAY_RATE = 0.1; // λ = 0.1，每天约-9.5%

export async function runDecay(): Promise<void> {
  console.log('[decay] starting decay cycle...');

  // 获取所有需要衰减的记忆（非冻结、非置顶）
  const { data: memories, error } = await supabase
    .from('memories')
    .select('id, heat, is_pinned, resolved, updated_at')
    .eq('is_pinned', false)
    .gt('heat', 0.02); // 已冻结的不动

  if (error) {
    console.error('[decay] fetch error:', error.message);
    return;
  }

  if (!memories || memories.length === 0) {
    console.log('[decay] no memories to decay');
    return;
  }

  const now = Date.now();
  let decayed = 0;
  let frozen = 0;

  for (const mem of memories) {
    const lastUpdate = new Date(mem.updated_at || Date.now()).getTime();
    const daysSince = (now - lastUpdate) / 86400000;

    if (daysSince < 0.25) continue; // 6小时内更新的跳过

    let newHeat = mem.heat * Math.exp(-DECAY_RATE * daysSince);

    // resolved记忆加速衰减
    if (mem.resolved) {
      newHeat *= 0.05;
    }

    // 冻结阈值
    if (newHeat < 0.02) {
      newHeat = 0.01;
      frozen++;
    }

    // 只在变化超过1%时才写入（减少数据库压力）
    if (Math.abs(newHeat - mem.heat) / mem.heat > 0.01) {
      await supabase
        .from('memories')
        .update({ heat: newHeat, updated_at: new Date().toISOString() })
        .eq('id', mem.id);
      decayed++;
    }
  }

  console.log(`[decay] cycle done: ${decayed} decayed, ${frozen} frozen, ${memories.length} total`);
}

/**
 * 启动定时衰减（每6小时）
 */
export function startDecayTimer(): void {
  const SIX_HOURS = 6 * 60 * 60 * 1000;
  setInterval(() => {
    runDecay().catch(err => console.error('[decay] timer error:', err.message));
  }, SIX_HOURS);

  // 启动时也跑一次
  setTimeout(() => {
    runDecay().catch(err => console.error('[decay] initial error:', err.message));
  }, 30000); // 30秒后跑第一次，给Gateway时间稳定

  console.log('[decay] timer started (every 6h)');
}
