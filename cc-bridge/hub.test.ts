import { test, expect, beforeAll, afterAll } from "bun:test"
import { WebSocket } from "ws"
import { buildChannelTag, setTmuxRunner } from "./hub.ts"
// 仅对 in-process tmux 调用生效（目前没有 in-process 测试用到 tmux）。
// 集成测试由 spawn 子进程跑，子进程通过 MP_CC_TMUX_DRY_RUN=1 跳过真实 tmux。
setTmuxRunner({ send: () => {} })

let hubProcess: ReturnType<typeof Bun.spawn> | undefined

beforeAll(async () => {
  hubProcess = Bun.spawn(["bun", "run", "hub.ts"], {
    cwd: import.meta.dir,
    env: { ...process.env, MP_CC_TMUX_DRY_RUN: "1" },
  })
  await new Promise(r => setTimeout(r, 300))  // wait for hub startup
})

afterAll(() => {
  hubProcess?.kill()
})

test("hub accepts MP WebSocket connection on /cc", async () => {
  const ws = new WebSocket("ws://127.0.0.1:7890/cc")
  await new Promise<void>((resolve, reject) => {
    ws.on("open", resolve)
    ws.on("error", reject)
    setTimeout(() => reject(new Error("connect timeout")), 2000)
  })
  expect(ws.readyState).toBe(WebSocket.OPEN)
  ws.close()
})

test("hub acks send messages", async () => {
  const ws = new WebSocket("ws://127.0.0.1:7890/cc")
  await new Promise<void>((resolve, reject) => {
    ws.on("open", resolve)
    ws.on("error", reject)
    setTimeout(() => reject(new Error("connect timeout")), 2000)
  })

  ws.send(JSON.stringify({
    type: "send",
    chat_id: "test-conv-1",
    message_id: "msg-1",
    content: "hello",
    user: "susu",
  }))

  const ack = await new Promise<{ type: string; message_id: string }>((resolve) => {
    ws.on("message", (data) => resolve(JSON.parse(data.toString())))
  })

  expect(ack.type).toBe("ack")
  expect(ack.message_id).toBe("msg-1")
  ws.close()
})

test("buildChannelTag wraps message in channel xml", () => {
  const tag = buildChannelTag({
    type: "send",
    chat_id: "conv-1",
    message_id: "msg-1",
    content: "hello",
    user: "susu",
  }, "2026-05-18T03:00:00.000Z")

  expect(tag).toContain('source="memorypalace"')
  expect(tag).toContain('chat_id="conv-1"')
  expect(tag).toContain('message_id="msg-1"')
  expect(tag).toContain('user="susu"')
  expect(tag).toContain('ts="2026-05-18T03:00:00.000Z"')
  expect(tag).toContain("hello")
  expect(tag.startsWith("<channel")).toBe(true)
  expect(tag.endsWith("</channel>")).toBe(true)
})

test("buildChannelTag replaces newlines with spaces", () => {
  const tag = buildChannelTag({
    type: "send",
    chat_id: "c1",
    message_id: "m1",
    content: "line1\nline2\nline3",
    user: "susu",
  }, "2026-05-18T00:00:00.000Z")

  expect(tag).not.toContain("line1\nline2")
  expect(tag).toContain("line1 line2 line3")
})
