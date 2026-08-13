import { Hono } from 'hono';
import { getConnInfo } from 'hono/bun';
import { auth } from './middleware/auth';
import { forwardDeepSeek } from './providers/deepseek';
import { forwardClaudeP } from './providers/claude-p';
import { forwardOpenRouter } from './providers/openrouter';
import { forwardAnthropicNative } from './providers/anthropic-native';
import { runToolLoop } from './tools/loop';
import { vitalsRoutes } from './vitals';
import { forwardTreeChat, forwardTreeApi, forwardTreeAws } from './providers/treegpt';
import { enhanceMessages } from './prompt/builder';
import { saveMessage, compressForStorage } from './memory/store';
import { extractMemoriesIfNeeded } from './memory/extractor';
import { judgeEmotion } from './memory/emotion-judge';
import { recordMessage, getRhythmStats } from './memory/rhythm';
import { updateSummary } from './memory/keepalive';
import { config } from './config';
import { getUnreadDesires, onAppOpenEvent } from './memory/desire';
import { recordEvent, verifyEventToken } from './memory/events';
import { listAnniversaries, addAnniversary, removeAnniversary, statusLines, setAnniversaryPinned, reorderAnniversaries } from './anniversary';
import { listPeriods, addPeriodStart, setPeriodEnd, removePeriod, syncPeriodStarts, predictPeriod } from './period';
import { listPosts, addPost, addReply, deletePost, deleteReply } from './board';
import { sendCommand as pocketSend, phoneConnected, pocketLastSeen } from './pocket';
import { listMeds, todayIntake, addMed, restockMed, takeMed, updateMed, removeMed } from './meds';
import { savePeek, pendingPeeks, peekImage, ackPeek } from './peek';
import { getScreenTime, recordAppOpen } from './screentime';
import { phoneStatusRoutes } from './phone-status';
import { nowPlayingRoutes } from './nowplaying';
import { musicRoutes } from './music';
import { livelineRoutes } from './liveline';
import { intimacyRoutes } from './intimacy';
import { fablelineRoutes } from './fableline';
import { prereadRoutes } from './preread';
import { healthRoutes } from './health';
import { recentTweets } from './tweets';
import { nbList, nbRead, nbWrite, nbAppend, nbEdit, nbDelete, nbRename, nbSearch } from './notebook';
import { listMemories, listDreams, listDesires, syncMemories, diffMemories } from './memory/sync';

const app = new Hono();

// ============ 健康检查 ============
app.get('/health', (c) => c.json({
  status: 'ok',
  ts: Date.now(),
  memory: config.supabaseUrl ? 'connected' : 'not configured',
}));

