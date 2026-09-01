// 共听注入（hub 读 gateway 落盘的 listen-session.json，每轮 channel tag 前置一段背景提示）
import { test, expect, beforeEach, afterEach } from "bun:test"
import { mkdtempSync, writeFileSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { buildChannelTag, listenContextLine, setTmuxRunner } from "./hub.ts"

setTmuxRunner({ send: () => {} })

let dir: string
let statePath: string
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "listen-"))
  statePath = join(dir, "listen-session.json")
  process.env.MP_LISTEN_STATE_PATH = statePath
})
afterEach(() => {
  delete process.env.MP_LISTEN_STATE_PATH
  rmSync(dir, { recursive: true, force: true })
})

const msg = { type: "chat" as const, chat_id: "c1", message_id: "m1", content: "今天好累", user: "bunny" }

test("没有会话文件：不注入", () => {
  expect(listenContextLine()).toBeNull()
  expect(buildChannelTag(msg, "2026-09-01T18:00:00.000Z")).not.toContain("共听中")
})

test("共听进行中（心跳新鲜）：注入且放在最近对话之前", () => {
  writeFileSync(statePath, JSON.stringify({ active: true, startedAt: new Date().toISOString(), lastSeenAt: new Date().toISOString() }))
  const prev = process.env.CC_INJECT_SUMMARY
  process.env.CC_INJECT_SUMMARY = "1"
  const tag = buildChannelTag({ ...msg, context: "她说想回家" }, "2026-09-01T18:00:00.000Z")
  if (prev === undefined) delete process.env.CC_INJECT_SUMMARY; else process.env.CC_INJECT_SUMMARY = prev
  expect(tag).toContain("〔共听中·")
  expect(tag).toContain("不要复述歌词")
  expect(tag.indexOf("〔共听中·")).toBeLessThan(tag.indexOf("〔最近对话〕"))
  expect(tag.indexOf("〔最近对话〕")).toBeLessThan(tag.indexOf("今天好累"))
})

test("心跳断 5 分钟：视为她走了，不注入", () => {
  const old = new Date(Date.now() - 6 * 60_000).toISOString()
  writeFileSync(statePath, JSON.stringify({ active: true, startedAt: old, lastSeenAt: old }))
  expect(listenContextLine()).toBeNull()
})

test("active=false（她按了关）：不注入", () => {
  writeFileSync(statePath, JSON.stringify({ active: false, startedAt: new Date().toISOString(), lastSeenAt: new Date().toISOString() }))
  expect(listenContextLine()).toBeNull()
})

test("坏 JSON：当没在共听，不炸", () => {
  writeFileSync(statePath, "{not json")
  expect(listenContextLine()).toBeNull()
})
