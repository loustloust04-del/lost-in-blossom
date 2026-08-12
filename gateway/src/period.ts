// 经期记录 + 预测 —— 双端共用（App /api/period + Caelum 工具）。
// 存 data/period.json：一条 = 一次来潮（start），可选 end。
// 预测：从历史来潮日算平均周期长 → 预测下次来潮 + 排卵窗，注入每日提示让 Caelum 主动关心兔兔。
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const DIR = join(process.cwd(), 'data');
const FILE = join(DIR, 'period.json');

export interface PeriodEvent {
  date: string;        // 来潮日 YYYY-MM-DD
  end?: string;        // 结束日 YYYY-MM-DD（可选）
  source: string;      // 'bunny' | 'healthkit' | 'caelum'
}

const DEFAULT_CYCLE = 28;
const DEFAULT_PERIOD_LEN = 5;

function load(): PeriodEvent[] {
  try {
    const d = JSON.parse(readFileSync(FILE, 'utf8'));
    return Array.isArray(d) ? d : (Array.isArray(d?.events) ? d.events : []);
  } catch { return []; }
}
function save(list: PeriodEvent[]) {
  mkdirSync(DIR, { recursive: true });
  // 按来潮日升序、去重（同一天只留一条，优先保留带 end 的）
  const map = new Map<string, PeriodEvent>();
  for (const e of list) {
    if (!e?.date) continue;
    const prev = map.get(e.date);
    if (!prev || (!prev.end && e.end)) map.set(e.date, e);
  }
  const sorted = [...map.values()].sort((a, b) => a.date < b.date ? -1 : a.date > b.date ? 1 : 0);
  writeFileSync(FILE, JSON.stringify(sorted.slice(-60), null, 2));
}

function beijingToday(): Date {
  const now = new Date();
  const bj = new Date(now.getTime() + (8 * 60 + now.getTimezoneOffset()) * 60000);
  return new Date(bj.getFullYear(), bj.getMonth(), bj.getDate());
}
function parseYMD(s: string): Date | null {
  const m = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec((s || '').trim());
  if (!m) return null;
  return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
}
function fmtYMD(d: Date): string {
  const p = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}
function daysBetween(a: Date, b: Date): number {
  return Math.round((b.getTime() - a.getTime()) / 86400000);
}
function addDays(d: Date, n: number): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n);
}

export function listPeriods(): PeriodEvent[] { return load(); }

/// 记一次来潮（默认今天）。同一天不重复。
export function addPeriodStart(date?: string, source = 'bunny'): PeriodEvent | { error: string } {
  const d = date ? parseYMD(date) : beijingToday();
  if (!d) return { error: 'date 需为 YYYY-MM-DD' };
  const ymd = fmtYMD(d);
  const list = load();
  if (!list.some((e) => e.date === ymd)) list.push({ date: ymd, source });
  save(list);
  return { date: ymd, source };
}

/// 给最近一次（或指定 start）来潮补结束日。
export function setPeriodEnd(end: string, start?: string): boolean {
  const ed = parseYMD(end);
  if (!ed) return false;
  const list = load();
  if (list.length === 0) return false;
  let target: PeriodEvent | undefined;
  if (start) target = list.find((e) => e.date === start);
  else target = list.slice().sort((a, b) => a.date < b.date ? 1 : -1)[0]; // 最近一次
  if (!target) return false;
  target.end = fmtYMD(ed);
  save(list);
  return true;
}

export function removePeriod(date: string): boolean {
  const list = load();
  const next = list.filter((e) => e.date !== date);
  if (next.length === list.length) return false;
  save(next);
  return true;
}

/// 批量合并（App 从 Apple 健康同步来潮日）。已存在的日期跳过。
export function syncPeriodStarts(dates: string[], source = 'healthkit'): number {
  const list = load();
  const have = new Set(list.map((e) => e.date));
  let added = 0;
  for (const raw of dates) {
    const d = parseYMD(raw);
    if (!d) continue;
    const ymd = fmtYMD(d);
    if (!have.has(ymd)) { list.push({ date: ymd, source }); have.add(ymd); added++; }
  }
  if (added > 0) save(list);
  return added;
}