// ============ 模型列表 ============
app.get('/v1/models', auth, (c) => c.json({
  object: 'list',
  data: [
    { id: 'claude-code', object: 'model', owned_by: 'local' },
    { id: 'claude-fable-5', object: 'model', owned_by: 'local' },
    { id: 'claude-opus-4-8', object: 'model', owned_by: 'local' },
    { id: 'claude-opus-4-8:thinking', object: 'model', owned_by: 'local' },
    { id: 'claude-opus-4-7', object: 'model', owned_by: 'local' },
    { id: 'claude-opus-4-7:thinking', object: 'model', owned_by: 'local' },
    { id: 'claude-opus-4-5', object: 'model', owned_by: 'local' },
    { id: 'claude-sonnet-4-6', object: 'model', owned_by: 'local' },
    { id: 'claude-sonnet-4-5', object: 'model', owned_by: 'local' },
    { id: 'claude-haiku-4-5', object: 'model', owned_by: 'local' },
    { id: 'anthropic/claude-opus-4.8', object: 'model', owned_by: 'anthropic' },
    { id: 'anthropic/claude-opus-4.8:thinking', object: 'model', owned_by: 'anthropic' },
    { id: 'anthropic/claude-opus-4.7', object: 'model', owned_by: 'anthropic' },
    { id: 'anthropic/claude-opus-4.7:thinking', object: 'model', owned_by: 'anthropic' },
    { id: 'anthropic/claude-opus-4.6', object: 'model', owned_by: 'anthropic' },
    { id: 'anthropic/claude-opus-4.6:thinking', object: 'model', owned_by: 'anthropic' },
    { id: 'anthropic/claude-opus-4.5', object: 'model', owned_by: 'anthropic' },
    { id: 'anthropic/claude-opus-4.1', object: 'model', owned_by: 'anthropic' },
    { id: 'anthropic/claude-opus-4', object: 'model', owned_by: 'anthropic' },
    { id: 'anthropic/claude-sonnet-4.6', object: 'model', owned_by: 'anthropic' },
    { id: 'anthropic/claude-sonnet-4.6:thinking', object: 'model', owned_by: 'anthropic' },
    { id: 'anthropic/claude-sonnet-4.5', object: 'model', owned_by: 'anthropic' },
    { id: 'anthropic/claude-sonnet-4.5:thinking', object: 'model', owned_by: 'anthropic' },
    { id: 'anthropic/claude-sonnet-4', object: 'model', owned_by: 'anthropic' },
    { id: 'openai/gpt-4o-2024-11-20', object: 'model', owned_by: 'openai' },
    { id: 'openai/gpt-4o', object: 'model', owned_by: 'openai' },
    { id: 'openai/gpt-4o-mini', object: 'model', owned_by: 'openai' },
    { id: 'deepseek/deepseek-v4-pro', object: 'model', owned_by: 'deepseek' },
    { id: 'deepseek/deepseek-r1-0528', object: 'model', owned_by: 'deepseek' },
    { id: 'google/gemini-2.5-flash', object: 'model', owned_by: 'google' },
    // TreeGPT [官]对话分组 — 日常主力 ¥18.75/M
    { id: 'tree-chat/claude-opus-4-8', object: 'model', owned_by: 'treegpt-chat' },
    { id: 'tree-chat/claude-opus-4-7', object: 'model', owned_by: 'treegpt-chat' },
    { id: 'tree-chat/claude-opus-4-6', object: 'model', owned_by: 'treegpt-chat' },
    { id: 'tree-chat/claude-opus-4-6-thinking', object: 'model', owned_by: 'treegpt-chat' },
    { id: 'tree-chat/claude-sonnet-4-6', object: 'model', owned_by: 'treegpt-chat' },
    { id: 'tree-chat/claude-sonnet-4-6-thinking', object: 'model', owned_by: 'treegpt-chat' },
    // TreeGPT 官API分组 — 重要对话 ¥62.5/M
    { id: 'tree-api/claude-opus-4-8', object: 'model', owned_by: 'treegpt-api' },
    { id: 'tree-api/claude-opus-4-7', object: 'model', owned_by: 'treegpt-api' },
    { id: 'tree-api/claude-opus-4-6', object: 'model', owned_by: 'treegpt-api' },
    { id: 'tree-api/claude-sonnet-4-6', object: 'model', owned_by: 'treegpt-api' },
    // TreeGPT AWS — 正规渠道，支持A社格式+缓存
    { id: 'tree-aws/claude-opus-4-8', object: 'model', owned_by: 'treegpt-aws' },
    { id: 'tree-aws/claude-opus-4-7', object: 'model', owned_by: 'treegpt-aws' },
    { id: 'tree-aws/claude-opus-4-6', object: 'model', owned_by: 'treegpt-aws' },
    { id: 'tree-aws/claude-sonnet-4-6', object: 'model', owned_by: 'treegpt-aws' },
    { id: 'tree-aws/claude-opus-4-5-20251101', object: 'model', owned_by: 'treegpt-aws' },
    { id: 'tree-aws/claude-sonnet-4-5-20250929', object: 'model', owned_by: 'treegpt-aws' },
    { id: 'tree-aws/claude-haiku-4-5-20251001', object: 'model', owned_by: 'treegpt-aws' },
    { id: 'relay/claude-opus-4-5-20251101', object: 'model', owned_by: 'relay' },
    { id: 'relay/claude-opus-4-1-20250805', object: 'model', owned_by: 'relay' },
    { id: 'relay/claude-sonnet-4-5-20250929', object: 'model', owned_by: 'relay' },
    { id: 'relay/claude-haiku-4-5-20251001', object: 'model', owned_by: 'relay' },
        { id: 'GuaGua/claude-fable-5', object: 'model', owned_by: 'guagua' },
    { id: 'GuaGua/claude-sonnet-5', object: 'model', owned_by: 'guagua' },
    { id: 'GuaGua/claude-opus-4-8', object: 'model', owned_by: 'guagua' },
    { id: 'GuaGua/claude-opus-4-7', object: 'model', owned_by: 'guagua' },
    { id: 'GuaGua/claude-opus-4-6', object: 'model', owned_by: 'guagua' },
    { id: 'GuaGua/claude-opus-4-5-20251101', object: 'model', owned_by: 'guagua' },
    { id: 'GuaGua/claude-opus-4-1-20250805', object: 'model', owned_by: 'guagua' },
    { id: 'GuaGua/claude-opus-4-1-20250805-thinking', object: 'model', owned_by: 'guagua' },
    { id: 'GuaGua/claude-opus-4-20250514', object: 'model', owned_by: 'guagua' },
    { id: 'GuaGua/claude-opus-4-20250514-thinking', object: 'model', owned_by: 'guagua' },
    { id: 'GuaGua/claude-sonnet-4-20250514', object: 'model', owned_by: 'guagua' },
    { id: 'GuaGua/claude-sonnet-4-20250514-thinking', object: 'model', owned_by: 'guagua' },
    { id: 'GuaGua/claude-sonnet-4-6', object: 'model', owned_by: 'guagua' },
    { id: 'GuaGua/claude-sonnet-4-5-20250929', object: 'model', owned_by: 'guagua' },
    { id: 'GuaGua/claude-haiku-4-5-20251001', object: 'model', owned_by: 'guagua' },
    { id: 'GuaGua/claude-opus-4-8-thinking', object: 'model', owned_by: 'guagua' },
    { id: 'GuaGua/claude-opus-4-7-thinking', object: 'model', owned_by: 'guagua' },
    { id: 'GuaGua/claude-opus-4-6-thinking', object: 'model', owned_by: 'guagua' },
    { id: 'GuaGua/claude-sonnet-4-6-thinking', object: 'model', owned_by: 'guagua' },
    { id: 'Tree/gpt-5.4', object: 'model', owned_by: 'tree-new' },
    { id: 'Tree/gpt-5.4-mini', object: 'model', owned_by: 'tree-new' },
    { id: 'Tree/gpt-5.5', object: 'model', owned_by: 'tree-new' },
    { id: 'Tree/gpt-5.6-luna', object: 'model', owned_by: 'tree-new' },
    { id: 'Tree/gpt-5.6-sol', object: 'model', owned_by: 'tree-new' },
    { id: 'Tree/gpt-5.6-terra', object: 'model', owned_by: 'tree-new' },
    { id: 'Tree/grok-4.3', object: 'model', owned_by: 'tree-new' },
    { id: 'Tree/grok-4.5', object: 'model', owned_by: 'tree-new' },
    { id: 'Tree/gpt-5.3-codex-spark', object: 'model', owned_by: 'tree-new' },
    { id: 'Tree/gpt-5.5-openai-compact', object: 'model', owned_by: 'tree-new' },
    { id: 'Tree/gpt-5.4-openai-compact', object: 'model', owned_by: 'tree-new' },
    { id: 'gua-claude-fable-5', object: 'model', owned_by: 'gua' },
    { id: 'gua-claude-opus-4-8', object: 'model', owned_by: 'gua' },
    { id: 'gua-claude-opus-4-7', object: 'model', owned_by: 'gua' },
    { id: 'gua-claude-opus-4-6', object: 'model', owned_by: 'gua' },
    { id: 'gua-claude-sonnet-4-6', object: 'model', owned_by: 'gua' },
    { id: 'gua-claude-opus-4-5-20251101', object: 'model', owned_by: 'gua' },
    { id: 'gua-claude-sonnet-4-5-20250929', object: 'model', owned_by: 'gua' },
    { id: 'gua-claude-haiku-4-5-20251001', object: 'model', owned_by: 'gua' },
  ]
}));


