#!/usr/bin/env bun
/**
 * APNs sandbox push test.
 * Usage: bun run cc-bridge/test-push.ts <device-token>
 */
import { sendPush } from "./apns"

const token = process.argv[2]
if (!token) {
  console.error("Usage: bun run cc-bridge/test-push.ts <device-token>")
  process.exit(1)
}

console.log(`Sending test push to device: ${token.slice(0, 8)}...${token.slice(-4)}`)

const result = await sendPush(
  token,
  "🌸 推送测试",
  "Lost in Blossom 推送链路正常",
)

if (result.ok) {
  console.log(`✓ 成功 — HTTP ${result.status}, apns-id: ${result.apnsId}`)
} else {
  console.error(`✗ 失败 — HTTP ${result.status ?? "(no response)"}, error: ${result.error}`)
  process.exit(1)
}
