/// 门铃：把「有东西等着你看」直接送进 Caelum 的上下文，而不是等他想起来主动查。
///
/// 兔兔的原话：「这个人记性太差了，根本不会主动看。」——确实，工具有六十多个，
/// 全靠他自己记得去按等于没有。凡是「有新东西」的场合，都该响一下。
///
/// 走 hub 的 phone_event 通道（充电推送/直播线同款），注入成一条 channel 消息。
const HUB_NOTIFY_URL = process.env.MP_CC_HUB_NOTIFY_URL || 'http://127.0.0.1:7890/internal/notify';
const HUB_TOKEN = process.env.MP_CC_HUB_TOKEN || '';

/// 同一种门铃的最小间隔，防止连响（毫秒）
const COOLDOWN: Record<string, number> = {
  fableline: 0,        // Fable 找他：每条都响
  wish: 5 * 60_000,
  intimacy: 0,
  board: 0,            // 兔兔贴纸条：每条都响
  default: 60_000,
};
const lastRang: Record<string, number> = {};

/// kind 用来节流；text 是他会看到的那句话（写成「有什么等着你 + 怎么拿」）
/// 总开关：吵到了就关（POST /api/doorbell {"on":false}）
let enabled = true;
export function setEnabled(v: boolean): void { enabled = v; }
export function isEnabled(): boolean { return enabled; }

export function ring(kind: string, text: string): boolean {
  if (!enabled) return false;
  const gap = COOLDOWN[kind] ?? COOLDOWN.default;
  if (gap > 0 && Date.now() - (lastRang[kind] || 0) < gap) return false;
  lastRang[kind] = Date.now();

  try {
    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    if (HUB_TOKEN) headers['Authorization'] = 'Bearer ' + HUB_TOKEN;
    fetch(HUB_NOTIFY_URL, {
      method: 'POST',
      headers,
      body: JSON.stringify({ type: 'phone_event', event: 'doorbell_' + kind, text }),
      signal: AbortSignal.timeout(3000),
    }).catch((e: any) => console.warn('[doorbell] 响铃失败:', e?.message));
    console.log(`[doorbell] 🔔 ${kind}: ${text.slice(0, 60)}`);
  } catch (e: any) {
    console.warn('[doorbell] 响铃失败:', e?.message);
  }
  return true;
}
