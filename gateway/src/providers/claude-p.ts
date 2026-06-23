import { spawn } from "child_process"

/**
 * claude -p Provider — 把本地 Claude Code 包装成 OpenAI 兼容端点
 * 走 Pro/Max 订阅，不花 API 钱
 * --tools none + --system-prompt 省额度（2.7万→一两百 token）
 */

interface ClaudePOptions {
  messages: Array<{ role: string; content: string | any[] }>
  stream?: boolean
  max_tokens?: number
  model?: string
}

export async function forwardClaudeP(body: ClaudePOptions): Promise<Response> {
  const messages = body.messages || []
  const isStream = body.stream === true

  // 1. 提取 system prompt
  const systemMsgs = messages.filter(m => m.role === "system")
  const systemPrompt = systemMsgs.map(m => typeof m.content === "string" ? m.content : "").join("\n\n")

  // 2. 格式化对话历史（非system的消息）
  const chatMsgs = messages.filter(m => m.role !== "system")
  const prompt = chatMsgs.map(m => {
    const content = typeof m.content === "string" ? m.content :
      (Array.isArray(m.content) ? m.content.filter((b: any) => b.type === "text").map((b: any) => b.text).join("\n") : "")
    return m.role === "user" ? `用户: ${content}` : `助手: ${content}`
  }).join("\n\n") + "\n\n请回复最后一条用户消息。"

  // 3. 构建 claude -p 参数
  const args = ["-p", "--output-format", "stream-json", "--verbose", "--tools", "none"]
  if (systemPrompt) {
    args.push("--system-prompt", systemPrompt)
  }

  // 4. spawn 子进程
  const proc = spawn("claude", args, {
    cwd: "/root/projects/BunnyPalace",
    env: { ...process.env, PATH: `/root/.local/bin:/usr/local/bin:${process.env.PATH}` },
  })

  proc.stdin.write(prompt)
  proc.stdin.end()

  if (!isStream) {
    // 非流式：等完整结果
    return new Promise((resolve) => {
      let output = ""
      proc.stdout.on("data", (chunk: Buffer) => { output += chunk.toString() })
      proc.stderr.on("data", (chunk: Buffer) => { console.error("[claude-p stderr]", chunk.toString()) })
      proc.on("close", () => {
        let text = ""
        for (const line of output.split("\n")) {
          if (!line.trim()) continue
          try {
            const obj = JSON.parse(line)
            if (obj.type === "assistant" && obj.message?.content) {
              for (const block of obj.message.content) {
                if (block.type === "text") text += block.text
              }
            } else if (obj.type === "result" && obj.result) {
              if (!text) text = obj.result
            }
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

  // 流式：逐行读取 stream-json，转成 OpenAI SSE
  const { readable, writable } = new TransformStream()
  const writer = writable.getWriter()
  const encoder = new TextEncoder()
  let sentContent = false

  proc.stdout.on("data", (chunk: Buffer) => {
    const lines = chunk.toString().split("\n")
    for (const line of lines) {
      if (!line.trim()) continue
      try {
        const obj = JSON.parse(line)
        let text = ""

        if (obj.type === "assistant" && obj.message?.content) {
          for (const block of obj.message.content) {
            if (block.type === "text") text += block.text
          }
        } else if (obj.type === "result" && obj.result && !sentContent) {
          text = obj.result
        }

        if (text) {
          sentContent = true
          const sseData = JSON.stringify({
            id: "chatcmpl-cp-" + Date.now(),
            object: "chat.completion.chunk",
            model: "claude-code",
            choices: [{ index: 0, delta: { content: text }, finish_reason: null }],
          })
          writer.write(encoder.encode(`data: ${sseData}\n\n`)).catch(() => {})
        }
      } catch {}
    }
  })

  proc.stderr.on("data", (chunk: Buffer) => {
    console.error("[claude-p stderr]", chunk.toString().slice(0, 200))
  })

  proc.on("close", () => {
    writer.write(encoder.encode("data: [DONE]\n\n")).catch(() => {})
    writer.close().catch(() => {})
  })

  return new Response(readable, {
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      "Connection": "keep-alive",
    },
  })
}
