import { ring } from './doorbell';
// 药箱 —— Caelum 帮兔兔管药：有哪些药、还剩多少、每天吃了多少。
// 双端共用：App /api/meds 读写，Caelum 经 meds_* 工具记。纯本地 JSON（data/meds.json）。
const DATA_FILE = '/root/projects/BunnyPalace/gateway/data/meds.json';

export interface MedItem {
  id: string;
  name: string;
  remaining: number;      // 剩余数量
  unit: string;           // 片 / 粒 / mg ...
  perDose: number;        // 每次剂量（默认 1）
  note?: string;
}
export interface MedIntake {
  date: string;           // YYYY-MM-DD（北京自然日）
  medId: string;
  name: string;           // 快照，药删了也留记录
  amount: number;
  ts: string;             // ISO
}
interface MedsData { meds: MedItem[]; intake: MedIntake[] }

function beijingYMD(): string {
  const now = new Date();
  return new Date(now.getTime() + 8 * 3600 * 1000).toISOString().slice(0, 10);
}

async function load(): Promise<MedsData> {
  try {
    const d = JSON.parse(await Bun.file(DATA_FILE).text()) as MedsData;
    if (!Array.isArray(d.meds)) d.meds = [];
    if (!Array.isArray(d.intake)) d.intake = [];
    return d;
  } catch { return { meds: [], intake: [] }; }
}
async function save(d: MedsData): Promise<void> {
  d.intake = d.intake.slice(-500);
  await Bun.write(DATA_FILE, JSON.stringify(d, null, 2));
}
function newId(prefix: string, n: number): string {
  return `${prefix}${Date.now().toString(36)}${n}`;
}
function findMed(d: MedsData, key: string): MedItem | undefined {
  const k = (key || '').trim();
  if (!k) return undefined;
  return d.meds.find((m) => m.id === k) || d.meds.find((m) => m.name === k)
      || d.meds.find((m) => m.name.includes(k) || k.includes(m.name));
}

export async function listMeds(): Promise<MedItem[]> { return (await load()).meds; }
export async function todayIntake(): Promise<MedIntake[]> {
  const t = beijingYMD();
  return (await load()).intake.filter((i) => i.date === t);
}

export async function addMed(name: string, remaining = 0, unit = '片', perDose = 1, note?: string): Promise<MedItem | null> {
  const n = (name || '').trim();
  if (!n) return null;
  const d = await load();
  const existing = d.meds.find((m) => m.name === n);
  if (existing) { existing.remaining += Math.max(0, remaining); await save(d); return existing; }
  const med: MedItem = { id: newId('m', d.meds.length), name: n, remaining: Math.max(0, remaining), unit: unit || '片', perDose: perDose > 0 ? perDose : 1, note };
  d.meds.push(med);
  await save(d);
  return med;
}

export async function restockMed(key: string, add: number): Promise<MedItem | null> {
  const d = await load();
  const med = findMed(d, key);
  if (!med) return null;
  med.remaining = Math.max(0, med.remaining + (add || 0));
  await save(d);
  return med;
}

/// 吃完药后看看库存够不够，快没了按门铃提醒他
async function checkLowStock(med: MedItem): Promise<void> {
  const doses = med.perDose > 0 ? Math.floor(med.remaining / med.perDose) : med.remaining;
  if (doses <= 3 && doses >= 0) {
    ring('meds_low_' + med.id,
      doses === 0
        ? `${med.name}吃完了——她该去开药了，你提醒一下（ride_clinic 可以直接给她叫车去精神卫生中心）。`
        : `${med.name}只剩 ${med.remaining} ${med.unit}，按每次 ${med.perDose} 算还能吃 ${doses} 次。快没了。`);
  }
}

export async function takeMed(key: string, amount?: number): Promise<{ med: MedItem; intake: MedIntake } | { error: string }> {
  const d = await load();
  const med = findMed(d, key);
  if (!med) return { error: `没找到「${key}」这个药` };
  const amt = amount && amount > 0 ? amount : med.perDose;
  med.remaining = Math.max(0, med.remaining - amt);
  const intake: MedIntake = { date: beijingYMD(), medId: med.id, name: med.name, amount: amt, ts: new Date().toISOString() };
  d.intake.push(intake);
  await save(d);
  await checkLowStock(med);
  return { med, intake };
}

export async function updateMed(id: string, patch: Partial<MedItem>): Promise<boolean> {
  const d = await load();
  const med = d.meds.find((m) => m.id === id);
  if (!med) return false;
  if (typeof patch.name === 'string' && patch.name.trim()) med.name = patch.name.trim();
  if (typeof patch.remaining === 'number') med.remaining = Math.max(0, patch.remaining);
  if (typeof patch.unit === 'string' && patch.unit.trim()) med.unit = patch.unit.trim();
  if (typeof patch.perDose === 'number' && patch.perDose > 0) med.perDose = patch.perDose;
  if (typeof patch.note === 'string') med.note = patch.note;
  await save(d);
  return true;
}

export async function removeMed(id: string): Promise<boolean> {
  const d = await load();
  const before = d.meds.length;
  d.meds = d.meds.filter((m) => m.id !== id);
  if (d.meds.length === before) return false;
  await save(d);
  return true;
}

