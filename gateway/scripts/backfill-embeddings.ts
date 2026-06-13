/**
 * 批量补全脚本——给已有记忆生成embedding向量
 * 运行方式：cd gateway && bun scripts/backfill-embeddings.ts
 */
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = Bun.env.SUPABASE_URL || '';
const SUPABASE_KEY = Bun.env.SUPABASE_KEY || '';
const EMBEDDING_KEY = Bun.env.EMBEDDING_API_KEY || '';
const EMBEDDING_BASE = Bun.env.EMBEDDING_BASE_URL || 'https://api.deepseek.com/v1';
const EMBEDDING_MODEL = Bun.env.EMBEDDING_MODEL || 'deepseek-embedding';

const supabase = createClient(SUPABASE_URL, SUPABASE_KEY);

async function embed(text: string): Promise<number[]> {
  if (!EMBEDDING_KEY || EMBEDDING_KEY.length < 10) return [];
  try {
    const res = await fetch(`${EMBEDDING_BASE}/embeddings`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${EMBEDDING_KEY}`,
      },
      body: JSON.stringify({ model: EMBEDDING_MODEL, input: text }),
    });
    if (!res.ok) {
      console.error(`  embed API error: ${res.status} ${await res.text()}`);
      return [];
    }
    const data = await res.json() as any;
    return data?.data?.[0]?.embedding ?? [];
  } catch (e: any) {
    console.error(`  embed error: ${e.message}`);
    return [];
  }
}

async function backfill() {
  console.log('🔍 查找需要补全embedding的记忆...');
  console.log(`   嵌入API: ${EMBEDDING_BASE}`);
  console.log(`   模型: ${EMBEDDING_MODEL}`);

  const { data, error } = await supabase
    .from('memories')
    .select('id, content')
    .is('embedding', null)
    .order('created_at', { ascending: false });

  if (error) {
    console.error('查询失败:', error.message);
    return;
  }

  if (!data || data.length === 0) {
    console.log('✅ 所有记忆都已有embedding，无需补全');
    return;
  }

  console.log(`📝 找到 ${data.length} 条需要补全的记忆\n`);

  let success = 0;
  let failed = 0;

  for (const mem of data) {
    const vec = await embed(mem.content);
    if (vec.length > 0) {
      const { error: updateErr } = await supabase
        .from('memories')
        .update({ embedding: vec })
        .eq('id', mem.id);

      if (updateErr) {
        console.log(`❌ ${mem.id.slice(0, 8)}: ${updateErr.message}`);
        failed++;
      } else {
        console.log(`✅ ${mem.id.slice(0, 8)}: "${mem.content.slice(0, 50)}"`);
        success++;
      }
    } else {
      console.log(`⏭  ${mem.id.slice(0, 8)}: 嵌入API无响应，跳过`);
      failed++;
    }

    // 避免API限速
    await new Promise(r => setTimeout(r, 200));
  }

  console.log(`\n🏁 补全完成: ${success} 成功, ${failed} 失败, 共 ${data.length} 条`);
}

backfill();
