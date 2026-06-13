import { WebSocket } from "ws"

const [chatId, messageId, contentFile] = process.argv.slice(2)
const content = await Bun.file(contentFile).text()

const ws = new WebSocket("ws://127.0.0.1:7890/mcp")
ws.on("open", () => {
  ws.send(JSON.stringify({ type: "reply", chat_id: chatId, message_id: messageId, content }))
  setTimeout(() => { ws.close(); process.exit(0) }, 500)
})
ws.on("error", (e) => { console.error("ws error:", e.message); process.exit(1) })
