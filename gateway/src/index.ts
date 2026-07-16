// admin 层包装 app（/api/admin/* 管理路由 + 通道 key 覆盖热加载），其余请求原样透传 app.ts
import app from './admin';
import { config } from './config';
import { startDecayTimer } from './memory/decay';
import { startDreamTimer } from './memory/dreamer';
import { startDesireTimer } from './memory/desire';
import { startMurmurTimer } from './memory/murmur';
import { keepCacheAlive } from './memory/keepalive';
import { pocketWSHandler, isPocketToken } from './pocket';

const server = Bun.serve({
  port: config.port,
  idleTimeout: 120, // 2分钟，给 Opus 4.7/4.8 足够的首 token 时间
  fetch(req, srv) {
    const url = new URL(req.url);
    // Pocket Browser：手机 App 经 wss /pocket/ws 注册执行端（token 走 query）
    if (url.pathname === '/pocket/ws') {
      const token = url.searchParams.get('token') || '';
      if (!isPocketToken(token)) return new Response('unauthorized', { status: 401 });
      if (srv.upgrade(req, { data: { kind: 'pocket' } })) return undefined as any;
      return new Response('upgrade failed', { status: 400 });
    }
    return app.fetch(req, srv);
  },
  websocket: pocketWSHandler,
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