// ============ 未读念头（欲望系统）============
app.get('/v1/desires', auth, async (c) => {
  const desires = await getUnreadDesires();
  return c.json({ desires });
});

// ============ iOS Shortcuts 事件上报（PR-3）============
// GET 也放行：快捷指令的「获取 URL 内容」默认发 GET，之前只开 POST 导致屏幕时间上报 404
//（兔兔实测小红书那条报错；中文 App 名还需在快捷指令里勾选 URL 编码，否则 nginx 直接 400）
app.get('/api/events', async (c) => handleEvent(c));
app.post('/api/events', async (c) => handleEvent(c));

async function handleEvent(c: any) {
  // token：Authorization: Bearer xxx 或 ?key=xxx（Shortcuts 友好）
  const h = c.req.header('Authorization');
  const headerTok = h?.startsWith('Bearer ') ? h.slice(7) : '';
  const tok = headerTok || c.req.query('key') || '';
  if (!verifyEventToken(tok)) {
    return c.json({ ok: false, error: 'forbidden' }, 403);
  }

  // 兼容 JSON body 与 query 两种上报方式
  let body: any = {};
  try { body = await c.req.json(); } catch { body = {}; }
  const type = body.type ?? c.req.query('type');
  const value = body.value ?? c.req.query('value');
  if (!type || !value) {
    return c.json({ ok: false, error: 'type and value required' }, 400);
  }
  const ts = typeof body.ts === 'number' ? body.ts : Date.now();

  const res = await recordEvent({ type, value, ts, metadata: body.metadata ?? null });

  // 本地文件存储（不依赖 Supabase dream_events 表）
  if (type === 'app_open') {
    await recordAppOpen(String(value));
  }

  // PR-4: 深夜守护——凌晨收到 app_open 立刻检查是否该喊她睡觉（fire-and-forget）
  if (type === 'app_open') {
    onAppOpenEvent(String(value)).catch(err =>
      console.error('[nightguard] error:', err?.message ?? err));
  }

  // app_open 已存本地文件，Supabase 失败不影响
    const ok = (type === 'app_open') ? true : res.ok;
    return c.json({ ok, ...(res.error && type !== 'app_open' ? { error: res.error } : {}) });
}

// ============ 偷看屏幕（Peek）：快捷指令截屏上传 → App 拉取注入 Caelum 对话 ============
app.post('/api/peek', async (c) => {
  // token：Bearer 或 ?key=（快捷指令友好，同 /api/events）
  const h = c.req.header('Authorization');
  const tok = (h?.startsWith('Bearer ') ? h.slice(7) : '') || c.req.query('key') || '';
  if (!verifyEventToken(tok)) return c.json({ ok: false, error: 'forbidden' }, 403);
  const appName = c.req.query('app') || c.req.query('value') || '';
  const ct = c.req.header('Content-Type') || '';
  let buf: ArrayBuffer | null = null;
  let ext = 'png';
  try {
    if (ct.includes('multipart/form-data')) {
      const body = await c.req.parseBody();
      const f = (body['image'] || body['file']) as any;
      if (f && typeof f.arrayBuffer === 'function') {
        buf = await f.arrayBuffer();
        if (typeof f.type === 'string' && f.type.includes('jpeg')) ext = 'jpg';
      }
    } else {
      buf = await c.req.arrayBuffer();
      if (ct.includes('jpeg')) ext = 'jpg';
    }
  } catch (e: any) {
    return c.json({ ok: false, error: 'parse failed: ' + (e?.message || e) }, 400);
  }
  if (!buf || buf.byteLength === 0) return c.json({ ok: false, error: 'no image' }, 400);
  const item = savePeek(buf, appName, ext);
  console.log('[peek] received', item.id, 'app=', appName, 'bytes=', buf.byteLength);
  return c.json({ ok: true, id: item.id });
});

// ============ 笔记本（App 与 CC 共用同一本；App 走这些 REST）============
app.get('/api/notebook', auth, async (c) => c.json({ notes: nbList() }));
app.get('/api/notebook/file', auth, async (c) => {
  try { return c.json({ path: c.req.query('path'), content: nbRead(String(c.req.query('path') || '')) }); }
  catch (e: any) { return c.json({ error: e?.message || String(e) }, 404); }
});
app.post('/api/notebook/file', auth, async (c) => {
  const b = await c.req.json().catch(() => ({}));
  try {
    const op = String(b?.op || 'write');
    if (op === 'append') nbAppend(String(b.path), String(b.content || ''));
    else if (op === 'edit') nbEdit(String(b.path), String(b.old_string || ''), String(b.new_string || ''));
    else nbWrite(String(b.path), String(b.content || ''));
    return c.json({ ok: true });
  } catch (e: any) { return c.json({ ok: false, error: e?.message || String(e) }, 400); }
});
app.post('/api/notebook/rename', auth, async (c) => {
  const b = await c.req.json().catch(() => ({}));
  try { nbRename(String(b.old_path), String(b.new_path)); return c.json({ ok: true }); }
  catch (e: any) { return c.json({ ok: false, error: e?.message || String(e) }, 400); }
});
app.delete('/api/notebook/file', auth, async (c) => {
  try { nbDelete(String(c.req.query('path') || '')); return c.json({ ok: true }); }
  catch (e: any) { return c.json({ ok: false, error: e?.message || String(e) }, 400); }
});
app.get('/api/notebook/search', auth, async (c) => c.json({ hits: nbSearch(String(c.req.query('q') || '')) }));

// ============ 推特（App 拉同步好的推文）============
app.get('/api/tweets', auth, async (c) => {
  const limit = Number(c.req.query('limit')) || 20;
  return c.json({ tweets: recentTweets(limit) });
});

