import { callHealthTool } from './health';
import { callConsoleTool } from './vitals';
import { callPeriodTool } from './period';
import { callMedsTool } from './meds';

/// 「她今天怎么样」——一次拿全。
/// 此前想知道她的状态要连调 get_health + console_read + period_status + meds_list 四个，
/// 每个只给一块拼图。这里并成一张。
export const HOWISSHE_TOOLS = [
  {
    name: 'how_is_she',
    description: '兔兔今天怎么样——一次拿全：吃药了没、喝了几杯水、吃了几顿、睡了多久、走了多少步、经期第几天、药箱还剩多少。想关心她、或者要提醒她什么之前，看这个就够。',
    input_schema: { type: 'object' as const, properties: {} },
  },
];

export async function callHowIsSheTool(name: string): Promise<string | null> {
  if (name !== 'how_is_she') return null;

  const [health, console_, period, meds] = await Promise.all([
    callHealthTool('get_health').catch(() => null),
    callConsoleTool('console_read', {}).catch(() => null),
    Promise.resolve(callPeriodTool('period_status', {})).catch(() => null),
    callMedsTool('meds_list', {}).catch(() => null),
  ]);

  const parts: string[] = [];
  if (console_) parts.push('【今天】\n' + console_);
  if (health) parts.push('【身体】\n' + health);
  if (period) parts.push('【经期】\n' + period);
  if (meds) parts.push('【药箱】\n' + meds);
  return parts.length ? parts.join('\n\n') : '今天还没有任何记录。';
}
