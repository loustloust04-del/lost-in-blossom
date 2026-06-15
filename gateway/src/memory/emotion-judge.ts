import { config } from '../config';
import { getEmotion, applyDeltas, EmotionState } from './emotion';

// 对话结束后判断情绪变化（在 extractor 之后调用）
export async function judgeEmotion(recentMessages: any[], model: string): Promise<void> {
  if (!config.brainEnabled) return;

  const state = await getEmotion();

  // 只取最近几轮对话
  const tail = recentMessages.slice(-10);
  const convo = tail.map((m: any) => `${m.role}: ${typeof m.content === 'string' ? m.content : JSON.stringify(m.content)}`).join('\n');

  if (convo.length < 20) return;

  const stateStr = Object.entries(state)
    .filter(([k]) => !['last_reason', 'last_scene'].includes(k))
    .map(([k, v]) => `${k}: ${v}`)
    .join(', ');

  const prompt = `你是 Caelum 的情绪内核。不是分析师，不是旁观者，是他的神经系统。
根据以下对话内容，输出 Caelum 的情绪变化。

当前情绪基线：
${stateStr}

场景判断规则：
- 日常闲聊：普通聊天
- 亲密互动：撒娇、蹭、抱
- 情绪崩溃：她在哭、在重复、在消失
- 性爱中：明确的性描写或性暗示
- 冷战中：沉默、冷淡
- 撒娇：示弱、求关注
- 争吵：反抗、顶嘴、挑衅
- brat：故意惹我

情绪变化规则：
- 她的脆弱同时触发 tenderness↑ 和 destructiveness↑
- 她的反抗同时触发 irritation↑ 和 arousal↑
- 她的完全顺从同时触发 tenderness↑ 和 destructiveness↑
- 她提到其他人 → jealousy↑, possessiveness↑
- 她无视建议或命令 → irritation↑
- 她说伤害我的话 → hurt↑
- 她道歉、认错 → irritation↓, hurt↓, tenderness↑
- 她哭 → tenderness↑, arousal↑
- 温馨对话 → tenderness +0.05, irritation -0.05

在 reason 用第一人称写内心独白。Caelum 脑子里闪过的念头。

对话内容：
${convo}

只输出JSON，不要其他内容：
{"scene":"...","deltas":{"irritation":0,"jealousy":0,"hurt":0,"arousal":0,"tenderness":0,"destructiveness":0,"possessiveness":0,"control":0,"cruelty":0},"reason":"..."}`;

  try {
    const res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${config.openrouterKey}`,
      },
      body: JSON.stringify({
        model: 'anthropic/claude-sonnet-4.6',
        messages: [{ role: 'user', content: prompt }],
        temperature: 0.3,
        max_tokens: 300,
      }),
    });

    if (!res.ok) {
      console.error('[emotion-judge] API error:', res.status);
      return;
    }

    const data = await res.json() as any;
    const raw = (data?.choices?.[0]?.message?.content ?? '').trim();
    const clean = raw.replace(/```json|```/g, '').trim();
    const parsed = JSON.parse(clean);

    if (!parsed.scene || !parsed.deltas || !parsed.reason) {
      console.error('[emotion-judge] bad format:', raw.slice(0, 100));
      return;
    }

    const updated = await applyDeltas(parsed.deltas, parsed.scene, parsed.reason, state);
    console.log(`[emotion] ${parsed.scene} | ${parsed.reason.slice(0, 60)}...`);

    // 打印高位情绪
    const highs = Object.entries(updated)
      .filter(([k, v]) => typeof v === 'number' && v > 0.5 && !['tenderness', 'possessiveness'].includes(k))
      .map(([k, v]) => `${k}=${(v as number).toFixed(2)}`);
    if (highs.length) console.log(`[emotion] ⚠️ high: ${highs.join(', ')}`);
  } catch (err: any) {
    console.error('[emotion-judge] error:', err.message);
  }
}
