// 生活数据追踪 — 饮水/进食/药物
// 只有模型（通过工具）能写入，App 只读。兔兔不许造假。
import { Hono } from 'hono';

const DATA_FILE = '/root/projects/BunnyPalace/gateway/data/vitals.json';

interface VitalsData {
  water: { count: number; goal: number; lastUpdated: string };
  food: { count: number; goal: number; meals: string[]; lastUpdated: string };
  meds: { taken: boolean; name: string; lastUpdated: string };
  notes?: { text: string; by: string; ts: string }[]; // 历史备注，App 的 LOG 区仍会显示；写入口已删
  date: string; // YYYY-MM-DD，每天重置
}

/// 主人 0906 工单（兔兔发现）：控制台把昨天和今天的饮食混在一起。三个真凶：
/// ①这里用 UTC 切日 —— 兔兔在北京时间凌晨 0-8 点吃的宵夜会被算进「昨天」，
///   跨日判定整体偏 8 小时；②load() 发现日期变了只在内存返回空数据、从不落盘，
///   下一次 save 又把旧 meals 写回去（她的胡辣汤和昨天的小火锅就这么同框的）；
///   ③旧数据直接丢，没有归档。改：北京日界 + 翻篇即归档落盘。
function today(): string {
  return new Date(Date.now() + 8 * 3600_000).toISOString().slice(0, 10);
}

function defaultData(): VitalsData {
  return {
    water: { count: 0, goal: 6, lastUpdated: '' },
    food: { count: 0, goal: 3, meals: [], lastUpdated: '' },
    meds: { taken: false, name: '右佐匹克隆', lastUpdated: '' },
    date: today(),
  };
}

const HISTORY_FILE = DATA_FILE.replace(/vitals\.json$/, 'vitals-history.json');

/// 翻篇：把昨天那页存进历史（按日期 key，最多留 90 天），再开新的一页。
async function archive(old: VitalsData): Promise<void> {
  try {
    let hist: Record<string, VitalsData> = {};
    try { hist = JSON.parse(await Bun.file(HISTORY_FILE).text()); } catch {}
    if (old.date && (old.food?.meals?.length || old.water?.count || old.meds?.taken)) {
      hist[old.date] = old;
    }
    const keys = Object.keys(hist).sort();
    for (const k of keys.slice(0, Math.max(0, keys.length - 90))) delete hist[k];
    await Bun.write(HISTORY_FILE, JSON.stringify(hist, null, 2));
    console.log(`[vitals] 📔 归档 ${old.date}（饭 ${old.food?.meals?.length ?? 0} 水 ${old.water?.count ?? 0}）`);
  } catch (e: any) {
    console.warn('[vitals] 归档失败:', e?.message);
  }
}

async function load(): Promise<VitalsData> {
  try {
    const text = await Bun.file(DATA_FILE).text();
    const data = JSON.parse(text) as VitalsData;
    if (data.date !== today()) {
      // 日期变了：归档昨天 + **立刻落盘新的一天**（老实现只在内存里返回空数据，
      // 下一次 save 会把旧 meals 原样写回，这就是「昨天今天混在一起」的直接原因）
      await archive(data);
      const fresh = defaultData();
      await Bun.write(DATA_FILE, JSON.stringify(fresh, null, 2));
      return fresh;
    }
    return data;
  } catch {
    return defaultData();
  }
}

/// 历史查询（控制台/工具可用）：某天或最近 N 天
export async function vitalsHistory(): Promise<Record<string, VitalsData>> {
  try { return JSON.parse(await Bun.file(HISTORY_FILE).text()); } catch { return {}; }
}

async function save(data: VitalsData): Promise<void> {
  data.date = today();
  await Bun.write(DATA_FILE, JSON.stringify(data, null, 2));
}

// 内置工具定义
export const VITALS_TOOLS = [
  {
    name: 'vitals_water',
    description: "记一杯水。她喝了、或者我提醒完她喝了，就记一次，一次一杯。",
    input_schema: { type: 'object', properties: {} },
  },
  {
    name: 'vitals_food',
    description: "记一顿饭，写上她吃了什么。",
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
// console_read：随时看今日全况（不用等 App 汇报）。
// console_write 已删（2026-08-03）：与 board_post 重叠且严格更弱（只活一天、不能回复），七天零调用。
// 与 vitals 同一数据文件，每天随 date 重置。
export const CONSOLE_TOOLS = [
  {
    name: 'console_read',
    description: "看今天的控制台：兔兔喝了几杯水、吃了几顿、药吃了没，以及今天写在上面的备注。",
    input_schema: { type: 'object', properties: {} },
  },
];

export async function callConsoleTool(name: string, input: any, by = 'model'): Promise<string | null> {
  if (name !== 'console_read') return null;
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

  /// 历史（归档后的往日页）：控制台「昨天吃了什么」用
  app.get('/api/vitals/history', async (c) => {
    const hist = await vitalsHistory();
    const days = Number(c.req.query('days') || 7);
    const keys = Object.keys(hist).sort().slice(-days);
    return c.json(Object.fromEntries(keys.map((k) => [k, hist[k]])));
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
