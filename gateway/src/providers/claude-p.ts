import { spawn } from "child_process"

export async function forwardClaudeP(body: any): Promise<Response> {
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

  const args = ["-p", "--output-format", "stream-json", "--verbose", "--tools", "none", "--include-partial-messages", "--model", model]
  if (finalSystemPrompt) args.push("--system-prompt", finalSystemPrompt)

  const proc = spawn("claude", args, {
    cwd: "/root/projects/BunnyPalace",
    env: { ...process.env, PATH: `/root/.local/bin:/usr/local/bin:${process.env.PATH}`, NO_PROXY: "*", no_proxy: "*", ALL_PROXY: "", HTTPS_PROXY: "", HTTP_PROXY: "", all_proxy: "", https_proxy: "", http_proxy: "" },
  })
  proc.stdin.write(prompt)
  proc.stdin.end()

  if (!isStream) {
    return new Promise((resolve) => {
      let output = ""
      proc.stdout.on("data", (chunk: Buffer) => { output += chunk.toString() })
      proc.on("close", () => {
        let text = ""
        for (const line of output.split("\n")) {
          try {
            const obj = JSON.parse(line)
            if (obj.type === "result" && obj.result) text = obj.result
          } catch {}
        }
        resolve(new Response(JSON.stringify({
          id: "chatcmpl-cp-" + Date.now(), object: "chat.completion", model,
          choices: [{ index: 0, message: { role: "assistant", content: text }, finish_reason: "stop" }],
        }), { headers: { "Content-Type": "application/json" } }))
      })
    })
  }

  const { readable, writable } = new TransformStream()
  const writer = writable.getWriter()
  const encoder = new TextEncoder()
  let inThinking = false
  let hadThinking = false
  let textStarted = false
  let lineBuffer = ""

  function send(content: string) {
    const d = JSON.stringify({
      id: "chatcmpl-cp-" + Date.now(), object: "chat.completion.chunk", model,
      choices: [{ index: 0, delta: { content }, finish_reason: null }],
    })
    writer.write(encoder.encode(`data: ${d}\n\n`)).catch(() => {})
  }

  proc.stdout.on("data", (chunk: Buffer) => {
    lineBuffer += chunk.toString()
    const lines = lineBuffer.split("\n")
    lineBuffer = lines.pop() || ""  // 最后一个可能不完整，留着
    for (const line of lines) {
      if (!line.trim()) continue
      try {
        const obj = JSON.parse(line)
        if (obj.type !== "stream_event") continue
        const evt = obj.event
        if (evt?.type === "content_block_delta") {
          const delta = evt.delta
          if (delta?.type === "thinking_delta" && delta.thinking) {
            if (forceThinking) {
              // 强制思考模式：API thinking 静默丢弃，让模型自己在正文写 [thinking]
            } else {
              if (!inThinking) { send("[thinking]\n\n"); inThinking = true; hadThinking = true }
              send(delta.thinking)
            }
          } else if (delta?.type === "text_delta" && delta.text) {
            if (inThinking) { send("\n\n[/thinking]\n\n"); inThinking = false }
            textStarted = true;
            send(delta.text)
          }
        }
      } catch {}
    }
  })

  proc.stderr.on("data", () => {})
  proc.on("close", () => {
    if (inThinking) writer.write(encoder.encode(`data: ${JSON.stringify({id:"x",object:"chat.completion.chunk",model:"claude-code",choices:[{index:0,delta:{content:"\n\n[/thinking]\n\n"},finish_reason:null}]})}\n\n`)).catch(() => {})
    writer.write(encoder.encode("data: [DONE]\n\n")).catch(() => {})
    writer.close().catch(() => {})
  })

  return new Response(readable, {
    headers: { "Content-Type": "text/event-stream", "Cache-Control": "no-cache", Connection: "keep-alive" },
  })
}