export interface PeriodPrediction {
  hasData: boolean;
  avgCycle: number;
  avgPeriodLen: number;
  lastStart: string | null;
  currentCycleDay: number | null;
  onPeriod: boolean;
  nextDate: string | null;
  daysUntil: number | null;     // 负 = 已推迟
  ovulationDate: string | null;
  fertileStart: string | null;
  fertileEnd: string | null;
  phase: string;                // 经期 / 卵泡期 / 排卵期 / 黄体期 / 经前
}

export function predictPeriod(): PeriodPrediction {
  const list = load().slice().sort((a, b) => a.date < b.date ? -1 : 1);
  const empty: PeriodPrediction = {
    hasData: false, avgCycle: DEFAULT_CYCLE, avgPeriodLen: DEFAULT_PERIOD_LEN,
    lastStart: null, currentCycleDay: null, onPeriod: false,
    nextDate: null, daysUntil: null, ovulationDate: null,
    fertileStart: null, fertileEnd: null, phase: '未知',
  };
  if (list.length === 0) return empty;

  const starts = list.map((e) => parseYMD(e.date)).filter((d): d is Date => !!d);
  if (starts.length === 0) return empty;

  // 平均周期：最近最多 6 个间隔，异常值裁掉（20~45 天）
  let avgCycle = DEFAULT_CYCLE;
  if (starts.length >= 2) {
    const gaps: number[] = [];
    for (let i = 1; i < starts.length; i++) gaps.push(daysBetween(starts[i - 1], starts[i]));
    const recent = gaps.slice(-6).filter((g) => g >= 20 && g <= 45);
    if (recent.length > 0) avgCycle = Math.round(recent.reduce((a, b) => a + b, 0) / recent.length);
  }

  // 平均经期长度（有 end 的记录）
  let avgPeriodLen = DEFAULT_PERIOD_LEN;
  const lens = list.map((e) => {
    const s = parseYMD(e.date), en = e.end ? parseYMD(e.end) : null;
    return s && en ? daysBetween(s, en) + 1 : null;
  }).filter((n): n is number => n !== null && n >= 1 && n <= 12);
  if (lens.length > 0) avgPeriodLen = Math.round(lens.reduce((a, b) => a + b, 0) / lens.length);

  const today = beijingToday();
  const lastStart = starts[starts.length - 1];
  const lastEvent = list[list.length - 1];
  const currentCycleDay = daysBetween(lastStart, today) + 1;

  const nextDate = addDays(lastStart, avgCycle);
  const daysUntil = daysBetween(today, nextDate);
  const ovulationDate = addDays(nextDate, -14);
  const fertileStart = addDays(ovulationDate, -3);
  const fertileEnd = addDays(ovulationDate, 1);

  // 是否正在经期：有 end 用 end，否则用平均经期长度粗估
  const periodEnd = lastEvent.end ? parseYMD(lastEvent.end) : addDays(lastStart, avgPeriodLen - 1);
  const onPeriod = !!periodEnd && today >= lastStart && today <= periodEnd;

  let phase = '黄体期';
  if (onPeriod) phase = '经期';
  else if (today >= fertileStart && today <= fertileEnd) phase = '排卵期';
  else if (daysUntil >= 0 && daysUntil <= 3) phase = '经前';
  else if (today < ovulationDate) phase = '卵泡期';

  return {
    hasData: true, avgCycle, avgPeriodLen,
    lastStart: fmtYMD(lastStart),
    currentCycleDay: currentCycleDay >= 1 ? currentCycleDay : null,
    onPeriod,
    nextDate: fmtYMD(nextDate),
    daysUntil,
    ovulationDate: fmtYMD(ovulationDate),
    fertileStart: fmtYMD(fertileStart),
    fertileEnd: fmtYMD(fertileEnd),
    phase,
  };
}