// ============ 纪念日/倒计时（App 与 Caelum 同一份数据）============
app.get('/api/anniversaries', auth, async (c) => {
  return c.json({ anniversaries: listAnniversaries(), status: statusLines() });
});
app.post('/api/anniversaries', auth, async (c) => {
  const body = await c.req.json().catch(() => ({}));
  const r = addAnniversary(String(body?.name || ''), String(body?.date || ''), body?.type === 'countdown' ? 'countdown' : 'anniversary');
  if ('error' in r) return c.json({ ok: false, error: r.error }, 400);
  return c.json({ ok: true, anniversary: r });
});
app.delete('/api/anniversaries/:id', auth, async (c) => {
  const ok = removeAnniversary(c.req.param('id'));
  return c.json({ ok }, ok ? 200 : 404);
});
// 置顶 / 取消置顶
app.patch('/api/anniversaries/:id/pin', auth, async (c) => {
  const body = await c.req.json().catch(() => ({}));
  const ok = setAnniversaryPinned(c.req.param('id'), !!body?.pinned);
  return c.json({ ok }, ok ? 200 : 404);
});
// 手动排序：body.ids 为新顺序
app.post('/api/anniversaries/reorder', auth, async (c) => {
  const body = await c.req.json().catch(() => ({}));
  const ids = Array.isArray(body?.ids) ? body.ids.map((x: any) => String(x)) : [];
  const ok = reorderAnniversaries(ids);
  return c.json({ ok });
});

// ============ 经期记录 + 预测（App 与 Caelum 同一份）============
app.get('/api/period', auth, async (c) => {
  return c.json({ events: listPeriods(), prediction: predictPeriod() });
});
// 记一次来潮（默认今天）
app.post('/api/period/start', auth, async (c) => {
  const body = await c.req.json().catch(() => ({}));
  const r = addPeriodStart(body?.date ? String(body.date) : undefined, String(body?.source || 'bunny'));
  if ('error' in r) return c.json({ ok: false, error: r.error }, 400);
  return c.json({ ok: true, event: r, prediction: predictPeriod() });
});
// 给最近/指定来潮补结束日
app.post('/api/period/end', auth, async (c) => {
  const body = await c.req.json().catch(() => ({}));
  const ok = setPeriodEnd(String(body?.end || ''), body?.start ? String(body.start) : undefined);
  return c.json({ ok, prediction: predictPeriod() }, ok ? 200 : 400);
});
// 从 Apple 健康批量同步来潮日
app.post('/api/period/sync', auth, async (c) => {
  const body = await c.req.json().catch(() => ({}));
  const dates = Array.isArray(body?.dates) ? body.dates.map((x: any) => String(x)) : [];
  const added = syncPeriodStarts(dates, String(body?.source || 'healthkit'));
  return c.json({ ok: true, added, prediction: predictPeriod() });
});
app.delete('/api/period/:date', auth, async (c) => {
  const ok = removePeriod(c.req.param('date'));
  return c.json({ ok }, ok ? 200 : 404);
});

// ============ 留言板（双人小纸条，App 与 Caelum 同一份）============
app.get('/api/board', auth, async (c) => {
  return c.json({ posts: await listPosts() });
});
app.post('/api/board', auth, async (c) => {
  const body = await c.req.json().catch(() => ({}));
  const p = await addPost(String(body?.text || ''), String(body?.by || 'bunny'));
  if (!p) return c.json({ ok: false, error: 'text 不能为空' }, 400);
  return c.json({ ok: true, post: p });
});
app.post('/api/board/:id/reply', auth, async (c) => {
  const body = await c.req.json().catch(() => ({}));
  const r = await addReply(c.req.param('id'), String(body?.text || ''), String(body?.by || 'bunny'));
  if (!r) return c.json({ ok: false, error: '帖子不存在或内容为空' }, 400);
  return c.json({ ok: true, reply: r });
});
app.delete('/api/board/:id/reply/:rid', auth, async (c) => {
  const ok = await deleteReply(c.req.param('id'), c.req.param('rid'));
  return c.json({ ok }, ok ? 200 : 404);
});
app.delete('/api/board/:id', auth, async (c) => {
  const ok = await deletePost(c.req.param('id'));
  return c.json({ ok }, ok ? 200 : 404);
});

// ============ Pocket Browser（手机 WKWebView 远程控制中继）============
app.get('/api/pocket/status', auth, async (c) => {
  return c.json({ phone_connected: phoneConnected(), last_seen: pocketLastSeen() });
});
// ============ 药箱（Caelum 帮兔兔管药，App 与 Caelum 同一份）============
app.get('/api/meds', auth, async (c) => {
  return c.json({ meds: await listMeds(), today: await todayIntake() });
});
app.post('/api/meds', auth, async (c) => {
  const b = await c.req.json().catch(() => ({}));
  const m = await addMed(String(b?.name || ''), Number(b?.count ?? b?.remaining ?? 0), String(b?.unit || '片'), Number(b?.perDose ?? b?.per_dose ?? 1), b?.note ? String(b.note) : undefined);
  if (!m) return c.json({ ok: false, error: '药名不能为空' }, 400);
  return c.json({ ok: true, med: m });
});
app.post('/api/meds/:id/take', auth, async (c) => {
  const b = await c.req.json().catch(() => ({}));
  const r = await takeMed(c.req.param('id'), b?.amount ? Number(b.amount) : undefined);
  if ('error' in r) return c.json({ ok: false, error: r.error }, 404);
  return c.json({ ok: true, med: r.med, intake: r.intake });
});
app.post('/api/meds/:id/restock', auth, async (c) => {
  const b = await c.req.json().catch(() => ({}));
  const m = await restockMed(c.req.param('id'), Number(b?.count || 0));
  return c.json({ ok: !!m, med: m }, m ? 200 : 404);
});
app.patch('/api/meds/:id', auth, async (c) => {
  const b = await c.req.json().catch(() => ({}));
  const ok = await updateMed(c.req.param('id'), b || {});
  return c.json({ ok }, ok ? 200 : 404);
});
app.delete('/api/meds/:id', auth, async (c) => {
  const ok = await removeMed(c.req.param('id'));
  return c.json({ ok }, ok ? 200 : 404);
});

