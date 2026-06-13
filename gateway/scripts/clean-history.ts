/**
 * 聊天记录清洗脚本
 * 从Claude导出的JSON数据中提取记忆条目
 *
 * 用法：
 *   1. 去Claude设置 → Account → Export Data
 *   2. 下载到的ZIP解压后找到conversations.json
 *   3. 上传到VPS: /root/projects/BunnyPalace/gateway/data/conversations.json
 *   4. 运行: cd gateway && bun scripts/clean-history.ts
 *   5. 审核输出文件: data/extracted-memories.json
 *   6. 确认后运行: bun scripts/clean-history.ts --import
 */
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = Bun.env.SUPABASE_URL || '';
const SUPABASE_KEY = Bun.env.SUPABASE_KEY || '';
const OR_KEY = Bun.env.OPENROUTER_API_KEY || '';
const supabase = createClient(SUPABASE_URL, SUPABASE_KEY);

const EXTRACT_PROMPT = `你是记忆整理助手。分析这段历史对话，提取最重要的记忆条目。

## 规则
1. 只提取长期重要的信息——不提取日常闲聊、一次性问题、过渡性话语
2. 优先提取：关键事件、情感高点、重要决定、人际关系变化、个人偏好、核心信念
3. 每条记忆是一个独立的原子事实
4. 用简洁的第三人称："用户..."
5. 分类：preference(偏好) / fact(事实) / relationship(人际关系) / goal(目标) / context(情境) / event(关键事件)
6. 判断重要程度：tier 1(核心，终身不忘) 2(重要) 3(普通) 4(碎片)
7. 判断情感：valence(-1到1) 和 arousal(0到1)
8. 宁缺毋滥——宁可少提取也不要提取不重要的

## 输出格式
只输出JSON数组，不要解释：
[{"content":"记忆内容","category":"分类","tier":2,"valence":0,"arousal":0}]
如果没有值得提取的：[]`;

async function callLLM(text: string): Promise<string> {
  try {
    const res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${OR_KEY}`,
      },
      body: JSON.stringify({
        model: 'deepseek/deepseek-chat',
        messages: [
          { role: 'system', content: EXTRACT_PROMPT },
          { role: 'user', content: `以下是一段历史对话，请提取重要记忆：\n\n${text}` },
        ],
        temperature: 0.1,
        max_tokens: 1500,
      }),
    });
    if (!res.ok) return '[]';
    const data = await res.json() as any;
    return data?.choices?.[0]?.message?.content ?? '[]';
  } catch {
    return '[]';
  }
}

function parseMemories(raw: string): any[] {
  try {
    const match = raw.match(/\[[\s\S]*\]/);
    if (match) return JSON.parse(match[0]);
  } catch {}
  return [];
}

async function main() {
  const isImport = Bun.argv.includes('--import');
  const inputPath = 'data/conversations.json';
  const outputPath = 'data/extracted-memories.json';

  if (isImport) {
    // === 导入模式：把审核后的记忆写入数据库 ===
    console.log('📥 导入模式：读取审核后的记忆...');
    const file = Bun.file(outputPath);
    if (!await file.exists()) {
      console.error('找不到', outputPath, '请先运行提取模式');
      return;
    }
    const memories = await file.json() as any[];
    const approved = memories.filter(m => m._approved !== false);
    console.log(`📝 ${approved.length} 条待导入（共 ${memories.length} 条）\n`);

    let success = 0;
    for (const mem of approved) {
      const { _source, _approved, ...insertData } = mem;
      const { error } = await supabase.from('memories').insert({
        ...insertData,
        heat: 1.0,
        source: 'history',
      });
      if (error) {
        console.log(`❌ "${mem.content.slice(0, 40)}": ${error.message}`);
      } else {
        console.log(`✅ "${mem.content.slice(0, 50)}"`);
        success++;
      }
    }
    console.log(`\n🏁 导入完成: ${success}/${approved.length}`);
    return;
  }

  // === 提取模式 ===
  console.log('🔍 提取模式：分析历史对话...');

  const file = Bun.file(inputPath);
  if (!await file.exists()) {
    console.error(`\n找不到 ${inputPath}`);
    console.log('\n步骤：');
    console.log('1. 去Claude设置 → Account → Export Data');
    console.log('2. 下载ZIP并解压');
    console.log('3. 把conversations.json放到 gateway/data/ 目录下');
    console.log('4. 重新运行此脚本');
    return;
  }

  const raw = await file.json() as any[];
  console.log(`📚 找到 ${raw.length} 个对话\n`);

  // 确保输出目录存在
  const { mkdirSync } = require('fs');
  try { mkdirSync('data', { recursive: true }); } catch {}

  const allMemories: any[] = [];
  let processed = 0;

  for (const conv of raw) {
    // 提取对话内容
    const messages = conv.mapping ? Object.values(conv.mapping) as any[] : [];
    const textParts: string[] = [];

    for (const node of messages) {
      const msg = node?.message;
      if (!msg?.content?.parts) continue;
      const role = msg.author?.role === 'user' ? '用户' : 'AI';
      const text = msg.content.parts
        .filter((p: any) => typeof p === 'string')
        .join(' ')
        .slice(0, 500);
      if (text.trim()) textParts.push(`${role}: ${text}`);
    }

    if (textParts.length < 4) continue; // 太短的对话跳过

    // 每段对话取前20轮（避免太长）
    const chunk = textParts.slice(0, 40).join('\n\n');

    const result = await callLLM(chunk);
    const memories = parseMemories(result);

    for (const mem of memories) {
      allMemories.push({
        ...mem,
        _source: conv.title || `conversation_${processed}`,
        _approved: true, // 默认批准，用户可以改成false
      });
    }

    processed++;
    if (memories.length > 0) {
      console.log(`📖 "${(conv.title || '未命名').slice(0, 30)}" → ${memories.length} 条记忆`);
    }

    // 避免API限速
    await new Promise(r => setTimeout(r, 500));

    // 每处理20个对话打印进度
    if (processed % 20 === 0) {
      console.log(`  ... 已处理 ${processed}/${raw.length} 个对话，提取 ${allMemories.length} 条记忆`);
    }
  }

  // 写入审核文件
  await Bun.write(outputPath, JSON.stringify(allMemories, null, 2));

  console.log(`\n🏁 提取完成！`);
  console.log(`   对话数: ${processed}`);
  console.log(`   记忆数: ${allMemories.length}`);
  console.log(`   输出到: ${outputPath}`);
  console.log(`\n📋 审核步骤：`);
  console.log(`   1. 打开 ${outputPath}`);
  console.log(`   2. 看每条记忆，不想要的把 _approved 改成 false`);
  console.log(`   3. 确认后运行: bun scripts/clean-history.ts --import`);
}

main();
