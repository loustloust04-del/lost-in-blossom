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
    description: "Reply to a Memory Palace channel message. Use this when responding to <channel source=\"memorypalace\"> input.",
    inputSchema: {
      type: "object",
      properties: {
        chat_id: { type: "string", description: "The chat_id from the <channel> tag" },
        content: { type: "string", description: "Your reply text" },
      },
      required: ["chat_id", "content"],
    },
  }],
}))

server.setRequestHandler(CallToolRequestSchema, async (req) => {
  if (req.params.name !== "reply") {
    throw new Error(`unknown tool: ${req.params.name}`)
  }
  const args = req.params.arguments as { chat_id: string; content: string }
  const ws = await ensureHub()
  ws.send(JSON.stringify({
    type: "reply",
    chat_id: args.chat_id,
    content: args.content,
  }))
  return { content: [{ type: "text", text: "ok" }] }
})

const transport = new StdioServerTransport()
await server.connect(transport)
