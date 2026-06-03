#!/usr/bin/env bun
/**
 * VPS Tools MCP Server
 * Exposes shell + filesystem tools to Anthropic via SSE transport.
 * Anthropic's API server connects directly to this endpoint.
 *
 * Endpoints:
 *   GET  /sse      → SSE stream (Anthropic connects here)
 *   POST /messages → message endpoint (SSE transport internal)
 *
 * Auth: Authorization: Bearer <MCP_AUTH_TOKEN>
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js"
import { SSEServerTransport } from "@modelcontextprotocol/sdk/server/sse.js"
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js"
import { createServer, type IncomingMessage, type ServerResponse } from "http"
import { execSync } from "child_process"
import {
  existsSync,
  readFileSync,
  writeFileSync,
  readdirSync,
  statSync,
} from "fs"
import { join } from "path"

const PORT = parseInt(process.env.VPS_MCP_PORT ?? "7891")
const AUTH_TOKEN = process.env.MCP_AUTH_TOKEN ?? ""

function checkAuth(req: IncomingMessage): boolean {
  if (!AUTH_TOKEN) return true
  const auth = (req.headers["authorization"] as string) ?? ""
  return auth === `Bearer ${AUTH_TOKEN}`
}

// ── MCP Server definition ────────────────────────────────────────────────────

const server = new Server(
  { name: "vps-tools", version: "1.0.0" },
  { capabilities: { tools: {} } }
)

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "exec_command",
      description: "Execute a shell command on the VPS and return stdout/stderr/exit code",
      inputSchema: {
        type: "object",
        properties: {
          command: { type: "string", description: "Shell command to execute" },
        },
        required: ["command"],
      },
    },
    {
      name: "read_file",
      description: "Read a file from the VPS filesystem (truncated to 50KB)",
      inputSchema: {
        type: "object",
        properties: {
          path: { type: "string", description: "Absolute file path" },
          line_start: { type: "number", description: "First line to read (1-based)" },
          line_end: { type: "number", description: "Last line to read (inclusive)" },
        },
        required: ["path"],
      },
    },
    {
      name: "write_file",
      description: "Write content to a file on the VPS filesystem",
      inputSchema: {
        type: "object",
        properties: {
          path: { type: "string", description: "Absolute file path" },
          content: { type: "string", description: "File content to write" },
        },
        required: ["path", "content"],
      },
    },
    {
      name: "list_directory",
      description: "List directory contents as a tree",
      inputSchema: {
        type: "object",
        properties: {
          path: { type: "string", description: "Absolute directory path" },
          max_depth: { type: "number", description: "Max tree depth (default: 2)" },
        },
        required: ["path"],
      },
    },
  ],
}))

server.setRequestHandler(CallToolRequestSchema, async (req) => {
  const { name, arguments: args } = req.params

  if (name === "exec_command") {
    const command = (args?.command as string) ?? ""
    try {
      const output = execSync(command, {
        timeout: 30_000,
        encoding: "utf8",
        stdio: ["pipe", "pipe", "pipe"],
      })
      return { content: [{ type: "text", text: `exit 0\n${output}` }] }
    } catch (e: any) {
      const stdout = e.stdout ?? ""
      const stderr = e.stderr ?? ""
      const code = e.status ?? 1
      return {
        content: [{
          type: "text",
          text: `exit ${code}\nstdout: ${stdout}\nstderr: ${stderr}`,
        }],
      }
    }
  }

  if (name === "read_file") {
    const filePath = (args?.path as string) ?? ""
    if (!existsSync(filePath)) {
      return { content: [{ type: "text", text: `Error: file not found: ${filePath}` }] }
    }
    let content = readFileSync(filePath, "utf8")
    const lineStart = args?.line_start as number | undefined
    const lineEnd = args?.line_end as number | undefined
    if (lineStart !== undefined || lineEnd !== undefined) {
      const lines = content.split("\n")
      const from = (lineStart ?? 1) - 1
      const to = lineEnd ?? lines.length
      content = lines.slice(from, to).join("\n")
    }
    // Truncate to 50KB
    const MAX = 50 * 1024
    if (content.length > MAX) {
      content = content.slice(0, MAX) + "\n[truncated]"
    }
    return { content: [{ type: "text", text: content }] }
  }

  if (name === "write_file") {
    const filePath = (args?.path as string) ?? ""
    const fileContent = (args?.content as string) ?? ""
    try {
      writeFileSync(filePath, fileContent, "utf8")
      return { content: [{ type: "text", text: `Written: ${filePath}` }] }
    } catch (e: any) {
      return { content: [{ type: "text", text: `Error: ${e.message}` }] }
    }
  }

  if (name === "list_directory") {
    const dirPath = (args?.path as string) ?? ""
    const maxDepth = (args?.max_depth as number) ?? 2

    function buildTree(p: string, depth: number, prefix: string): string {
      if (depth > maxDepth) return ""
      let result = ""
      try {
        const entries = readdirSync(p).sort()
        entries.forEach((entry, idx) => {
          const isLast = idx === entries.length - 1
          const connector = isLast ? "└── " : "├── "
          const childPrefix = isLast ? "    " : "│   "
          const fullPath = join(p, entry)
          let stat
          try { stat = statSync(fullPath) } catch { return }
          result += `${prefix}${connector}${entry}${stat.isDirectory() ? "/" : ""}\n`
          if (stat.isDirectory()) {
            result += buildTree(fullPath, depth + 1, prefix + childPrefix)
          }
        })
      } catch { /* permission denied etc */ }
      return result
    }

    if (!existsSync(dirPath)) {
      return { content: [{ type: "text", text: `Error: directory not found: ${dirPath}` }] }
    }
    const tree = `${dirPath}\n` + buildTree(dirPath, 1, "")
    return { content: [{ type: "text", text: tree }] }
  }

  return { content: [{ type: "text", text: `Unknown tool: ${name}` }] }
})

// ── HTTP Server ──────────────────────────────────────────────────────────────

// sessionId → transport (for /messages routing)
const transports = new Map<string, SSEServerTransport>()

const httpServer = createServer(async (req: IncomingMessage, res: ServerResponse) => {
  // Auth check
  if (!checkAuth(req)) {
    res.writeHead(403, { "Content-Type": "text/plain" })
    res.end("Forbidden")
    return
  }

  const url = new URL(req.url ?? "/", `http://localhost`)

  if (req.method === "GET" && url.pathname === "/sse") {
    // Establish SSE connection
    const transport = new SSEServerTransport("/messages", res)
    transports.set(transport.sessionId, transport)
    res.on("close", () => {
      transports.delete(transport.sessionId)
    })
    await server.connect(transport)
    return
  }

  if (req.method === "POST" && url.pathname === "/messages") {
    const sessionId = url.searchParams.get("sessionId") ?? ""
    const transport = transports.get(sessionId)
    if (!transport) {
      res.writeHead(404, { "Content-Type": "text/plain" })
      res.end("Session not found")
      return
    }
    await transport.handlePostMessage(req, res)
    return
  }

  if (req.method === "GET" && url.pathname === "/health") {
    res.writeHead(200, { "Content-Type": "application/json" })
    res.end(JSON.stringify({ status: "ok", sessions: transports.size }))
    return
  }

  res.writeHead(404, { "Content-Type": "text/plain" })
  res.end("Not found")
})

httpServer.listen(PORT, "127.0.0.1", () => {
  console.log(`vps-mcp server listening on 127.0.0.1:${PORT}`)
})
