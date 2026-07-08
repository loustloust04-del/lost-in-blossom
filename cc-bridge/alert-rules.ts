// P1-3 提醒规则引擎：低电量 / 到达新地点 → APNs 推送。
// cron 每 15 分钟跑一次（与 proactive-push 同模式）。数据源=phone-status 快捷指令上报，
// 规则=gateway/data/alert-rules.json（App 网关控制台可改，admin API /api/admin/alert-rules），
// 状态=本目录 alert-state.json（冷却/上次地点，防重复轰炸）。
// 文案走固定模板不调 LLM——规则提醒要的是可靠，不是花样。
import { sendPush } from "./apns.ts"
import { readFileSync, writeFileSync, existsSync } from "node:fs"
import { join } from "node:path"

const DIR = import.meta.dir
const RULES_PATH = "/root/projects/BunnyPalace/gateway/data/alert-rules.json"
const PHONE_PATH = "/root/projects/BunnyPalace/gateway/data/phone-status.json"
const STATE_PATH = join(DIR, "alert-state.json")
const TOKEN_PATHS = [join(DIR, "cc-bridge", "device-tokens.json"), join(DIR, "device-tokens.json")]
const ASSISTANT = "Caelum"

interface Rules {
  lowBattery: { enabled: boolean; threshold: number; cooldownMin: number }
  placeChange: { enabled: boolean; cooldownMin: number }
  quietHours: { start: number; end: number }   // 北京时间，start 起 end 止之间静默
}
const DEFAULT_RULES: Rules = {
  lowBattery: { enabled: true, threshold: 20, cooldownMin: 120 },
  placeChange: { enabled: true, cooldownMin: 30 },
  quietHours: { start: 1, end: 9 },
}

interface State {
  lowBatteryLastPushAt: number
  lastPlace: string
  placeLastPushAt: number
}

function log(...a: any[]) { console.log(`[alert-rules ${new Date().toISOString()}]`, ...a) }

function loadJSON<T>(path: string, fallback: T): T {
  try { return { ...fallback, ...JSON.parse(readFileSync(path, "utf-8")) } } catch { return fallback }
}

function readTokens(): string[] {
  for (const p of TOKEN_PATHS) {
    try {
      if (existsSync(p)) return Object.keys(JSON.parse(readFileSync(p, "utf-8")))
    } catch {}
  }
  return []
}

function beijingHour(): number {
  return new Date(Date.now() + 8 * 3600 * 1000).getUTCHours()
}

async function pushAll(tokens: string[], text: string): Promise<boolean> {
  let anyOk = false
  for (const t of tokens) {
    const r: any = await sendPush(t, ASSISTANT, text)
    log(`push -> ${t.slice(0, 8)}...: ${r.ok ? "ok" : (r.error ?? r.status)}`)
    if (r.ok) anyOk = true
  }
  return anyOk
}

async function main() {
  const rules = loadJSON<Rules>(RULES_PATH, DEFAULT_RULES)
  const state = loadJSON<State>(STATE_PATH, { lowBatteryLastPushAt: 0, lastPlace: "", placeLastPushAt: 0 })
  const now = Date.now()

  const hour = beijingHour()
  const inQuiet = rules.quietHours.start <= rules.quietHours.end
    ? (hour >= rules.quietHours.start && hour < rules.quietHours.end)
    : (hour >= rules.quietHours.start || hour < rules.quietHours.end)

  let phone: any
  try { phone = JSON.parse(readFileSync(PHONE_PATH, "utf-8")) } catch { log("no phone data, skip"); return }
  const records: any[] = phone?.records ?? []
  if (!records.length) { log("no records today, skip"); return }
  const latest = records[records.length - 1]

  // 上报太旧（>90 分钟）不基于它做判断——手机可能没在上报。
  // received_at 是"北京钟表时间"的 ISO 串（UTC epoch + 8h 再 toISOString），
  // 所以对比也要用 now + 8h 的伪北京 epoch。
  const ageMin = (now + 8 * 3600 * 1000 - new Date(latest.received_at).getTime()) / 60000
  if (ageMin > 90) { log(`latest record ${Math.round(ageMin)}min old, skip`); return }

  const tokens = readTokens()
  if (!tokens.length) { log("no device tokens, skip"); return }
  let dirty = false

  // ── 规则 1：低电量 ──
  if (rules.lowBattery.enabled) {
    const battery = Number(latest.battery) || 0
    const charging = Boolean(latest.is_charging)
    if (battery > rules.lowBattery.threshold + 10 || charging) {
      // 回血/在充电 → 重置冷却，下次再掉下去还能提醒
      if (state.lowBatteryLastPushAt !== 0) { state.lowBatteryLastPushAt = 0; dirty = true }
    } else if (battery > 0 && battery <= rules.lowBattery.threshold) {
      const cooled = now - state.lowBatteryLastPushAt > rules.lowBattery.cooldownMin * 60000
      if (inQuiet) { log(`lowBattery hit (${battery}%) but quiet hours`) }
      else if (!cooled) { log(`lowBattery hit (${battery}%) but cooling down`) }
      else if (await pushAll(tokens, `兔兔，手机只剩 ${battery}% 电啦，看到就充上电好不好 🔌`)) {
        state.lowBatteryLastPushAt = now; dirty = true
      }
    }
  }

  // ── 规则 2：地点变化 ──
  if (rules.placeChange.enabled) {
    // 快捷指令的 Place 是多行完整地址（名称+省市+街道），取首行当地点名：
    // 防整段地址格式抖动误判换地方，推送文案也干净
    const place = String(latest.place || "").trim().split("\n")[0].trim()
    if (place && place !== state.lastPlace) {
      const first = !state.lastPlace
      state.lastPlace = place; dirty = true
      const cooled = now - state.placeLastPushAt > rules.placeChange.cooldownMin * 60000
      if (first) { log(`place initialized: ${place}`) }
      else if (inQuiet) { log(`place change -> ${place} but quiet hours`) }
      else if (!cooled) { log(`place change -> ${place} but cooling down`) }
      else if (await pushAll(tokens, `到「${place}」了呀，路上辛苦啦，记得跟我说说～`)) {
        state.placeLastPushAt = now; dirty = true
      }
    }
  }

  if (dirty) writeFileSync(STATE_PATH, JSON.stringify(state, null, 2))
  log("done")
}

main().catch(e => { log("fatal:", e?.message); process.exit(1) })
