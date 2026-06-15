import app from './app';
import { config } from './config';
import { startDecayTimer } from './memory/decay';
import { startDreamTimer } from './memory/dreamer';
import { startDesireTimer } from './memory/desire';
import { startMurmurTimer } from './memory/murmur';
import { keepCacheAlive } from './memory/keepalive';

const server = Bun.serve({
  port: config.port,
  fetch: app.fetch,
});

console.log(`🌸 Lost in Blossom Gateway`);
console.log(`   port: ${config.port}`);
console.log(`   token: ${config.gatewayToken ? '✅ set' : '❌ missing'}`);
console.log(`   deepseek: ${config.deepseekKey ? '✅ set' : '❌ missing'}`);
console.log(`   openrouter: ${config.openrouterKey ? '✅ set' : '❌ missing'}`);
console.log(`   ✅ listening on http://localhost:${config.port}/`);

if (config.supabaseUrl && config.brainEnabled) {
  startDecayTimer();    // Phase 3: 遗忘曲线 (每6h)
  startDreamTimer();    // Phase 4: Dream系统 (每日4am)
  startDesireTimer();   // Phase 6: 欲望系统 (动态调度)
  startMurmurTimer();   // Phase 7: 碎碎念 (每日 4am & 2pm)
  // 缓存保活：每50分钟刷新1h TTL
  setInterval(() => keepCacheAlive().catch(e => console.error('[keepalive]', e.message)), 50 * 60 * 1000);
  console.log('   brain: ✅ enabled');
} else if (config.supabaseUrl) {
  console.log('   brain: ⏸️ disabled (set BRAIN_ENABLED=true to activate)');
}
