import { readFileSync } from "node:fs"
import { join } from "node:path"
import http2 from "node:http2"

const KEY_PATH = process.env.MP_APNS_KEY_PATH || join(import.meta.dir, "secrets", "AuthKey_PDAH2QTZ3W.p8")
const KEY_ID   = process.env.MP_APNS_KEY_ID   || "PDAH2QTZ3W"
const TEAM_ID  = process.env.MP_APNS_TEAM_ID  || "GQN42B462A"
const TOPIC    = process.env.MP_APNS_TOPIC    || "com.susu.MemoryPalace.ios"
const HOST     = process.env.MP_APNS_HOST     || "https://api.sandbox.push.apple.com"

export interface APNsResult {
  ok: boolean
  status?: number
  apnsId?: string
  error?: string
}

// ES256 JWT for APNs token-based auth (.p8 key)
let cachedToken: { jwt: string; iat: number } | null = null

async function getToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  // Reuse token if issued < 45 minutes ago (APNs tokens valid for 60 min)
  if (cachedToken && now - cachedToken.iat < 45 * 60) {
    return cachedToken.jwt
  }

  const header = { alg: "ES256", kid: KEY_ID }
  const payload = { iss: TEAM_ID, iat: now }

  const b64url = (obj: object) =>
    Buffer.from(JSON.stringify(obj)).toString("base64url")

  const unsigned = `${b64url(header)}.${b64url(payload)}`

  // Import PEM key
  const pem = readFileSync(KEY_PATH, "utf-8")
  const pemBody = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "")
  const keyData = Buffer.from(pemBody, "base64")

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    keyData,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  )

  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    cryptoKey,
    Buffer.from(unsigned),
  )

  const jwt = `${unsigned}.${Buffer.from(sig).toString("base64url")}`
  cachedToken = { jwt, iat: now }
  return jwt
}

export async function sendPush(
  deviceToken: string,
  title: string,
  body: string,
  chatId?: string,
): Promise<APNsResult> {
  let token: string
  try {
    token = await getToken()
  } catch (err: any) {
    return { ok: false, error: `jwt: ${err?.message ?? "unknown"}` }
  }

  return new Promise((resolve) => {
    const client = http2.connect(HOST)
    client.on("error", (err) => {
      resolve({ ok: false, error: `http2: ${err.message}` })
    })

    const apnsPayload = JSON.stringify({
      aps: {
        alert: { title, body },
        sound: "default",
      },
      ...(chatId ? { chat_id: chatId } : {}),
    })

    const req = client.request({
      ":method": "POST",
      ":path": `/3/device/${deviceToken}`,
      "authorization": `bearer ${token}`,
      "apns-topic": TOPIC,
      "apns-push-type": "alert",
      "content-type": "application/json",
      "content-length": Buffer.byteLength(apnsPayload),
    })

    let status = 0
    let apnsId = ""
    req.on("response", (headers) => {
      status = Number(headers[":status"] ?? 0)
      apnsId = String(headers["apns-id"] ?? "")
    })

    let responseBody = ""
    req.on("data", (chunk: Buffer) => { responseBody += chunk.toString() })

    req.on("end", () => {
      client.close()
      if (status === 200) {
        resolve({ ok: true, status, apnsId })
      } else {
        const errReason = (() => {
          try { return (JSON.parse(responseBody) as any).reason ?? responseBody }
          catch { return responseBody }
        })()
        resolve({ ok: false, status, apnsId, error: errReason })
      }
    })

    req.write(apnsPayload)
    req.end()
  })
}