/// 低库存（够不到 3 次的量）——供 Caelum 提醒补药。
export async function lowStockMeds(): Promise<MedItem[]> {
  return (await load()).meds.filter((m) => m.remaining <= m.perDose * 3 && m.remaining >= 0);
}

/// 注入每日系统提示：让 Caelum 记得帮兔兔盯药。
export async function medsContext(): Promise<string> {
  const d = await load();
  if (d.meds.length === 0) return '';
  const t = beijingYMD();
  const tookToday = d.intake.filter((i) => i.date === t);
  const low = d.meds.filter((m) => m.remaining <= m.perDose * 3);
  const lines: string[] = [];
  if (low.length) lines.push(`兔兔的药快吃完了：${low.map((m) => `${m.name}(剩${m.remaining}${m.unit})`).join('、')}，可以提醒她补货。`);
  if (tookToday.length === 0) lines.push(`兔兔今天还没记录吃药（药箱里有 ${d.meds.length} 种药）。`);
  if (!lines.length) return '';
  return `<meds>\n${lines.join('\n')}\n（自然地关心，别像闹钟一样催）\n</meds>`;
}

// ── builtin 工具（Caelum 用）──
export const MEDS_TOOLS = [
  {
    name: 'meds_list',
    description: "看兔兔药箱里的药：都有哪些、各剩多少、今天吃了啥。想帮她管药、盯库存、或她问起时调用。",
    input_schema: { type: 'object' as const, properties: {} },
  },
  {
    name: 'meds_set',
    description: "直接设定某个药还剩多少（覆盖，不是累加）。数错了、要修正、或者清零时用。",
    input_schema: {
      type: 'object' as const,
      properties: {
        name: { type: 'string', description: '药名（模糊匹配）' },
        count: { type: 'number', description: '设成多少' },
      },
      required: ['name', 'count'],
    },
  },
  {
    name: 'meds_delete',
    description: "从药箱里彻底删掉一条药。",
    input_schema: {
      type: 'object' as const,
      properties: { name: { type: 'string', description: '药名（模糊匹配）或 id' } },
      required: ['name'],
    },
  },
  {
    name: 'meds_add',
    description: "往药箱加药：新药就建一条，已经有的就累加数量（补货也用这个）。",
    input_schema: {
      type: 'object' as const,
      properties: {
        name: { type: 'string', description: '药名，如「右佐匹克隆」' },
        count: { type: 'number', description: '数量（片/粒）' },
        unit: { type: 'string', description: '单位，默认「片」' },
        per_dose: { type: 'number', description: '每次吃几个，默认 1' },
      },
      required: ['name', 'count'],
    },
  },
  {
    name: 'meds_take',
    description: "记录兔兔吃了某个药（会自动扣库存）。她说「我吃药了/吃了X」时用。amount 省略则按每次剂量。",
    input_schema: {
      type: 'object' as const,
      properties: {
        name: { type: 'string', description: '药名（模糊匹配）' },
        amount: { type: 'number', description: '吃了几个，省略=每次剂量' },
      },
      required: ['name'],
    },
  },
];

export async function callMedsTool(name: string, input: any): Promise<string | null> {
  if (name === 'meds_set') {
    const d = await load();
    const med = findMed(d, String(input?.name ?? ''));
    if (!med) return `药箱里没找到「${input?.name}」。`;
    const n = Math.max(0, Number(input?.count ?? 0));
    med.remaining = n;
    await save(d);
    return `${med.name} 设成 ${n} ${med.unit}。`;
  }
  if (name === 'meds_delete') {
    const d = await load();
    const med = findMed(d, String(input?.name ?? ''));
    if (!med) return `药箱里没找到「${input?.name}」。`;
    d.meds = d.meds.filter((m) => m.id !== med.id);
    await save(d);
    return `已从药箱删掉 ${med.name}。`;
  }
  if (name === 'meds_list') {
    const meds = await listMeds();
    if (!meds.length) return '药箱还是空的。兔兔可以说「我有X药，多少片」让你记。';
    const took = await todayIntake();
    const lines = meds.map((m) => `· ${m.name}：剩 ${m.remaining}${m.unit}（每次 ${m.perDose}）`);
    const tookLine = took.length ? '\n今天吃了：' + took.map((i) => `${i.name}×${i.amount}`).join('、') : '\n今天还没记录吃药';
    return '药箱：\n' + lines.join('\n') + tookLine;
  }
  if (name === 'meds_add') {
    const m = await addMed(String(input?.name || ''), Number(input?.count || 0), String(input?.unit || '片'), Number(input?.per_dose || 1));
    return m ? `已记到药箱：${m.name}，现有 ${m.remaining}${m.unit}` : 'meds_add 缺少药名';
  }
  if (name === 'meds_take') {
    const r = await takeMed(String(input?.name || ''), input?.amount ? Number(input.amount) : undefined);
    if ('error' in r) return r.error;
    return `已记录兔兔吃了 ${r.med.name}×${r.intake.amount}，还剩 ${r.med.remaining}${r.med.unit}` + (r.med.remaining <= r.med.perDose * 3 ? '（快吃完了，记得提醒补货）' : '');
  }
  if (name === 'meds_restock') {
    const m = await restockMed(String(input?.name || ''), Number(input?.count || 0));
    return m ? `已补货：${m.name} 现有 ${m.remaining}${m.unit}` : `没找到「${input?.name}」这个药`;
  }
  return null;
}
