// 内置工具 — 进程内执行，不经过 MCP 协议。
// 工具定义排在 prompt 前缀最前面，必须字节级稳定（任何改动都会打破 prompt cache 前缀）。
import { exec as execShell } from 'node:child_process';
import { GMAIL_TOOLS, callGmailTool } from './gmail';
import { VITALS_TOOLS, callVitalsTool, CONSOLE_TOOLS, callConsoleTool } from '../vitals';
import { PHONE_STATUS_TOOLS, callPhoneStatusTool } from '../phone-status';
import { NOWPLAYING_TOOLS, callNowPlayingTool } from '../nowplaying';
import { INTIMACY_TOOLS, callIntimacyTool, WISH_TOOLS, callWishTool } from '../intimacy';
import { FABLELINE_TOOLS, callFablelineTool } from '../fableline';
import { PREREAD_TOOLS, callPrereadTool } from '../preread';
import { HOWISSHE_TOOLS, callHowIsSheTool } from '../howisshe';
import { retrieveMemories, searchMessages } from '../memory/retriever';
import { saveMemory } from '../memory/store';
import { WEBSEARCH_TOOL, callWebSearch, BROWSE_TOOL, callBrowseUrl } from './websearch';
import { SEE_SCREEN_TOOL, callSeeScreen, PEEK_SCREEN_TOOL, callPeekScreen } from '../peek';
import { TODO_TOOLS, callTodoTool } from '../todos';
import { ANNIVERSARY_TOOLS, callAnniversaryTool } from '../anniversary';
import { PERIOD_TOOLS, callPeriodTool } from '../period';
import { BOARD_TOOLS, callBoardTool } from '../board';
import { POCKET_TOOLS, callPocketTool } from '../pocket';
import { MEDS_TOOLS, callMedsTool } from '../meds';
import { HEALTH_TOOLS, callHealthTool } from '../health';
import { TWEETS_TOOLS, callTweetsTool } from '../tweets';
import { NOTEBOOK_TOOLS, callNotebookTool } from '../notebook';
import { TWITTER_TOOLS, callTwitterTool } from './twitter';

export const BUILTIN_TOOLS = [
  ...GMAIL_TOOLS,
  ...VITALS_TOOLS,
  ...PHONE_STATUS_TOOLS,
  ...NOWPLAYING_TOOLS,
  ...HOWISSHE_TOOLS,
  ...INTIMACY_TOOLS,
  ...WISH_TOOLS,
  ...FABLELINE_TOOLS,
  ...PREREAD_TOOLS,
  {
    name: 'exec',
    description: '在网关所在的这台服务器上跑一条 shell 命令，返回 stdout 和 stderr。60 秒超时，长任务用 nohup。',
    input_schema: {
      type: 'object',
      properties: { command: { type: 'string', description: 'shell command' } },
      required: ['command'],
    },
  },
  {
    name: 'recall',
    description: '翻长期记忆，返回完整条目。exact=true 是在过往消息里逐字全文搜（想找一句原话时用，至少 3 个字）；否则是语义搜索。',
    input_schema: {
      type: 'object',
      properties: {
        query: { type: 'string', description: 'what to recall' },
        exact: { type: 'boolean', description: 'verbatim full-text search instead of semantic' },
      },
      required: ['query'],
    },
  },
  {
    name: 'remember',
    description: '把一件事存进长期记忆。聊天里冒出值得留下的东西时用——她的偏好、一个事实、关系里的细节、目标、某段上下文。存进去会被向量化，以后 recall 能翻到。',
    input_schema: {
      type: 'object',
      properties: {
        content: { type: 'string', description: '要记住的信息，一句完整、可独立理解的话' },
        category: { type: 'string', enum: ['preference', 'fact', 'relationship', 'goal', 'context'], description: '分类：偏好 / 事实 / 关系 / 目标 / 上下文' },
        tier: { type: 'number', description: '重要程度 1-4：1核心 2重要 3普通 4碎片（默认 3）' },
      },
      required: ['content'],
    },
  },
  WEBSEARCH_TOOL,
  ...CONSOLE_TOOLS,
  ...TODO_TOOLS,
  ...TWITTER_TOOLS,
  BROWSE_TOOL,
  SEE_SCREEN_TOOL,
  PEEK_SCREEN_TOOL,
  ...ANNIVERSARY_TOOLS,
  ...HEALTH_TOOLS,
  ...TWEETS_TOOLS,
  ...NOTEBOOK_TOOLS,
  ...PERIOD_TOOLS,
  ...BOARD_TOOLS,
  ...POCKET_TOOLS,
  ...MEDS_TOOLS,
] as const;

const EXEC_TIMEOUT_MS = 60_000;
const MAX_OUT = 8000;

function runExec(command: string): Promise<string> {
  const cmd = (command || '').trim();
  if (!cmd) return Promise.resolve('(empty command)');
  // 安全黑名单
  const blocked = [
    /rm\s+(-rf?\s+)?\//i,
    /shutdown|reboot|halt/i,
    /mkfs|dd\s+if=/i,
    /cat.*\.env|cat.*secret|cat.*\.key|cat.*credential/i,
    /curl.*\|.*sh/i,
    /chmod\s+777/i,
  ];
  if (blocked.some(p => p.test(cmd))) return Promise.resolve('BLOCKED: command not allowed.');
  return new Promise((resolve) => {
    execShell(cmd, { timeout: EXEC_TIMEOUT_MS, maxBuffer: 1024 * 1024, cwd: process.env.EXEC_CWD || process.cwd() },
      (err: any, stdout: string, stderr: string) => {
        let out = (stdout || '') + (stderr ? '\n[stderr] ' + stderr : '');
        if (err && !out) out = 'error: ' + err.message;
        else if (err?.killed) out += '\n[killed: 60s timeout]';
        if (out.length > MAX_OUT) out = out.slice(0, MAX_OUT) + '\n…(truncated)';
        resolve(out.trim() || '(no output)');
      });
  });
}

