// 生活数据追踪 — 饮水/进食/药物
// 只有模型（通过工具）能写入，App 只读。兔兔不许造假。
import { Hono } from 'hono';

const DATA_FILE = '/root/projects/BunnyPalace/gateway/data/vitals.json';

interface VitalsData {
  water: { count: number; goal: number; lastUpdated: string };
  food: { count: number; goal: number; meals: string[]; lastUpdated: string };
  meds: { taken: boolean; name: string; lastUpdated: string };
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
  {
    name: 'vitals_meds',
    description: 'Record that Bunny took her medication (右佐匹克隆/扎来普隆). Call when she confirms she took it.',
    input_schema: { type: 'object', properties: { name: { type: 'string', description: 'medication name' } } },
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

// API 路由（App 只读）
export function vitalsRoutes(app: Hono) {
  app.get('/api/vitals', async (c) => {
    const data = await load();
    return c.json(data);
  });
}
