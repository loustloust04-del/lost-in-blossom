import type { Context, Next } from 'hono';
import { timingSafeEqual } from 'node:crypto';
import { config } from '../config';

// S3: 常量时间比较，避免时序侧信道；空 token 一律拒绝。
function safeEqual(a: string, b: string): boolean {
  const ab = Buffer.from(a);
  const bb = Buffer.from(b);
  if (ab.length !== bb.length) return false;
  return timingSafeEqual(ab, bb);
}

export async function auth(c: Context, next: Next) {
  const h = c.req.header('Authorization');
  if (!h?.startsWith('Bearer ')) return c.json({ error: 'unauthorized' }, 401);
  const token = h.slice(7);
  if (!config.gatewayToken || !safeEqual(token, config.gatewayToken)) {
    return c.json({ error: 'forbidden' }, 403);
  }
  await next();
}