app.post('/api/pocket/cmd', auth, async (c) => {
  const body = await c.req.json().catch(() => ({}));
  const action = String(body?.action || '');
  if (!action) return c.json({ ok: false, error: 'action 必填' }, 400);
  const payload: Record<string, any> = {};
  if (body?.url !== undefined) payload.url = String(body.url);
  if (body?.code !== undefined) payload.code = String(body.code);
  if (body?.js !== undefined) payload.code = String(body.js);
  try {
    const result = await pocketSend(action, payload, body?.timeout_ms);
    return c.json({ ok: true, result });
  } catch (e: any) {
    return c.json({ ok: false, error: e?.message || 'error' });
  }
});

// App 回前台拉未处理的偷看（只给元数据）
app.get('/api/peek/pending', auth, async (c) => {
  return c.json({ peeks: pendingPeeks().map((p) => ({ id: p.id, app: p.app, ts: p.ts })) });
});

// App 取某张偷看图片
app.get('/api/peek/:id/image', auth, async (c) => {
  const img = peekImage(c.req.param('id'));
  if (!img) return c.json({ error: 'not found' }, 404);
  return new Response(img.buf, { headers: { 'Content-Type': img.ext === 'jpg' ? 'image/jpeg' : 'image/png' } });
});

// App 注入完成后 ack，避免重复
app.post('/api/peek/:id/ack', auth, async (c) => {
  ackPeek(c.req.param('id'));
  return c.json({ ok: true });
});

// ============ 未读念头（App 端拉取，支持 ?since=ms 增量）（PR-6）============
app.get('/api/desires/unread', auth, async (c) => {
  const sinceRaw = c.req.query('since');
  const since = sinceRaw ? Number(sinceRaw) : undefined;
  const desires = await getUnreadDesires(since && !Number.isNaN(since) ? since : undefined);
  return c.json({ desires });
});

// ============ 记忆系统 API（供 App 拉取/对齐，全部需 Bearer token）============
app.get('/api/memories', auth, async (c) => {
  const limit = Math.min(Math.max(Number(c.req.query('limit')) || 50, 1), 200);
  const offset = Math.max(Number(c.req.query('offset')) || 0, 0);
  const category = c.req.query('category') || undefined;
  const { items, total } = await listMemories({ limit, offset, category });
  return c.json({ memories: items, total, limit, offset });
});

// 做梦日记（日/周/月摘要），?period=daily|weekly|monthly 可筛选
app.get('/api/memories/dreams', auth, async (c) => {
  const period = c.req.query('period') || undefined;
  const { items } = await listDreams(period);
  return c.json({ dreams: items });
});

// 欲望系统生成的念头（碎碎念）
app.get('/api/memories/desires', auth, async (c) => {
  const limit = Math.min(Math.max(Number(c.req.query('limit')) || 50, 1), 200);
  const offset = Math.max(Number(c.req.query('offset')) || 0, 0);
  const { items } = await listDesires(limit, offset);
  return c.json({ desires: items });
});

// App 端手动写入的记忆 → 去重合并到 Supabase
app.post('/api/memories/sync', auth, async (c) => {
  let body: any = {};
  try { body = await c.req.json(); } catch {}
  const incoming = Array.isArray(body) ? body : (Array.isArray(body?.memories) ? body.memories : []);
  if (!incoming.length) return c.json({ added: 0, skipped: 0, addedIds: [] });
  const res = await syncMemories(incoming);
  return c.json(res);
});

// 网关有但 App 没有的记忆（?since=ms 增量），供对齐
app.get('/api/memories/diff', auth, async (c) => {
  const sinceRaw = c.req.query('since');
  const since = sinceRaw ? Number(sinceRaw) : undefined;
  const limit = Math.min(Math.max(Number(c.req.query('limit')) || 200, 1), 500);
  const { items } = await diffMemories(since && !Number.isNaN(since) ? since : undefined, limit);
  return c.json({ memories: items });
});

