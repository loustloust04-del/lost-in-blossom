import { test, expect, beforeAll, afterAll } from "bun:test"
import { WebSocket } from "ws"

let hubProc: ReturnType<typeof Bun.spawn> | undefined

// hub 对所有连接（含 loopback）强制 token 鉴权
const TEST_TOKEN = "test-token-mcp"

beforeAll(async () => {
  hubProc = Bun.spawn(["bun", "run", "hub.ts"], {
    cwd: import.meta.dir,
    env: { ...process.env, MP_CC_TMUX_DRY_RUN: "1", MP_CC_HUB_TOKEN: TEST_TOKEN },
  })
  await new Promise(r => setTimeout(r, 400))
})

afterAll(() => hubProc?.kill())

test("MCP reply broadcasts to MP clients with matching chat_id and content", async () => {
  // 1. Open MP-side WS first
  const mp = new WebSocket(`ws://127.0.0.1:7890/cc?token=${TEST_TOKEN}`)
  await new Promise<void>((resolve, reject) => {
    mp.on("open", resolve)
    mp.on("error", reject)
    setTimeout(() => reject(new Error("mp connect timeout")), 2000)
  })

  const mpReceived = new Promise<{ type: string; chat_id: string; content: string }>(resolve => {
    mp.on("message", (data) => {
      const msg = JSON.parse(data.toString())
      if (msg.type === "reply") resolve(msg)
    })
  })

  // 2. Connect MCP-side WS, send reply
  const mcp = new WebSocket(`ws://127.0.0.1:7890/mcp?token=${TEST_TOKEN}`)
  await new Promise<void>((resolve, reject) => {
    mcp.on("open", resolve)
    mcp.on("error", reject)
    setTimeout(() => reject(new Error("mcp connect timeout")), 2000)
  })

  mcp.send(JSON.stringify({
    type: "reply",
    chat_id: "conv-test-1",
    content: "hi from cc",
  }))

  const reply = await mpReceived
  expect(reply.chat_id).toBe("conv-test-1")
  expect(reply.content).toBe("hi from cc")
  expect(reply.type).toBe("reply")

  mp.close()
  mcp.close()
})