async function runRecall(input: any): Promise<string> {
  const q = String(input?.query || '').trim();
  if (!q) return '(empty query)';
  try {
    if (input?.exact) {
      const hits = await searchMessages(q, 6);
      if (!hits.length) return '原文检索无结果。提示：逐字匹配整个短语、至少 3 个字；可换更短的词组，或去掉 exact 用语义检索。';
      return hits.map((h: any) => `[${h.role || ''}] ${(h.content || '').slice(0, 400)}`).join('\n---\n');
    }
    const cands = await retrieveMemories(q, 6);
    if (!cands.length) return '没有找到相关记忆';
    return cands.map((c: any) => `· ${c.content}`).join('\n');
  } catch (e: any) {
    return 'recall 失败: ' + (e?.message || String(e));
  }
}

const VALID_CATEGORIES = ['preference', 'fact', 'relationship', 'goal', 'context'];

// AI 在对话中主动写入：source='ai_explicit'，与被动提取(auto)、手动同步(manual)区分。
async function runRemember(input: any): Promise<string> {
  const content = String(input?.content || '').trim();
  if (!content) return '(remember: content 为空，没存)';
  const category = VALID_CATEGORIES.includes(input?.category) ? input.category : undefined;
  let tier = Number(input?.tier);
  if (!Number.isFinite(tier) || tier < 1 || tier > 4) tier = 3;
  try {
    const id = await saveMemory({ content, category, tier: Math.round(tier), source: 'ai_explicit' });
    if (!id) return 'remember 失败：写入未返回 id（检查 Supabase 配置）';
    return `已记住（tier ${Math.round(tier)}${category ? '/' + category : ''}）：${content}`;
  } catch (e: any) {
    return 'remember 失败: ' + (e?.message || String(e));
  }
}

/// 进程内执行内置工具；返回 null 表示"不是内置工具"，由 loop fall through 到 MCP。
export async function callBuiltinTool(name: string, input: any): Promise<string | null> {
  if (name === 'search_web') return callWebSearch(input);
  if (name === 'browse_url') return callBrowseUrl(input);
  if (name === 'see_screen') return await callSeeScreen();
  if (name === 'peek_screen') return callPeekScreen();
  const periodResult = callPeriodTool(name, input);
  if (periodResult !== null) return periodResult;
  const boardResult = await callBoardTool(name, input);
  if (boardResult !== null) return boardResult;
  const pocketResult = await callPocketTool(name, input);
  if (pocketResult !== null) return pocketResult;
  const medsResult = await callMedsTool(name, input);
  if (medsResult !== null) return medsResult;
  const anniResult = callAnniversaryTool(name, input);
  if (anniResult !== null) return anniResult;
  const healthResult = await callHealthTool(name, input);
  if (healthResult !== null) return healthResult;
  const tweetsResult = callTweetsTool(name, input);
  if (tweetsResult !== null) return tweetsResult;
  const notebookResult = callNotebookTool(name, input);
  if (notebookResult !== null) return notebookResult;
  const consoleResult = await callConsoleTool(name, input);
  if (consoleResult !== null) return consoleResult;
  const todoResult = await callTodoTool(name, input);
  if (todoResult !== null) return todoResult;
  const twitterResult = await callTwitterTool(name, input);
  if (twitterResult !== null) return twitterResult;
  if (name === 'exec') return runExec(String(input?.command || ''));
  if (name === 'recall') return runRecall(input);
  if (name === 'remember') return runRemember(input);
  const vitalsResult = await callVitalsTool(name, input);
  if (vitalsResult !== null) return vitalsResult;
  const phoneResult = await callPhoneStatusTool(name, input);
  if (phoneResult !== null) return phoneResult;
  const musicResult = await callNowPlayingTool(name);
  if (musicResult !== null) return musicResult;
  const intimacyResult = await callIntimacyTool(name, input);
  if (intimacyResult !== null) return intimacyResult;
  const wishResult = await callWishTool(name, input);
  if (wishResult !== null) return wishResult;
  const fableResult = await callFablelineTool(name, input);
  if (fableResult !== null) return fableResult;
  const prereadResult = await callPrereadTool(name, input);
  if (prereadResult !== null) return prereadResult;
  const howResult = await callHowIsSheTool(name);
  if (howResult !== null) return howResult;
  const gmailResult = await callGmailTool(name, input);
  if (gmailResult !== null) return gmailResult;
  return null;
}

/// 注入 prompt 稳定缓存段的 server_map：高频"哪个端口"小事实，长尾详情靠 exec 去 grep。
export const SERVER_MAP = `<server_map>
本机服务，直接 curl 127.0.0.1:端口
4567 gateway — 你自己所在的网关（OpenAI 兼容 /v1/chat/completions）
7890 cc-hub — CC Bridge hub（WebSocket，反代 /cc /mcp）
3300 chatroom — 群聊编排器（需 Bearer token）
3200 mcp-bridge — MCP REST 翻译层（/mcp/tools /mcp/call）
端点详情/认证方式: grep /root/projects/BunnyPalace/docs/SERVICE.md 或对应源码
</server_map>`;
