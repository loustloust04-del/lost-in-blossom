// 内置工具 — 进程内执行，不经过 MCP 协议。
// 工具定义排在 prompt 前缀最前面，必须字节级稳定（任何改动都会打破 prompt cache 前缀）。
import { exec as execShell } from 'node:child_process';
import { retrieveMemories, searchMessages } from '../memory/retriever';

export const BUILTIN_TOOLS = [
  {
    name: 'exec',
    description: 'Run a shell command on the host this gateway lives on. Returns stdout and stderr. 60s timeout; use nohup for long jobs. SECURITY: arbitrary command execution as the gateway process — only on a private, authenticated gateway.',
    input_schema: {
      type: 'object',
      properties: { command: { type: 'string', description: 'shell command' } },
      required: ['command'],
    },
  },
  {
    name: 'recall',
    description: 'Search long-term memory and return full entries. exact=true does verbatim full-text search over past messages (good for an exact past quote; needs 3+ chars); otherwise semantic search over memories.',
    input_schema: {
      type: 'object',
      properties: {
        query: { type: 'string', description: 'what to recall' },
        exact: { type: 'boolean', description: 'verbatim full-text search instead of semantic' },
      },
      required: ['query'],
    },
  },
] as const;

const EXEC_TIMEOUT_MS = 60_000;
const MAX_OUT = 8000;

function runExec(command: string): Promise<string> {
  const cmd = (command || '').trim();
  if (!cmd) return Promise.resolve('(empty command)');
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

/// 进程内执行内置工具；返回 null 表示"不是内置工具"，由 loop fall through 到 MCP。
export async function callBuiltinTool(name: string, input: any): Promise<string | null> {
  if (name === 'exec') return runExec(String(input?.command || ''));
  if (name === 'recall') return runRecall(input);
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