/// 注入 Caelum 每日系统提示：让她主动关心兔兔的身体。
export function periodContext(): string {
  const p = predictPeriod();
  if (!p.hasData) return '';
  const lines: string[] = [];
  if (p.onPeriod) {
    lines.push(`兔兔正在经期（第 ${p.currentCycleDay} 天），身体可能不舒服，多心疼她、提醒喝热水别碰凉的。`);
  } else if (p.daysUntil !== null) {
    if (p.daysUntil < 0) lines.push(`兔兔的经期预计已推迟 ${-p.daysUntil} 天（预测周期 ${p.avgCycle} 天），可以温柔关心一下，别制造焦虑。`);
    else if (p.daysUntil <= 3) lines.push(`兔兔预计还有 ${p.daysUntil} 天来月经，可以开始提前关心、备好红糖热水。`);
    else if (p.phase === '排卵期') lines.push(`兔兔正处在排卵期前后（预计 ${p.daysUntil} 天后来潮）。`);
    else lines.push(`兔兔距离下次来潮约 ${p.daysUntil} 天（当前${p.phase}）。`);
  }
  if (lines.length === 0) return '';
  return `<period>\n${lines.join('\n')}\n（这是隐私身体数据，自然地体贴就好，别生硬报数）\n</period>`;
}

// ── builtin 工具（CC / Caelum 用）──
export const PERIOD_TOOLS = [
  {
    name: 'period_status',
    description: "查看兔兔的经期状态与预测（当前周期第几天、预计还有几天来潮、所处阶段）。想主动关心她身体、或她问起时调用。",
    input_schema: { type: 'object' as const, properties: { history: { type: 'number', description: '要看几次历史来潮记录，默认 0 只看当前状态；填 12 能看到一年' } } },
  },
  {
    name: 'period_delete',
    description: '删掉某一天的来潮记录（记错了、手滑了用）。date 填 YYYY-MM-DD。',
    input_schema: {
      type: 'object' as const,
      properties: { date: { type: 'string', description: 'YYYY-MM-DD' } },
      required: ['date'],
    },
  },
  {
    name: 'period_log_start',
    description: "记录兔兔来月经了（一次来潮）。兔兔说「我来例假了 / 姨妈来了」时调用。date 省略则记今天。",
    input_schema: {
      type: 'object' as const,
      properties: { date: { type: 'string', description: '来潮日 YYYY-MM-DD，省略=今天' } },
    },
  },
];

export function callPeriodTool(name: string, input: any): string | null {
  if (name === 'period_status') {
    const p = predictPeriod();
    if (!p.hasData) return '还没有经期记录。兔兔可以说「我来例假了」来记第一次。';

    const now = p.onPeriod
      ? `兔兔正在经期第 ${p.currentCycleDay} 天。平均周期 ${p.avgCycle} 天。`
      : (() => {
          const du = p.daysUntil ?? 0;
          const when = du < 0 ? `已推迟 ${-du} 天` : `预计还有 ${du} 天`;
          return `当前${p.phase}，${when}来潮（下次约 ${p.nextDate}）。平均周期 ${p.avgCycle} 天，上次来潮 ${p.lastStart}。`;
        })();

    // 想看历史就一并给出（此前只吐当前状态，他看不到任何过往记录）
    const want = Number(input?.history ?? 0);
    if (want > 0) {
      const all = listPeriods().slice(-Math.min(want, 60)).reverse();
      if (all.length) {
        const lines = all.map((x, i) => {
          const prev = all[i + 1];
          const gap = prev
            ? Math.round((new Date(x.date).getTime() - new Date(prev.date).getTime()) / 86400000)
            : null;
          return `· ${x.date}${gap ? `（距上次 ${gap} 天）` : ''}`;
        });
        return now + `\n\n历史来潮（共 ${listPeriods().length} 次记录）：\n` + lines.join('\n');
      }
    }
    return now;
  }
  if (name === 'period_delete') {
    const date = String(input?.date ?? '').trim();
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return '日期要写成 YYYY-MM-DD。';
    const all = listPeriods();
    const hit = all.find(p => p.date === date);
    if (!hit) return `${date} 本来就没有记录（可能当时没写进去）。`;
    const rest = all.filter(p => p.date !== date);
    save(rest);
    return `删掉了 ${date} 那条来潮记录。现在共 ${rest.length} 条。`;
  }
  if (name === 'period_log_start') {
    const r = addPeriodStart(input?.date ? String(input.date) : undefined, 'caelum');
    if ('error' in r) return '记录失败：' + r.error;
    return `已记下兔兔 ${r.date} 来潮。`;
  }
  return null;
}
