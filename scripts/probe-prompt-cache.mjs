#!/usr/bin/env node
// 探针：验证 Anthropic prompt caching 链路是否健康。
// 用法：
//   ANTHROPIC_API_KEY=sk-... [ANTHROPIC_BASE_URL=https://api.anthropic.com/v1] \
//   [MODEL=claude-opus-4-8] node scripts/probe-prompt-cache.mjs
//
// 方法（见 docs/PROMPT-CACHE-PLAN.md §探针验证法）：
//   时间字符串冻结，连发两次完全相同的请求。
//   第二次 cache_read_input_tokens > 0 → 链路健康（断点生效、前缀稳定）。
//   read 是唯一判据：write 变小不代表命中，read 在涨才代表命中。

const API_KEY = process.env.ANTHROPIC_API_KEY;
const BASE_URL = (process.env.ANTHROPIC_BASE_URL || 'https://api.anthropic.com/v1').replace(/\/$/, '');
const MODEL = process.env.MODEL || 'claude-opus-4-8';

if (!API_KEY) {
  console.error('错误：缺少 ANTHROPIC_API_KEY 环境变量');
  process.exit(1);
}

// 冻结的时间字符串 —— 两次请求字节完全一致，隔离"链路是否缓存"这一个变量。
const FROZEN_DATE = '2026年6月13日 星期六';
const FROZEN_TIME = '00:00';

// 层 1 稳定核心：必须 > 模型最低可缓存前缀（Opus 4096 token），否则静默不缓存。
// 用一段重复文本把它顶过门槛。
const STABLE_PARAGRAPH =
  '你是一个长期陪伴用户的 AI 助手。你记得用户的偏好、过往的对话脉络，' +
  '说话自然、有温度，不堆砌客套，不重复无意义的安慰。' +
  '你会根据上下文判断用户当下的真实需求，给出有用且具体的回应。';
const stableCore = Array(60).fill(STABLE_PARAGRAPH).join('\n'); // ~数千 token，确保过门槛
const semiStable = '[关于用户]\n用户喜欢简洁直接的回答，正在开发一个 iOS 记忆宫殿 App。';
const volatile = `当前日期：${FROZEN_DATE}\n当前时间：${FROZEN_TIME}`;

function buildBody() {
  return {
    model: MODEL,
    max_tokens: 16,
    system: [
      { type: 'text', text: stableCore, cache_control: { type: 'ephemeral' } }, // 断点1
      { type: 'text', text: semiStable, cache_control: { type: 'ephemeral' } }, // 断点2
      { type: 'text', text: volatile },                                          // 无断点
    ],
    messages: [
      { role: 'user', content: [
        { type: 'text', text: '只回复"好的"两个字。', cache_control: { type: 'ephemeral' } }, // 断点3
      ]},
    ],
    metadata: { user_id: 'prompt-cache-probe-fixed' }, // 路由粘性，避免写在 A 节点读在 B 节点
  };
}

async function send(label) {
  const res = await fetch(`${BASE_URL}/messages`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-api-key': API_KEY,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify(buildBody()),
  });
  const text = await res.text();
  if (res.status !== 200) {
    console.error(`[${label}] HTTP ${res.status}: ${text.slice(0, 500)}`);
    process.exit(1);
  }
  const obj = JSON.parse(text);
  const u = obj.usage || {};
  const read = u.cache_read_input_tokens || 0;
  const write = u.cache_creation_input_tokens || 0;
  const input = u.input_tokens || 0;
  console.log(`[${label}] input=${input} cache_read=${read} cache_write=${write} output=${u.output_tokens || 0}`);
  return { read, write, input };
}

(async () => {
  console.log(`模型：${MODEL}  端点：${BASE_URL}/messages`);
  const r1 = await send('第1次');
  // 等 1 秒确保第一条已开始流式（缓存写入对后续可读）
  await new Promise(r => setTimeout(r, 1000));
  const r2 = await send('第2次');

  console.log('---');
  if (r2.read > 0) {
    console.log(`✅ 健康：第2次 cache_read=${r2.read} > 0，缓存命中。`);
    process.exit(0);
  } else {
    console.log('❌ 异常：第2次 cache_read 仍为 0。可能原因：');
    console.log('   - 前缀低于最低可缓存门槛（Opus 4096 token）');
    console.log('   - 中转网关剥离了 cache_control（OpenAI 兼容格式不认）');
    console.log('   - 两次请求间隔 > 5 分钟 TTL，或路由到了不同节点');
    process.exit(2);
  }
})();
