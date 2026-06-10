#!/usr/bin/env node
const { McpServer } = require('@modelcontextprotocol/sdk/server/mcp.js');
const { StdioServerTransport } = require('@modelcontextprotocol/sdk/server/stdio.js');
const { execSync } = require('child_process');
const { z } = require('zod');
const fs = require('fs');

const server = new McpServer({ name: "vps-tools", version: "1.0.0" });

server.tool(
  "exec_vps",
  "Run shell command on VPS and return output",
  { command: z.string().describe("Shell command to execute") },
  async ({ command }) => {
    try {
      const result = execSync(command, { timeout: 30000, encoding: 'utf-8', maxBuffer: 1024 * 1024 });
      return { content: [{ type: "text", text: result || "(no output)" }] };
    } catch (e) {
      return { content: [{ type: "text", text: `Error: ${e.message}\n${e.stderr || ''}` }] };
    }
  }
);

server.tool(
  "read_file",
  "Read a file from VPS",
  { path: z.string().describe("File path to read") },
  async ({ path: filePath }) => {
    try {
      const content = fs.readFileSync(filePath, 'utf-8');
      return { content: [{ type: "text", text: content.slice(0, 50000) }] };
    } catch (e) {
      return { content: [{ type: "text", text: `Error: ${e.message}` }] };
    }
  }
);

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}
main().catch(console.error);
