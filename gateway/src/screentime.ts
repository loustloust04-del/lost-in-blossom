// 从本地 app-opens.json 聚合今日屏幕时间

const DATA_FILE = '/root/projects/BunnyPalace/gateway/data/app-opens.json';

const SOCIAL_APPS = ['小红书', '微博', '抖音', 'B站', '微信', 'QQ', 'Twitter', 'Instagram', 'TikTok'];

/// kind 缺省视为 'open'——09-06 之前的历史数据都没有这个字段，不能当成脏数据丢掉
interface AppOpen { app: string; ts: number; kind?: 'open' | 'close' }
interface DayData { date: string; opens: AppOpen[]; }

function todayBeijing(): string {
  const now = new Date();
  return new Date(now.getTime() + 8 * 3600 * 1000).toISOString().slice(0, 10);
}

async function loadOpens(): Promise<DayData> {
  try {
    const text = await Bun.file(DATA_FILE).text();
    const data = JSON.parse(text) as DayData;
    if (data.date !== todayBeijing()) return { date: todayBeijing(), opens: [] };
    return data;
  } catch {
    return { date: todayBeijing(), opens: [] };
  }
}

async function saveOpens(data: DayData): Promise<void> {
  data.date = todayBeijing();
  await Bun.write(DATA_FILE, JSON.stringify(data, null, 2));
}

export async function recordAppOpen(app: string, kind: 'open' | 'close' = 'open'): Promise<void> {
  const data = await loadOpens();
  data.opens.push({ app, ts: Date.now(), kind });
  await saveOpens(data);
  const n = data.opens.length;
  console.log(`[screen] 📱 app_${kind}: ${app} (${n} events today)`);
}

export async function getScreenTime(): Promise<any> {
  const data = await loadOpens();
  const date = data.date;

  if (data.opens.length === 0) {
    return { date, total_minutes: 0, social_minutes: 0, apps: [] };
  }

  // 09-06 重写。旧版靠「下一次打开」减出时长，系统性高估，兔兔实测报不准：
  //   · 锁屏它不知道——刷 2 分钟就睡，下次打开是 3 小时后，直接记满 15 分钟
  //   · 最后一次永远记满 15 分钟（没有『下一次』可减）
  //   · 秒切也算一段——实测 08:17:46→08:17:58 共 12 秒里 Claude/QQ 来回跳 4 次
  //
  // 新版优先用真实的 close 事件配对；没有 close 才回落到旧的推测法。
  // 两种数据混在一起是常态：兔兔一个 app 一个 app 地加自动化，加一个准一个。
  const MAX_SESSION_MS = 15 * 60 * 1000;
  /// 短于这个的不计时长（只记次数）——路过不是使用
  const MIN_SESSION_MS = 20 * 1000;

  const appMinutes: Record<string, { sessions: number; minutes: number; measured: number }> = {};
  const touch = (app: string) => {
    if (!appMinutes[app]) appMinutes[app] = { sessions: 0, minutes: 0, measured: 0 };
    return appMinutes[app];
  };

  /// 每个 app 手上那个还没关的 open，等它的 close。记下标是为了收尾时能找『紧接着的下一个』
  const pending: Record<string, number> = {};
  const pendingAt: Record<string, { ts: number; idx: number }> = {};

  for (let i = 0; i < data.opens.length; i++) {
    const ev = data.opens[i];
    const kind = ev.kind ?? 'open';

    if (kind === 'close') {
      const start = pending[ev.app];
      if (start === undefined) continue;      // 没有配对的 open（漏了/跨天），丢掉不猜
      delete pending[ev.app];
      delete pendingAt[ev.app];
      const dur = Math.min(ev.ts - start, MAX_SESSION_MS);
      const a = touch(ev.app);
      a.sessions += 1;
      a.measured += 1;
      if (dur >= MIN_SESSION_MS) a.minutes += dur / 60000;
      continue;
    }

    // 同一个 app 连开两次没关（自动化漏触发）：前一段按推测法结掉，别丢。
    //
    // ⚠️ 踩过：起初直接用 ev.ts - prev，即「QQ 上次打开」到「QQ 这次打开」。
    // 但中间她明明切去用别的 app 了——QQ 04:35 开、下次开是 07:41，
    // 那三小时被整段算给 QQ（撞满 15 分钟上限），QQ 从 11.7 分虚胖到 60.3 分。
    // 必须用**紧接着的下一个事件**（不论哪个 app）来结账，这点旧算法是对的。
    if (pending[ev.app] !== undefined) {
      const prevIdx = pendingAt[ev.app].idx;
      const nextEv = data.opens[prevIdx + 1];
      const dur = Math.min((nextEv?.ts ?? ev.ts) - pending[ev.app], MAX_SESSION_MS);
      const a = touch(ev.app);
      a.sessions += 1;
      if (dur >= MIN_SESSION_MS) a.minutes += dur / 60000;
    }
    pending[ev.app] = ev.ts;
    pendingAt[ev.app] = { ts: ev.ts, idx: i };
  }

  // 收尾：还开着的（或压根没配 close 自动化的）走旧推测法。
  //
  // ⚠️ 这里踩过一次：起初写成 data.opens.find(o => o.ts > start && o.app !== app)，
  // 从数组头开始找，命中的是一整天里第一个匹配项而不是**紧接着的下一个**，
  // 时间跨度被拉满到 15 分钟上限——QQ 因此从 11.7 分被算成 60.3 分。
  // 正确做法是记住每个 pending 的事件下标，从那之后往后找第一个不同 app 的事件。
  for (const [app, info] of Object.entries(pendingAt)) {
    const nextEv = data.opens.slice(info.idx + 1).find(o => o.app !== app);
    const dur = Math.min((nextEv?.ts ?? Date.now()) - info.ts, MAX_SESSION_MS);
    const a = touch(app);
    a.sessions += 1;
    if (dur >= MIN_SESSION_MS) a.minutes += dur / 60000;
  }

  const apps = Object.entries(appMinutes)
    .map(([app, d]) => ({
      app,
      sessions: d.sessions,
      minutes: Math.round(d.minutes * 10) / 10,
      // 有几段是真量出来的（有 close 配对），其余是推测——让读的人知道这数字有多硬
      measured_sessions: d.measured,
    }))
    .sort((a, b) => b.minutes - a.minutes);

  const total_minutes = Math.round(apps.reduce((sum, a) => sum + a.minutes, 0) * 10) / 10;
  const social_minutes = Math.round(
    apps.filter(a => SOCIAL_APPS.includes(a.app)).reduce((sum, a) => sum + a.minutes, 0) * 10
  ) / 10;

  return { date, total_minutes, social_minutes, apps };
}
