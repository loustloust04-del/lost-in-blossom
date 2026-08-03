// 生活数据追踪 — 饮水/进食/药物
// 只有模型（通过工具）能写入，App 只读。兔兔不许造假。
import { Hono } from 'hono';

const DATA_FILE = '/root/projects/BunnyPalace/gateway/data/vitals.json';

interface VitalsData {
  water: { count: number; goal: number; lastUpdated: string };
  food: { count: number; goal: number; meals: string[]; lastUpdated: string };
  meds: { taken: boolean; name: string; lastUpdated: string };
  notes?: { text: string; by: string; ts: string }[]; // 控制台备注（console_write），可选=旧文件兼容
  date: string; // YYYY-MM-DD，每天重置
}

function today(): string {
  return new Date().toISOString().slice(0, 10);
}

function defaultData(): VitalsData {
  return {
    water: { count: 0, goal: 6, lastUpdated: '' },
    food: { count: 0, goal: 3, meals: [], lastUpdated: '' },
    meds: { taken: false, name: '右佐匹克隆', lastUpdated: '' },
    date: today(),
  };
}

async function load(): Promise<VitalsData> {
  try {
    const text = await Bun.file(DATA_FILE).text();
    const data = JSON.parse(text) as VitalsData;
    // 日期变了就重置（新的一天）
    if (data.date !== today()) return defaultData();
    return data;
  } catch {
    return defaultData();
  }
}

async function save(data: VitalsData): Promise<void> {
  data.date = today();
  await Bun.write(DATA_FILE, JSON.stringify(data, null, 2));
}

// 内置工具定义
export const VITALS_TOOLS = [
  {
    name: 'vitals_water',
    description: 'Record that Bunny drank water. Call this when she drinks water or you remind her to drink. Each call adds 1 cup.',
    input_schema: { type: 'object', properties: {} },
  },
  {
    name: 'vitals_food',
    description: 'Record that Bunny ate a meal. Call with what she ate.',
    input_schema: { type: 'object', properties: { meal: { type: 'string', description: 'what she ate, e.g. "早餐：面包牛奶"' } }, required: ['meal'] },
  },
];

export async function callVitalsTool(name: string, input: any): Promise<string | null> {
  if (!name.startsWith('vitals_')) return null;
  const data = await load();
  const now = new Date().toISOString();

  if (name === 'vitals_water') {
    data.water.count += 1;
    data.water.lastUpdated = now;
    await save(data);
    return `记录成功：兔兔今天喝了第 ${data.water.count} 杯水（目标 ${data.water.goal} 杯）`;
  }
  if (name === 'vitals_food') {
    data.food.count += 1;
    data.food.meals.push(input?.meal || '未记录');
    data.food.lastUpdated = now;
    await save(data);
    return `记录成功：兔兔今天吃了第 ${data.food.count} 餐（${input?.meal || '未记录'}）`;
  }
  if (name === 'vitals_meds') {
    data.meds.taken = true;
    data.meds.name = input?.name || data.meds.name;
    data.meds.lastUpdated = now;
    await save(data);
    return `记录成功：兔兔今天的 ${data.meds.name} 已服用`;
  }
  return null;
}

// ============ 控制台读写（P1-4：CC/API 双端可读可记）============
// console_read：模型随时看今日全况（不用等 App 汇报）；console_write：记备注/计划/心情。
// 与 vitals 同一数据文件，每天随 date 重置。
export const CONSOLE_TOOLS = [
  {
    name: 'console_read',
    description: "Read today's care console: Bunny's water/food/meds status and any notes written today. Call when you want to know how she is doing today or before reminding her about water/food/meds.",
    input_schema: { type: 'object', properties: {} },
  },
  {
    name: 'console_write',
    description: "Write a note onto today's care console (plan, mood, observation, anything worth tracking today). Both CC and API models share this console.",
    input_schema: {
      type: 'object',
      properties: { text: { type: 'string', description: '要记的内容，一句完整的话' } },
      required: ['text'],
    },
  },
];

export async function callConsoleTool(name: string, input: any, by = 'model'): Promise<string | null> {
  if (name !== 'console_read' && name !== 'console_write') return null;
  const data = await load();
  if (name === 'console_read') {
    const notes = (data.notes ?? []).map((n) => `[${n.ts.slice(11, 16)} ${n.by}] ${n.text}`);
    return [
      `今日 (${data.date}) 控制台：`,
      `- 饮水 ${data.water.count}/${data.water.goal} 杯${data.water.lastUpdated ? `（最后 ${data.water.lastUpdated.slice(11, 16)}）` : ''}`,
      `- 进食 ${data.food.count}/${data.food.goal} 餐${data.food.meals.length ? `：${data.food.meals.join('；')}` : ''}`,
      `- 药物 ${data.meds.name}：${data.meds.taken ? '已服用' : '未服用'}`,
      notes.length ? `- 备注：\n  ${notes.join('\n  ')}` : '- 备注：无',
    ].join('\n');
  }
  const text = String(input?.text || '').trim();
  if (!text) return 'console_write 缺少 text';
  const notes = data.notes ?? [];
  notes.push({ text, by, ts: new Date().toISOString() });
  data.notes = notes.slice(-50);
  await save(data);
  return `已记到今日控制台（第 ${notes.length} 条备注）`;
}

// API 路由
export function vitalsRoutes(app: Hono) {
  app.get('/api/vitals', async (c) => {
    const data = await load();
    return c.json(data);
  });

  /// App 侧合并上报：兔兔在 App 里记的饮水/进食推上来。
  /// 合并语义取「较大者」而非覆盖——两边都是只增计数，谁记得多以谁为准，
  /// 既不会把 Caelum 记的抹掉，也不会把兔兔自己点的抹掉。meals 按未见过的追加。
  app.post('/api/vitals/merge', async (c) => {
    let body: any = {};
    try { body = await c.req.json(); } catch { return c.json({ error: 'invalid JSON' }, 400); }
    const data = await load();
    const now = new Date().toISOString();
    let touched = false;

    const water = Number(body.water_count);
    if (Number.isFinite(water) && water > data.water.count) {
      data.water.count = Math.min(water, 99);
      data.water.lastUpdated = now;
      touched = true;
    }
    const food = Number(body.food_count);
    if (Number.isFinite(food) && food > data.food.count) {
      data.food.count = Math.min(food, 20);
      data.food.lastUpdated = now;
      touched = true;
    }
    if (Array.isArray(body.meals)) {
      for (const m of body.meals.slice(0, 20)) {
        const name = String(m || '').slice(0, 80);
        if (name && !data.food.meals.includes(name)) { data.food.meals.push(name); touched = true; }
      }
    }
    if (touched) await save(data);
    return c.json({ ok: true, water: data.water, food: data.food });
  });
}
