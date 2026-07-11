// 纪念日 / 倒计时 —— 让 Caelum 主动记得你俩的日子。
// 纯本地 JSON 存储（data/anniversary.json）。两类：
//   anniversary 每年循环（相识/生日）→ 算「第 N 天」+「第 N 周年」，当天 🎉
//   countdown  一次性未来日期 → 算「还有 N 天」，过期自动不显示
// anniversaryContext() 注入每日系统提示；set/list 工具供 Caelum 与兔兔随口记。
import { mkdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';

const DIR = join(process.cwd(), 'data');
const FILE = join(DIR, 'anniversary.json');

export interface Anniversary {
  id: string;
  name: string;
  date: string;              // YYYY-MM-DD
  type: 'anniversary' | 'countdown';
}

function load(): Anniversary[] {
  try { return JSON.parse(readFileSync(FILE, 'utf8')); } catch { return []; }
}
function save(list: Anniversary[]) {
  mkdirSync(DIR, { recursive: true });
  writeFileSync(FILE, JSON.stringify(list, null, 2));
}

/// 北京时间「今天」的 Date（零点）
function beijingToday(): Date {
  const now = new Date();
  const bj = new Date(now.getTime() + (8 * 60 + now.getTimezoneOffset()) * 60000);
  return new Date(bj.getFullYear(), bj.getMonth(), bj.getDate());
}
function parseYMD(s: string): Date | null {
  const m = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(s.trim());
  if (!m) return null;
  return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
}
function daysBetween(a: Date, b: Date): number {
  return Math.round((b.getTime() - a.getTime()) / 86400000);
}

export function listAnniversaries(): Anniversary[] { return load(); }

export function addAnniversary(name: string, date: string, type: 'anniversary' | 'countdown' = 'anniversary'): Anniversary | { error: string } {
  if (!name?.trim()) return { error: 'name 不能为空' };
  if (!parseYMD(date)) return { error: 'date 需为 YYYY-MM-DD，例如 2024-07-14' };
  const list = load();
  const item: Anniversary = { id: randomUUID().slice(0, 8), name: name.trim(), date: date.trim(), type };
  list.push(item);
  save(list);
  return item;
}

export function removeAnniversary(id: string): boolean {
  const list = load();
  const next = list.filter((a) => a.id !== id);
  if (next.length === list.length) return false;
  save(next);
  return true;
}

/// 每个纪念日「今天」的一句话状态（已过期的 countdown 略去）
export function statusLines(): string[] {
  const today = beijingToday();
  const out: string[] = [];
  for (const a of load()) {
    const d = parseYMD(a.date);
    if (!d) continue;
    if (a.type === 'countdown') {
      const left = daysBetween(today, d);
      if (left < 0) continue;
      out.push(left === 0 ? `🎯 今天就是「${a.name}」！` : `距离「${a.name}」还有 ${left} 天`);
    } else {
      const since = daysBetween(d, today);
      // 今年的周年日（月日相同）
      const anni = new Date(today.getFullYear(), d.getMonth(), d.getDate());
      const toAnni = daysBetween(today, anni);
      const years = today.getFullYear() - d.getFullYear();
      if (toAnni === 0 && years > 0) out.push(`🎉 今天是「${a.name}」${years} 周年！（第 ${since} 天）`);
      else if (since >= 0) out.push(`「${a.name}」已经第 ${since} 天`);
    }
  }
  return out;
}

/// 今天是否「真的特殊」——供主动念头（desire）触发用：
/// 周年当天、或倒计时剩 0/1/3/7 天才算，避免每天都推「第 N 天」。
/// 返回一句话或 null。
export function anniversarySpecialToday(): string | null {
  const today = beijingToday();
  for (const a of load()) {
    const d = parseYMD(a.date);
    if (!d) continue;
    if (a.type === 'countdown') {
      const left = daysBetween(today, d);
      if (left === 0) return `今天就是「${a.name}」`;
      if ([1, 3, 7].includes(left)) return `距离「${a.name}」只剩 ${left} 天`;
    } else {
      const anni = new Date(today.getFullYear(), d.getMonth(), d.getDate());
      const years = today.getFullYear() - d.getFullYear();
      if (daysBetween(today, anni) === 0 && years > 0) {
        const since = daysBetween(d, today);
        return `今天是「${a.name}」${years} 周年（第 ${since} 天）`;
      }
    }
  }
  return null;
}

/// 注入系统提示的每日纪念日感知；无数据时返回空串（不占 prompt）
export function anniversaryContext(): string {
  const lines = statusLines();
  if (lines.length === 0) return '';
  return `<anniversary>\n今日与兔兔有关的日子（你可以自然地提起，别生硬报数）：\n${lines.map((l) => '· ' + l).join('\n')}\n</anniversary>`;
}

export const ANNIVERSARY_TOOLS = [
  {
    name: 'remember_anniversary',
    description: '记住一个纪念日或倒计时。兔兔说"记一下我们X月X日相识 / 我生日是X / 距离Y还有多久"时调用。type=anniversary 每年循环（相识/生日），type=countdown 一次性未来日期（考试/旅行）。',
    input_schema: {
      type: 'object' as const,
      properties: {
        name: { type: 'string', description: '名字，如「相识」「兔兔生日」「去日本」' },
        date: { type: 'string', description: '日期 YYYY-MM-DD，如 2024-07-14' },
        type: { type: 'string', enum: ['anniversary', 'countdown'], description: 'anniversary=每年循环，countdown=一次性倒计时。默认 anniversary' },
      },
      required: ['name', 'date'] as string[],
    },
  },
  {
    name: 'list_anniversaries',
    description: '查看所有已记的纪念日/倒计时，以及每个「今天」的状态（第几天 / 还有几天）。想主动关心日子、或兔兔问起时调用。',
    input_schema: { type: 'object' as const, properties: {}, required: [] as string[] },
  },
];

export function callAnniversaryTool(name: string, input: any): string | null {
  if (name === 'remember_anniversary') {
    const r = addAnniversary(String(input?.name || ''), String(input?.date || ''), input?.type === 'countdown' ? 'countdown' : 'anniversary');
    if ('error' in r) return '记录失败：' + r.error;
    return `已记住「${r.name}」（${r.date}，${r.type === 'countdown' ? '倒计时' : '每年'}）。id=${r.id}`;
  }
  if (name === 'list_anniversaries') {
    const list = listAnniversaries();
    if (list.length === 0) return '还没有记录任何纪念日。兔兔可以说"记一下我们X月X日相识"。';
    const lines = statusLines();
    return '当前状态：\n' + lines.map((l) => '· ' + l).join('\n') + '\n\n全部：\n' + list.map((a) => `[${a.id}] ${a.name} ${a.date} (${a.type})`).join('\n');
  }
  return null;
}
