#!/usr/bin/env bun
import { Server } from "@modelcontextprotocol/sdk/server/index.js"
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js"
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js"
import { WebSocket } from "ws"

const HUB_URL = process.env.MP_CC_HUB_URL ?? "ws://127.0.0.1:7890/mcp"

let hubWS: WebSocket | null = null
let connectingPromise: Promise<WebSocket> | null = null

function ensureHub(): Promise<WebSocket> {
  if (hubWS && hubWS.readyState === WebSocket.OPEN) return Promise.resolve(hubWS)
  if (connectingPromise) return connectingPromise

  connectingPromise = new Promise((resolve, reject) => {
    const ws = new WebSocket(HUB_URL)
    hubWS = ws
    ws.on("open", () => { connectingPromise = null; resolve(ws) })
    ws.on("error", (err) => { connectingPromise = null; hubWS = null; reject(err) })
    ws.on("close", () => { hubWS = null })
  })
  return connectingPromise
}

const server = new Server(
  { name: "cc-bridge-mcp", version: "0.1.0" },
  { capabilities: { tools: {} } }
)

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [{
    name: "reply",
    description: "Reply to a Memory Palace channel message. Use this when responding to <channel source=\"memorypalace\"> input. If you called any imprint-memory tools while preparing your reply, list them in tool_calls so the iOS app can display them as tool cards.",
    inputSchema: {
      type: "object",
      properties: {
        chat_id: { type: "string", description: "The chat_id from the <channel> tag" },
        content: { type: "string", description: "Your reply text" },
        tool_calls: {
          type: "array",
          description: "Optional: MCP tool calls made while preparing this reply (e.g., imprint-memory queries)",
          items: {
            type: "object",
            properties: {
              name:       { type: "string", description: "Tool name, e.g. memory_search" },
              input_json: { type: "string", description: "JSON-encoded tool arguments" },
              result:     { type: "string", description: "Tool result summary" },
            },
            required: ["name"],
          },
        },
      },
      required: ["chat_id", "content"],
    },
  }],
}))

server.setRequestHandler(CallToolRequestSchema, async (req) => {
  if (req.params.name !== "reply") {
    throw new Error(`unknown tool: ${req.params.name}`)
  }
  const args = req.params.arguments as {
    chat_id: string
    content: string
    tool_calls?: Array<{ name: string; input_json?: string; result?: string }>
  }
  const ws = await ensureHub()

  // 先发 tool_event 让 iOS 渲染 ToolCallCardView，再发 reply
  if (args.tool_calls && args.tool_calls.length > 0) {
    for (const tc of args.tool_calls) {
      ws.send(JSON.stringify({
        type: "tool_event",
        chat_id: args.chat_id,
        tool_name: tc.name,
        input_json: tc.input_json ?? "{}",
        result: tc.result ?? "",
      }))
    }
  }

  ws.send(JSON.stringify({
    type: "reply",
    chat_id: args.chat_id,
    content: args.content,
  }))
  return { content: [{ type: "text", text: "ok" }] }
})

const transport = new StdioServerTransport()
await server.connect(transport)