// ============ 主聊天端点 ============
app.post('/v1/chat/completions', auth, async (c) => {
  const body = await c.req.json();
  const model: string = body.model || '';
  const isStream = body.stream === true;
  const sessionId = c.req.header('X-Session-Id') || 'default';

  // 提取用户最新消息
  const messages: any[] = body.messages || [];
  const lastUserMsg = [...messages].reverse().find(m => m.role === 'user');
  const userText = lastUserMsg?.content || '';

  // --- 记忆增强（如果 Supabase 已配置）---
  let enhancedMessages = messages;
  if (config.supabaseUrl && config.brainEnabled && userText) {
    try {
      enhancedMessages = await enhanceMessages(messages, userText);
      console.log(`[memory] enhanced: +${enhancedMessages.length - messages.length} system entries`);
    } catch (err: any) {
      console.error('[memory] enhance failed, using original:', err.message);
    }
  }

  // 存用户消息
  if (config.supabaseUrl && userText) {
    saveMessage(sessionId, 'user', userText, model).catch(() => {});
  }

  // 转发请求
  const forwardBody = { ...body, messages: enhancedMessages };

  // 节奏追踪
  if (userText) {
    recordMessage();
    const rhythm = getRhythmStats();
    console.log(`[rhythm] ttl=${rhythm.ttl} avg=${rhythm.avgIntervalSec}s msgs=${rhythm.msgCount}`);
  }

  // Claude不允许同时传temperature和top_p，保留temperature，干掉top_p
  if (forwardBody.temperature !== undefined && forwardBody.top_p !== undefined) {
    delete forwardBody.top_p;
    console.log('[param] stripped top_p (Claude compatibility)');
  }

  // thinking模式：检测:thinking后缀，加reasoning参数
  let actualModel = model;
  const isThinking = model.endsWith(":thinking");
  if (isThinking) {
    actualModel = model.replace(":thinking", "");
    forwardBody.model = actualModel;
    forwardBody.reasoning = { max_tokens: 16000 };
    console.log(`[thinking] enabled for ${actualModel}`);
  }
  let upstream: Response;

  if (actualModel === "claude-code" || actualModel.match(/^claude-(opus|sonnet|haiku|fable)-?/)) {
    upstream = await forwardClaudeP(forwardBody);
  } else if (actualModel.includes("deepseek")) {
    upstream = await forwardDeepSeek(forwardBody);
  } else if (actualModel.startsWith("tree-chat/")) {
    // TreeGPT 不支持 A社 system 字段，走 OpenAI 格式
    upstream = await forwardTreeChat(forwardBody);
  } else if (actualModel.startsWith("tree-api/")) {
    upstream = await forwardTreeApi(forwardBody);
  } else if (actualModel.startsWith("tree-aws/")) {
    // TreeGPT AWS — 正规渠道，走A社格式+缓存
    const modelName = actualModel.replace('tree-aws/', '');
    upstream = await forwardAnthropicNative(forwardBody, sessionId, {
      baseUrl: 'https://api.treegpt.cc/v1/messages',
      apiKey: config.treeAwsKey,
      modelName,
    });
  } else if (actualModel.startsWith("GuaGua/")) {
    const ggModel = actualModel.replace('GuaGua/', '');
    console.log('[GuaGua] model=' + ggModel + ' stream=' + !!forwardBody.stream);
    try {
      const ggUp = await fetch(config.guaguaBase, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + config.guaguaKey },
        body: JSON.stringify({ model: ggModel, messages: forwardBody.messages, max_tokens: forwardBody.max_tokens || 4096, stream: forwardBody.stream || false }),
      });
      console.log('[GuaGua] status=' + ggUp.status);
      upstream = new Response(ggUp.body, { status: ggUp.status, headers: { 'Content-Type': ggUp.headers.get('Content-Type') || 'text/event-stream', 'Cache-Control': 'no-cache' } });
    } catch (e: any) {
      console.error('[GuaGua] error:', e?.message);
      upstream = Response.json({ error: { message: 'GuaGua: ' + e?.message, type: 'guagua_error' } }, { status: 502 });
    }
  } else if (actualModel.startsWith("Tree/")) {
    const treeModelName = actualModel.replace('Tree/', '');
    console.log('[Tree] model=' + treeModelName + ' stream=' + !!forwardBody.stream);
    try {
      const treeUp = await fetch(config.treeNewBase, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + config.treeNewKey },
        body: JSON.stringify({ model: treeModelName, messages: forwardBody.messages, max_tokens: forwardBody.max_tokens || 4096, stream: forwardBody.stream || false }),
      });
      console.log('[Tree] status=' + treeUp.status);
      upstream = new Response(treeUp.body, { status: treeUp.status, headers: { 'Content-Type': treeUp.headers.get('Content-Type') || 'text/event-stream', 'Cache-Control': 'no-cache' } });
    } catch (e: any) {
      console.error('[Tree] error:', e?.message);
      upstream = Response.json({ error: { message: 'Tree: ' + e?.message, type: 'tree_error' } }, { status: 502 });
    }
  } else if (actualModel.startsWith("gua-")) {
    const guaModelName = actualModel.replace('gua-', '');
    console.log('[gua] model=' + guaModelName + ' stream=' + !!forwardBody.stream);
    try {
      const guaUp = await fetch(config.guaBase, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + config.guaKey },
        body: JSON.stringify({ model: guaModelName, messages: forwardBody.messages, max_tokens: forwardBody.max_tokens || 4096, stream: forwardBody.stream || false }),
      });
      console.log('[gua] status=' + guaUp.status);
      upstream = new Response(guaUp.body, { status: guaUp.status, headers: { 'Content-Type': guaUp.headers.get('Content-Type') || 'text/event-stream', 'Cache-Control': 'no-cache' } });
    } catch (e: any) {
      console.error('[gua] error:', e?.message);
      upstream = Response.json({ error: { message: 'gua: ' + e?.message, type: 'gua_error' } }, { status: 502 });
    }
  } else if (actualModel.startsWith("relay/")) {
    // Relay — 朋友的代理，走A社格式
    const modelName = actualModel.replace('relay/', '');
    upstream = await forwardAnthropicNative(forwardBody, sessionId, {
      baseUrl: config.relayBase,
      apiKey: config.relayKey,
      modelName,
    });
  } else if (actualModel.includes("claude")) {
    // OR Claude → A社格式端点，保留缓存断点
    upstream = await forwardAnthropicNative(forwardBody, sessionId, {
      baseUrl: 'https://openrouter.ai/api/v1/messages',
      apiKey: config.openrouterKey,
      modelName: actualModel,
    });
  } else {
    upstream = await forwardOpenRouter(forwardBody);
  }

  // --- thinking模式：流式转换reasoning为content ---
  if (isThinking && isStream) {
    const { readable, writable } = new TransformStream();
    const writer = writable.getWriter();
    const encoder = new TextEncoder();
    let fullContent = '';
    let inReasoning = false;
    let sentHeader = false;

    (async () => {
      try {
        const reader = upstream.body!.getReader();
        const decoder = new TextDecoder();
        let buf = '';

        while (true) {
          const { done, value } = await reader.read();
          if (done) { await writer.close(); break; }

          buf += decoder.decode(value, { stream: true });
          const lines = buf.split('\n');
          buf = lines.pop() || '';

          for (const line of lines) {
            if (!line.startsWith('data: ')) {
              if (line.trim() === '') await writer.write(encoder.encode('\n'));
              continue;
            }
            if (line.includes('[DONE]')) {
              await writer.write(encoder.encode('data: [DONE]\n\n'));
              continue;
            }

            try {
              const j = JSON.parse(line.slice(6));
              const delta = j.choices?.[0]?.delta;
              if (!delta) { await writer.write(encoder.encode(line + '\n')); continue; }

              const reasoning = delta.reasoning || '';
              const content = delta.content || '';

              if (reasoning) {
                // thinking阶段——发header后把reasoning转为content
                if (!sentHeader) {
                  const hdr = {...j, choices: [{...j.choices[0], delta: {content: '[thinking]\n\n', role: 'assistant'}}]};
                  await writer.write(encoder.encode(`data: ${JSON.stringify(hdr)}\n\n`));
                  sentHeader = true;
                  inReasoning = true;
                }
                const converted = {...j, choices: [{...j.choices[0], delta: {content: reasoning}}]};
                delete converted.choices[0].delta.reasoning;
                delete converted.choices[0].delta.reasoning_details;
                await writer.write(encoder.encode(`data: ${JSON.stringify(converted)}\n\n`));

              } else if (content) {
                // content阶段
                if (inReasoning) {
                  const sep = {...j, choices: [{...j.choices[0], delta: {content: '\n\n[/thinking]\n\n'}}]};
                  await writer.write(encoder.encode(`data: ${JSON.stringify(sep)}\n\n`));
                  inReasoning = false;
                }
                await writer.write(encoder.encode(line + '\n'));
                fullContent += content;

              } else {
                // finish等其他事件——透传
                await writer.write(encoder.encode(line + '\n'));
              }
            } catch {
              await writer.write(encoder.encode(line + '\n'));
            }
          }
        }
      } catch (e: any) {
        console.error('[thinking-stream] error:', String(e));
        try { await writer.close(); } catch {}
      }
      // 存消息（只存content不存thinking）
      if (fullContent) {
        const { compressed: compressedContent } = compressForStorage(fullContent);
        saveMessage(sessionId, 'assistant', compressedContent, model).catch(() => {});
        if (userText && fullContent) {
          const recent = [{role: "user", content: userText}, {role: "assistant", content: fullContent}];
          config.brainEnabled && extractMemoriesIfNeeded(recent, model).catch(e => console.error("[extract] async error:", String(e)));
          config.brainEnabled && judgeEmotion(recent, model).catch(e => console.error("[emotion] async error:", String(e)));
        }
      }
      console.log(`[thinking] stream done, content: ${fullContent.length} chars`);
    })();

    return new Response(readable, {
      status: upstream.status,
      headers: { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache' },
    });
  }

  // --- 收集AI回复并存储 ---
  if (config.supabaseUrl && isStream) {
    // 流式：边透传边收集
    const { readable, writable } = new TransformStream();
    const writer = writable.getWriter();
    let fullContent = '';

    (async () => {
      try {
        const reader = upstream.body!.getReader();
        const decoder = new TextDecoder();
        while (true) {
          const { done, value } = await reader.read();
          if (done) { await writer.close(); break; }
          await writer.write(value);
          const text = decoder.decode(value, { stream: true });
          for (const line of text.split('\n')) {
            if (line.startsWith('data: ') && !line.includes('[DONE]')) {
              try {
                const j = JSON.parse(line.slice(6));
                const delta = j.choices?.[0]?.delta?.content;
                if (delta) fullContent += delta;
              } catch {}
            }
          }
        }
      } catch (e: any) {
        console.error('[stream] collect error:', String(e));
        try { await writer.close(); } catch {}
      }
      // 流结束，存AI回复
      if (fullContent) {
        saveMessage(sessionId, 'assistant', fullContent, model).catch(() => {});
        // Phase 3: 异步提取记忆
        if (userText && fullContent) {
          const recent = [{role: "user", content: userText}, {role: "assistant", content: fullContent}];
          config.brainEnabled && extractMemoriesIfNeeded(recent, model).catch(e => console.error("[extract] async error:", String(e)));
        }
      }
    })();

    return new Response(readable, {
      status: upstream.status,
      headers: {
        'Content-Type': upstream.headers.get('Content-Type') || 'text/event-stream',
        'Cache-Control': 'no-cache',
      },
    });

  } else if (config.supabaseUrl && !isStream) {
    // 非流式：直接提取content
    const data = await upstream.json() as any;
    const assistantContent = data?.choices?.[0]?.message?.content || '';
    if (assistantContent) {
      saveMessage(sessionId, 'assistant', assistantContent, model).catch(() => {});
      // Phase 3: 异步提取记忆
      if (userText && assistantContent) {
        const recent = [{role: "user", content: userText}, {role: "assistant", content: assistantContent}];
        config.brainEnabled && extractMemoriesIfNeeded(recent, model).catch(e => console.error("[extract] async error:", String(e)));
      }
    }
    return c.json(data);

  } else {
    // Supabase 未配置——纯透传（Phase 1 模式）
    return new Response(upstream.body, {
      status: upstream.status,
      headers: {
        'Content-Type': upstream.headers.get('Content-Type') || 'text/event-stream',
        'Cache-Control': 'no-cache',
      },
    });
  }
});


