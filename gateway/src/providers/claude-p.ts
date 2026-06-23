import { spawn } from "child_process"

export async function forwardClaudeP(body: any): Promise<Response> {
  const messages = body.messages || []
  const isStream = body.stream === true

  const systemMsgs = messages.filter((m: any) => m.role === "system")
  const systemPrompt = systemMsgs.map((m: any) => typeof m.content === "string" ? m.content : "").join("\n\n")

  const chatMsgs = messages.filter((m: any) => m.role !== "system")
  const prompt = chatMsgs.map((m: any) => {
    const content = typeof m.content === "string" ? m.content :
      (Array.isArray(m.content) ? m.content.filter((b: any) => b.type === "text").map((b: any) => b.text).join("\n") : "")
    return m.role === "user" ? `用户: ${content}` : `助手: ${content}`
  }).join("\n\n") + "\n\n请回复最后一条用户消息。"

  const args = ["-p", "--output-format", "stream-json", "--verbose", "--tools", "none", "--include-partial-messages"]
  if (systemPrompt) args.push("--append-system-prompt", systemPrompt)

  const proc = spawn("claude", args, {
    cwd: "/root/projects/BunnyPalace",
    env: { ...process.env, PATH: `/root/.local/bin:/usr/local/bin:${process.env.PATH}` },
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
          id: "chatcmpl-cp-" + Date.now(), object: "chat.completion", model: "claude-code",
          choices: [{ index: 0, message: { role: "assistant", content: text }, finish_reason: "stop" }],
        }), { headers: { "Content-Type": "application/json" } }))
      })
    })
  }

  const { readable, writable } = new TransformStream()
  const writer = writable.getWriter()
  const encoder = new TextEncoder()
  let inThinking = false

  function send(content: string) {
    const d = JSON.stringify({
      id: "chatcmpl-cp-" + Date.now(), object: "chat.completion.chunk", model: "claude-code",
      choices: [{ index: 0, delta: { content }, finish_reason: null }],
    })
    writer.write(encoder.encode(`data: ${d}\n\n`)).catch(() => {})
  }

  proc.stdout.on("data", (chunk: Buffer) => {
    for (const line of chunk.toString().split("\n")) {
      if (!line.trim()) continue
      try {
        const obj = JSON.parse(line)
        if (obj.type !== "stream_event") continue
        const evt = obj.event
        if (evt?.type === "content_block_delta") {
          const delta = evt.delta
          if (delta?.type === "thinking_delta" && delta.thinking) {
            if (!inThinking) { send("[thinking]\n\n"); inThinking = true }
            send(delta.thinking)
          } else if (delta?.type === "text_delta" && delta.text) {
            if (inThinking) { send("\n\n[/thinking]\n\n"); inThinking = false }
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
