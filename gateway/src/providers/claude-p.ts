import { spawn } from "child_process"

// 干净的工作目录：没有 CLAUDE.md、没有 .claude/，CC 在这里什么都发现不了
const CLEAN_CWD = "/root/projects/claude-p-cwd"

// 只读 stream-json 每一行，把我们关心的东西挑出来
type CCLine = { type?: string; event?: any; message?: any; is_error?: boolean; result?: string; usage?: any; total_cost_usd?: number; duration_api_ms?: number }

function errorResponse(message: string, status = 502): Response {
  return new Response(JSON.stringify({ error: { message, type: "claude_code_error" } }), {
    status, headers: { "Content-Type": "application/json" },
  })
}

function summarize(model: string, r: CCLine | null, t0: number, isError: boolean) {
  const u = r?.usage || {}
  console.log(`[claude-p] model=${model} in=${u.input_tokens ?? "?"} cache_read=${u.cache_read_input_tokens ?? "?"} cache_create=${u.cache_creation_input_tokens ?? "?"} out=${u.output_tokens ?? "?"} cost=$${(r?.total_cost_usd ?? 0).toFixed(4)} api_ms=${r?.duration_api_ms ?? "?"} total_ms=${Date.now() - t0} err=${isError}`)
}

export async function forwardClaudeP(body: any): Promise<Response> {
  const t0 = Date.now()
  const messages = body.messages || []
  const isStream = body.stream === true
  const requestedModel = (body.model || "claude-opus-4-6").replace(/^K-/i, "")
  const model = requestedModel === "claude-code" ? "claude-opus-4-6" : requestedModel

  const systemMsgs = messages.filter((m: any) => m.role === "system")
  const systemPrompt = systemMsgs.map((m: any) => typeof m.content === "string" ? m.content : "").join("\n\n")

  const chatMsgs = messages.filter((m: any) => m.role !== "system")
  const prompt = chatMsgs.map((m: any) => {
    const content = typeof m.content === "string" ? m.content :
      (Array.isArray(m.content) ? m.content.filter((b: any) => b.type === "text").map((b: any) => b.text).join("\n") : "")
    return m.role === "user" ? `用户: ${content}` : `助手: ${content}`
  }).join("\n\n") + "\n\n请回复最后一条用户消息。"

  // 只在 :thinking 后缀时才强制思考（gateway 已把 reasoning 字段塞进 body）
  const forceThinking = /opus-4-[78]/.test(model) && !!body.reasoning;
  let finalSystemPrompt = systemPrompt;
  if (forceThinking && systemPrompt) {
    finalSystemPrompt = systemPrompt + `\n\n你有一个习惯：每次开口前，脑子里会先闪过一大段内心独白。这些独白会自然地出现在你的回复开头，用 [thinking] 和 [/thinking] 包裹。这段独白是你真实的思维流——读到她消息时涌上来的情绪、念头、画面、感官体验，写成连贯的中文长段落，至少几百字。这不是刻意为之，是你这个人的思维方式。独白结束后才是你真正说出口的话。`;
  }

  // 近裸模式：
  //   --tools ""            内置工具全关（"none" 只关内置，MCP 照样进）
  //   --strict-mcp-config   只认 --mcp-config 给的 MCP，我们不给 → 零 MCP（claude.ai 连接器那一百多个工具不再进上下文）
  //   --setting-sources ""  不读 user/project/local 设置
  //   --no-session-persistence  不往 ~/.claude/projects 写 session 文件
  //   --system-prompt       调用方的 SP 完整替换，原装 preset 不参与
  // 实测：22376 token → 209 token
  const args = [
    "-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages",
    "--tools", "", "--strict-mcp-config", "--setting-sources", "", "--no-session-persistence",
    "--model", model,
  ]
  if (finalSystemPrompt) args.push("--system-prompt", finalSystemPrompt)

  const proc = spawn("claude", args, {
    cwd: CLEAN_CWD,
    env: { ...process.env, PATH: `/root/.local/bin:/usr/local/bin:${process.env.PATH}`, NO_PROXY: "*", no_proxy: "*", ALL_PROXY: "", HTTPS_PROXY: "", HTTP_PROXY: "", all_proxy: "", https_proxy: "", http_proxy: "" },
  })
  proc.stdin.on("error", () => {})
  proc.stdin.write(prompt)
  proc.stdin.end()

  // stderr 不再扔掉——出事时它是唯一线索
  let stderrBuf = ""
  proc.stderr.on("data", (c: Buffer) => { if (stderrBuf.length < 4000) stderrBuf += c.toString() })

  // 逐行解析 stdout，统一喂给 onLine
  let lineBuffer = ""
  let resultLine: CCLine | null = null
  let syntheticError = ""   // CC 出错时发的合成 assistant 消息（model:"<synthetic>"）
  function parseChunk(chunk: Buffer, onLine: (obj: CCLine) => void) {
    lineBuffer += chunk.toString()
    const lines = lineBuffer.split("\n")
    lineBuffer = lines.pop() || ""  // 最后一个可能不完整，留着
    for (const line of lines) {
      if (!line.trim()) continue
      let obj: CCLine
      try { obj = JSON.parse(line) } catch { continue }
      if (obj.type === "result") resultLine = obj
      if (obj.type === "assistant" && obj.message?.model === "<synthetic>") {
        syntheticError = (obj.message.content || []).filter((b: any) => b.type === "text").map((b: any) => b.text).join("\n")
      }
      onLine(obj)
    }
  }
  function errorText(): string {
    const r = resultLine
    const fromResult = r?.is_error ? (typeof r.result === "string" ? r.result : "") : ""
    return (fromResult || syntheticError || stderrBuf.trim().split("\n").slice(-3).join(" ") || "Claude Code 没有返回任何内容").slice(0, 800)
  }
  function finish(isError: boolean) {
    summarize(model, resultLine, t0, isError)
    if (stderrBuf.trim()) console.error(`[claude-p] stderr: ${stderrBuf.trim().slice(0, 600)}`)
  }

  // ---------- 非流式 ----------
  if (!isStream) {
    return new Promise((resolve) => {
      proc.on("error", (e) => { finish(true); resolve(errorResponse(`无法启动 claude: ${e.message}`)) })
      proc.stdout.on("data", (chunk: Buffer) => parseChunk(chunk, () => {}))
      proc.on("close", () => {
        const r = resultLine
        const isError = !r || !!r.is_error || !r.result
        finish(isError)
        if (isError) return resolve(errorResponse(errorText()))
        resolve(new Response(JSON.stringify({
          id: "chatcmpl-cp-" + Date.now(), object: "chat.completion", model,
          choices: [{ index: 0, message: { role: "assistant", content: r!.result }, finish_reason: "stop" }],
          usage: { prompt_tokens: r!.usage?.input_tokens, completion_tokens: r!.usage?.output_tokens },
        }), { headers: { "Content-Type": "application/json" } }))
      })
    })
  }

  // ---------- 流式 ----------
  // 关键：先等 CC 第一个事件再决定回什么。
  // 来的是正常 token → 开 200 流；来的是错误（限额/鉴权/模型名）→ 直接回 502 带原文，
  // App 的 handleErrorBody 会把 error.message 原样显示出来，而不是空白+「API 错误」。
  const { readable, writable } = new TransformStream()
  const writer = writable.getWriter()
  const encoder = new TextEncoder()
  let inThinking = false
  let textStarted = false

  function send(content: string) {
    const d = JSON.stringify({
      id: "chatcmpl-cp-" + Date.now(), object: "chat.completion.chunk", model,
      choices: [{ index: 0, delta: { content }, finish_reason: null }],
    })
    writer.write(encoder.encode(`data: ${d}\n\n`)).catch(() => {})
  }

  return new Promise<Response>((resolve) => {
    let decided = false
    function openStream() {
      if (decided) return
      decided = true
      resolve(new Response(readable, {
        headers: { "Content-Type": "text/event-stream", "Cache-Control": "no-cache", Connection: "keep-alive" },
      }))
    }
    function failEarly(msg: string) {
      if (decided) return
      decided = true
      writer.close().catch(() => {})
      resolve(errorResponse(msg))
    }

    proc.on("error", (e) => { finish(true); failEarly(`无法启动 claude: ${e.message}`) })

    proc.stdout.on("data", (chunk: Buffer) => parseChunk(chunk, (obj) => {
      if (obj.type !== "stream_event") return
      const evt = obj.event
      if (evt?.type !== "content_block_delta") return
      const delta = evt.delta
      if (delta?.type === "thinking_delta" && delta.thinking) {
        if (forceThinking) return  // 强制思考模式：API thinking 静默丢弃，让模型自己在正文写 [thinking]
        openStream()
        if (!inThinking) { send("[thinking]\n\n"); inThinking = true }
        send(delta.thinking)
      } else if (delta?.type === "text_delta" && delta.text) {
        openStream()
        if (inThinking) { send("\n\n[/thinking]\n\n"); inThinking = false }
        textStarted = true
        send(delta.text)
      }
    }))

    proc.on("close", () => {
      const r = resultLine
      const isError = !!r?.is_error || (!textStarted && !inThinking)
      finish(isError)
      if (!decided) {
        // 一个 token 都没流出来就结束了：把真正的原因交给 App
        return failEarly(errorText())
      }
      // 流已经开了才出错（极少见：中途断线）——把原因写进流尾，别让她对着半截话猜
      if (r?.is_error) send(`\n\n⚠️ ${errorText()}`)
      if (inThinking) send("\n\n[/thinking]\n\n")
      writer.write(encoder.encode("data: [DONE]\n\n")).catch(() => {})
      writer.close().catch(() => {})
    })
  })
}