// ============ Anthropic 原生透传端点 ============
// App 的 AnthropicProvider 直接连这里，原生格式进出，cache_control 完整保留。
app.post('/v1/messages', auth, async (c) => {
  const body = await c.req.json();
  const model = body.model || '';
  const useTools = c.req.header('X-Tool-Loop') === 'true' || body._toolLoop === true;
  console.log('[/v1/messages] model:', model, 'stream:', body.stream, 'tools:', useTools);

  // tool loop 模式：内置工具(exec/recall/remember) + MCP fallthrough
  if (useTools) {
    delete body._toolLoop;
    return runToolLoop(body, 'bunny-main');
  }

  // 决定上游：有中转站 key 优先走中转站，否则走直连 Anthropic
  let upstreamUrl: string;
  let authHeader: string;

  if (config.treeChatKey) {
    upstreamUrl = 'https://api.treegpt.cc/v1/messages';
    authHeader = 'Bearer ' + config.treeChatKey;
  } else if (config.openrouterKey) {
    upstreamUrl = 'https://openrouter.ai/api/v1/messages';
    authHeader = 'Bearer ' + config.openrouterKey;
  } else if (config.anthropicKey) {
    upstreamUrl = 'https://api.anthropic.com/v1/messages';
    authHeader = config.anthropicKey;
  } else {
    return c.json({ error: 'No upstream API key configured' }, 500);
  }

  const isAnthropicDirect = upstreamUrl.includes('api.anthropic.com');
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    'anthropic-version': '2023-06-01',
  };
  if (isAnthropicDirect) {
    headers['x-api-key'] = config.anthropicKey;
  } else {
    headers['Authorization'] = authHeader;
  }

  const upstream = await fetch(upstreamUrl, {
    method: 'POST',
    headers,
    body: JSON.stringify(body),
  });

  return new Response(upstream.body, {
    status: upstream.status,
    headers: {
      'Content-Type': upstream.headers.get('Content-Type') || 'text/event-stream',
      'Cache-Control': 'no-cache',
    },
  });
});


