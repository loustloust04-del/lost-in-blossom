import { spawn } from "child_process"

export async function forwardClaudeP(body: any): Promise<Response> {
  const messages = body.messages || []
  const isStream = body.stream === true

  // 提取 system prompt
  const systemMsgs = messages.filter((m: any) => m.role === "system")
  const systemPrompt = systemMsgs.map((m: any) => typeof m.content === "string" ? m.content : "").join("\n\n")

  // 格式化对话历史
  const chatMsgs = messages.filter((m: any) => m.role !== "system")
  const prompt = chatMsgs.map((m: any) => {
    const content = typeof m.content === "string" ? m.content :
      (Array.isArray(m.content) ? m.content.filter((b: any) => b.type === "text").map((b: any) => b.text).join("\n") : "")
    return m.role === "user" ? `用户: ${content}` : `助手: ${content}`
  }).join("\n\n") + "\n\n请回复最后一条用户消息。"

  // 构建参数：--tools none 省额度, --include-partial-messages 逐字流式
  const args = ["-p", "--output-format", "stream-json", "--verbose", "--tools", "none", "--include-partial-messages"]
  if (systemPrompt) {
    args.push("--append-system-prompt", systemPrompt)  // append保留模型身份
  }

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
          if (!line.trim()) continue
          try {
            const obj = JSON.parse(line)
            if (obj.type === "result" && obj.result) text = obj.result
          } catch {}
        }
        resolve(new Response(JSON.stringify({
          id: "chatcmpl-cp-" + Date.now(),
          object: "chat.completion",
          model: "claude-code",
          choices: [{ index: 0, message: { role: "assistant", content: text }, finish_reason: "stop" }],
        }), { headers: { "Content-Type": "application/json" } }))
      })
    })
  }

  // 流式：解析 stream_event 的 content_block_delta
  const { readable, writable } = new TransformStream()
  const writer = writable.getWriter()
  const encoder = new TextEncoder()

  proc.stdout.on("data", (chunk: Buffer) => {
    for (const line of chunk.toString().split("\n")) {
      if (!line.trim()) continue
      try {
        const obj = JSON.parse(line)
        if (obj.type === "stream_event" && obj.event?.type === "content_block_delta") {
          const delta = obj.event.delta
          let text = ""
          if (delta?.type === "text_delta" && delta.text) text = delta.text
          if (text) {
            const sseData = JSON.stringify({
              id: "chatcmpl-cp-" + Date.now(),
              object: "chat.completion.chunk",
              model: "claude-code",
              choices: [{ index: 0, delta: { content: text }, finish_reason: null }],
            })
            writer.write(encoder.encode(`data: ${sseData}\n\n`)).catch(() => {})
          }
        }
      } catch {}
    }
  })

  proc.stderr.on("data", () => {})
  proc.on("close", () => {
    writer.write(encoder.encode("data: [DONE]\n\n")).catch(() => {})
    writer.close().catch(() => {})
  })

  return new Response(readable, {
    headers: { "Content-Type": "text/event-stream", "Cache-Control": "no-cache", Connection: "keep-alive" },
  })
}
