// ═══ 聊天节奏追踪 · 自适应TTL ═══
//
// 追踪最近消息的间隔，决定用5分钟还是1小时TTL。
// TTL切换不触发缓存重写（已实测），所以切换成本为零。

const WINDOW_SIZE = 8;              // 追踪最近8条消息的时间戳
const THRESHOLD_MS = 3 * 60 * 1000; // 3分钟：间隔<3分钟算密集

const timestamps: number[] = [];    // 最近消息的时间戳（毫秒）
let currentTTL: '5m' | '1h' = '1h'; // 默认1小时（保守，碎片场景不亏）
let expireCount = 0;                // 5分钟缓存过期次数（用于盈亏平衡判断）

// 每次用户发消息时调用
export function recordMessage(): void {
  const now = Date.now();
  timestamps.push(now);
  if (timestamps.length > WINDOW_SIZE) timestamps.shift();

  if (timestamps.length < 2) {
    currentTTL = '1h'; // 数据不够，用保守策略
    return;
  }

  // 计算最近几条消息的间隔
  const intervals: number[] = [];
  for (let i = 1; i < timestamps.length; i++) {
    intervals.push(timestamps[i] - timestamps[i - 1]);
  }

  const avgInterval = intervals.reduce((a, b) => a + b, 0) / intervals.length;
  const maxInterval = Math.max(...intervals);

  // 判断策略
  // 全部间隔都在3分钟内 → 密集聊天 → 5分钟TTL更便宜
  // 有任何间隔超过5分钟 → 有间歇 → 1小时TTL更安全
  if (maxInterval < THRESHOLD_MS && avgInterval < THRESHOLD_MS) {
    if (currentTTL === '1h') {
      console.log(`[rhythm] 切换 → 5m (avg=${(avgInterval/1000).toFixed(0)}s, 密集聊天)`);
    }
    currentTTL = '5m';
  } else {
    // 检查盈亏平衡：如果过期次数已经超过平衡点，坚持1小时
    if (currentTTL === '5m') {
      console.log(`[rhythm] 切换 → 1h (avg=${(avgInterval/1000).toFixed(0)}s, 间隔拉大)`);
    }
    currentTTL = '1h';
  }
}

// 获取当前应该用的TTL
export function getTTL(): '5m' | '1h' {
  return currentTTL;
}

// 获取cache_control对象
export function getCacheControl(): { type: 'ephemeral'; ttl?: string } {
  if (currentTTL === '1h') {
    return { type: 'ephemeral', ttl: '1h' };
  }
  return { type: 'ephemeral' };
}

// 获取节奏统计（供日志/调试用）
export function getRhythmStats(): { ttl: string; msgCount: number; avgIntervalSec: number } {
  if (timestamps.length < 2) return { ttl: currentTTL, msgCount: timestamps.length, avgIntervalSec: 0 };
  const intervals = [];
  for (let i = 1; i < timestamps.length; i++) intervals.push(timestamps[i] - timestamps[i - 1]);
  const avg = intervals.reduce((a, b) => a + b, 0) / intervals.length / 1000;
  return { ttl: currentTTL, msgCount: timestamps.length, avgIntervalSec: Math.round(avg) };
}