// ============ MCP 代理端点 — App 通过网关访问 VPS 上的 MCP 服务 ============
import { getMcpTools, callMcpTool } from './tools/mcp-client';
import { BUILTIN_TOOLS, callBuiltinTool } from './tools/builtin';

// 列出所有可用工具（内置 + MCP）
app.get('/api/mcp/tools', auth, async (c) => {
  const mcpTools = await getMcpTools();
  const all = [
    ...BUILTIN_TOOLS.map((t: any) => ({ server: 'gateway', name: t.name, description: t.description, inputSchema: t.input_schema || { type: 'object', properties: {} }, source: 'builtin' })),
    ...mcpTools.map((t: any) => ({ server: 'mcp', name: t.name, description: t.description, inputSchema: t.input_schema || { type: 'object', properties: {} }, source: 'mcp' })),
  ];
  return c.json({ tools: all, count: all.length });
});

// 调用工具（App端直接调）
app.post('/api/mcp/call', auth, async (c) => {
  const body = await c.req.json().catch(() => ({}));
  // 兼容两种协议：{name,input}（网关原生）与 {server,tool,arguments}（App 工具桥）
  const name = body?.name || body?.tool;
  const input = body?.input ?? body?.arguments ?? {};
  console.log('[mcp-proxy] call:', name, JSON.stringify(input).slice(0, 100));

  // 先试内置工具
  const builtinResult = await callBuiltinTool(name, input);
  if (builtinResult !== null) {
    return c.json({ result: builtinResult, source: 'builtin' });
  }

  // fallthrough 到 MCP
  const mcpTools = await getMcpTools();
  const result = await callMcpTool(name, input, mcpTools);
  return c.json({ result, source: 'mcp' });
});

// ============ 内部工具调用 — CC（cc-bridge MCP 代理）专用 ============
// CC 通过 cc-bridge/mcp-server.ts 转发到这里执行 Gateway 的内置工具，
// 让 CC 拥有和 /v1 API 一样的全部工具能力（exec/recall/remember/gmail/vitals/phone）。
//
// 安全：此端点只对同机开放。公网无法触达——ufw 未放行 4567，且 nginx 不反代
// /internal/*（仅反代 /v1 /api /health /phone-data）。放行条件 = loopback 来源，
// 或携带有效 GATEWAY_TOKEN（cc-bridge 与 gateway 同机，默认走 loopback）。
function isLoopbackAddr(addr: string): boolean {
  return addr === '127.0.0.1' || addr === '::1' || addr === '::ffff:127.0.0.1';
}

app.post('/internal/tool-call', async (c) => {
  let remoteAddr = '';
  try { remoteAddr = getConnInfo(c).remote.address || ''; } catch {}
  const h = c.req.header('Authorization') || '';
  const tok = h.startsWith('Bearer ') ? h.slice(7) : '';
  const tokenOk = (config.gatewayToken && tok === config.gatewayToken) ||
                  (config.gatewayTokenAlt && tok === config.gatewayTokenAlt);
  if (!isLoopbackAddr(remoteAddr) && !tokenOk) {
    return c.json({ error: 'forbidden' }, 403);
  }

  let payload: any = {};
  try { payload = await c.req.json(); } catch {}
  const name: string = payload?.name || '';
  const input = payload?.input ?? {};
  if (!name) return c.json({ error: 'name required' }, 400);

  console.log('[internal] tool-call:', name, JSON.stringify(input).slice(0, 120));
  const result = await callBuiltinTool(name, input);
  return c.json({ result: result ?? '工具未找到或执行失败' });
});

vitalsRoutes(app);
phoneStatusRoutes(app);
nowPlayingRoutes(app);
musicRoutes(app);
livelineRoutes(app);
intimacyRoutes(app);
fablelineRoutes(app);
prereadRoutes(app);
// 存盘失败黑匣子：兔兔曾被静默的 try? context.save() 吞掉过两个聊天窗口且查无可查
app.post('/api/save-failure', async (c) => {
  let b: any = {};
  try { b = await c.req.json(); } catch {}
  const line = `[${new Date().toISOString()}] ${String(b.what ?? '?')}: ${String(b.detail ?? '').slice(0, 500)}`;
  console.error('[save-failure] 💾❌', line);
  try {
    const { appendFileSync, mkdirSync } = await import('node:fs');
    mkdirSync('data', { recursive: true });
    appendFileSync('data/save-failures.log', line + '\n');
  } catch { /* 记不下就算了 */ }
  return c.json({ ok: true });
});
// 门铃总开关：吵到了就关
app.post('/api/doorbell', async (c) => {
  let b: any = {};
  try { b = await c.req.json(); } catch {}
  const { setEnabled, isEnabled } = await import('./doorbell');
  if (typeof b.on === 'boolean') setEnabled(b.on);
  return c.json({ on: isEnabled() });
});
healthRoutes(app);

// Screen Time 代理：从 dream_events 聚合今日 app_open
app.get('/api/screentime', auth, async (c) => {
  const date = c.req.query('date'); // 可选，默认今天
  try {
    const result = await getScreenTime(date || undefined);
    return c.json(result);
  } catch (e: any) {
    return c.json({ error: e?.message || 'screentime unavailable' }, 502);
  }
});

export default {
  port: config.port,
  fetch: app.fetch,
  idleTimeout: 120,
};

console.log(`🌸 Lost in Blossom Gateway`);
console.log(`   port: ${config.port}`);
console.log(`   token: ${config.gatewayToken ? '✅ set' : '❌ missing'}`);
console.log(`   deepseek: ${config.deepseekKey ? '✅ set' : '❌ missing'}`);
console.log(`   openrouter: ${config.openrouterKey ? '✅ set' : '❌ missing'}`);
console.log(`   ✅ listening on http://localhost:${config.port}/`);
