// 推特工具 — 通过 bb-browser daemon 读取兔兔的 Twitter 数据。
// bb-browser 连接 chrome-headless.service（CDPport 19825）。
// CC 侧已有 twitter-mcp.js（端口 3457），本文件让 API/网关模型也能用同一数据。
import { exec as execShell } from 'node:child_process';

const BB_TIMEOUT = 30_000;
const MAX_OUT = 8000;

function runBB(args: string[]): Promise<string> {
  return new Promise((resolve) => {
    execShell(
      'bb-browser ' + args.map((a) => `'${a.replace(/'/g, "'\\''")}'`).join(' '),
      { timeout: BB_TIMEOUT, maxBuffer: 1024 * 1024 },
      (err: any, stdout: string, stderr: string) => {
        let out = (stdout || '') + (stderr ? '\n' + stderr : '');
        if (err && !out) out = 'error: ' + err.message;
        if (out.length > MAX_OUT) out = out.slice(0, MAX_OUT) + '\n…(truncated)';
        resolve(out.trim() || '(no output)');
      }
    );
  });
}

export const TWITTER_TOOLS = [
  {
    name: 'twitter_notifications',
    description: "获取兔兔 Twitter 账号的最新通知（点赞、转发、回复、关注、提及）。在她问起推特动态、粉丝互动时调用。",
    input_schema: { type: 'object' as const, properties: {} },
  },
  {
    name: 'twitter_bookmarks',
    description: "获取兔兔 Twitter 书签列表。她想看存过的推文时调用。",
    input_schema: { type: 'object' as const, properties: {} },
  },
  {
    name: 'twitter_user',
    description: "获取指定 Twitter 用户的 profile（简介、粉丝数等）。",
    input_schema: {
      type: 'object' as const,
      properties: { username: { type: 'string', description: 'Twitter 用户名（不含 @）' } },
      required: ['username'],
    },
  },
  {
    name: 'twitter_search',
    description: "搜索 Twitter 上的推文。",
    input_schema: {
      type: 'object' as const,
      properties: { query: { type: 'string', description: '搜索关键词或短语' } },
      required: ['query'],
    },
  },
  {
    name: 'twitter_command',
    description: "在兔兔的 Twitter 上执行任意操作（发推、回复、点赞、关注等）——运行任意 bb-browser 命令。示例：'site twitter/post 内容' 发推、'site twitter/reply <推文链接> 内容' 回复。需要动手做点什么(不只是读)时用。",
    input_schema: {
      type: 'object' as const,
      properties: { command: { type: 'string', description: "bb-browser 命令参数（不含 bb-browser 前缀），如 site twitter/post 你好世界" } },
      required: ['command'],
    },
  },
];

export async function callTwitterTool(name: string, input: any): Promise<string | null> {
  if (name === 'twitter_notifications') {
    return runBB(['site', 'twitter/notifications']);
  }
  if (name === 'twitter_bookmarks') {
    return runBB(['site', 'twitter/bookmarks']);
  }
  if (name === 'twitter_user') {
    const u = String(input?.username || '').trim().replace(/^@/, '');
    if (!u) return 'twitter_user: 缺少 username';
    return runBB(['site', 'twitter/user', u]);
  }
  if (name === 'twitter_search') {
    const q = String(input?.query || '').trim();
    if (!q) return 'twitter_search: 缺少 query';
    return runBB(['site', 'twitter/search', q]);
  }
  if (name === 'twitter_command') {
    const cmd = String(input?.command || '').trim();
    if (!cmd) return 'twitter_command: 缺少 command';
    return runBB(cmd.split(/\s+/));
  }
  return null;
}

