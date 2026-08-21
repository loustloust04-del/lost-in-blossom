import type { Hono } from 'hono';
import {
  loadPlaces, savePlaces, whichPlace, searchPlace,
  nearbySearch, routeTime, weatherForecast, distanceMeters, wgs84ToGcj02,
} from './geo';

/// 拿她最近一次上报的坐标
async function herCoords(): Promise<{ lat: number; lng: number } | null> {
  const { readFileSync } = await import('node:fs');
  const { join } = await import('node:path');
  try {
    const d = JSON.parse(readFileSync(join(process.cwd(), 'data', 'phone-status.json'), 'utf-8'));
    const rs = d.records || [];
    for (let i = rs.length - 1; i >= 0; i--) {
      if (rs[i].lat != null && rs[i].lon != null) return { lat: rs[i].lat, lng: rs[i].lon };
    }
  } catch { /* ignore */ }
  return null;
}

export const GEO_TOOLS = [
  {
    name: 'where_is_she',
    description: '她现在在哪——不只是地名，还会告诉你她在不在你们熟悉的地方（家、精神卫生中心…）、离家多远、周围有什么店。想知道她此刻的处境时看这个。',
    input_schema: { type: 'object' as const, properties: {} },
  },
  {
    name: 'nearby',
    description: '她周围有什么。不填 keyword 就给最近的几家店；填了就找特定的——「药店」「便利店」「咖啡」「餐厅」都行。她说饿了、想喝东西、要买药的时候可以顺手查。',
    input_schema: {
      type: 'object' as const,
      properties: {
        keyword: { type: 'string', description: '想找什么，比如「药店」「奶茶」' },
        radius: { type: 'number', description: '搜索半径（米），默认 1000' },
      },
    },
  },
  {
    name: 'how_far',
    description: '她从现在的位置到某个地方要多久（开车）。填 place 用常用地点的名字（家/精神卫生中心），或者直接填地名让高德搜。',
    input_schema: {
      type: 'object' as const,
      properties: { place: { type: 'string', description: '目的地：常用地点名，或任意地名' } },
      required: ['place'],
    },
  },
  {
    name: 'weather_ahead',
    description: '她所在地的天气：今天、明天、后天。想提醒她带伞加衣服时用。',
    input_schema: { type: 'object' as const, properties: {} },
  },
  {
    name: 'place_add',
    description: '记住一个常用地点——以后她到那儿，where_is_she 会直接告诉你「她在XX」而不是一串地名。填名字（家/公司/奶奶家）和地址关键词，高德会去搜坐标。',
    input_schema: {
      type: 'object' as const,
      properties: {
        name: { type: 'string', description: '你怎么称呼它，比如「奶奶家」' },
        keyword: { type: 'string', description: '地址或地点名，高德搜得到就行' },
        city: { type: 'string', description: '城市（可选，缩小范围用）' },
        radius: { type: 'number', description: '多近算「到了」，米，默认 300' },
      },
      required: ['name', 'keyword'],
    },
  },
];

export async function callGeoTool(name: string, input?: any): Promise<string | null> {
  if (!GEO_TOOLS.some(t => t.name === name)) return null;

  const c = await herCoords();
  if (!c && name !== 'place_add') {
    return '还不知道她在哪——她手机还没报过带坐标的位置。可以用 request_location 问一次。';
  }

  if (name === 'where_is_she') {
    const hit = whichPlace(c!.lat, c!.lng);
    const lines: string[] = [];
    if (hit) {
      lines.push(`她在${hit.place.name}${hit.place.alias ? `（${hit.place.alias}）` : ''}，离中心 ${hit.distance} 米。`);
    } else {
      const places = loadPlaces();
      const g = wgs84ToGcj02(c!.lat, c!.lng);
      const dists = Object.values(places).map(p =>
        `离${p.name} ${(distanceMeters(g.lat, g.lng, p.lat, p.lng) / 1000).toFixed(1)} 公里`);
      lines.push('她不在你们熟悉的地方。' + (dists.length ? '（' + dists.join('，') + '）' : ''));
    }
    const near = await nearbySearch(c!.lat, c!.lng, '', 300);
    if (near.length) lines.push('\n周围：\n' + near.slice(0, 5).map(s => '· ' + s).join('\n'));
    return lines.join('\n');
  }

  if (name === 'nearby') {
    const kw = String(input?.keyword ?? '').trim();
    const r = Math.min(Math.max(Number(input?.radius ?? 1000), 100), 5000);
    const list = await nearbySearch(c!.lat, c!.lng, kw, r);
    if (!list.length) return kw ? `${r} 米内没找到「${kw}」。` : '周围没搜到什么。';
    return (kw ? `她周围的${kw}：\n` : '她周围：\n') + list.map(s => '· ' + s).join('\n');
  }

  if (name === 'how_far') {
    const q = String(input?.place ?? '').trim();
    const places = loadPlaces();
    let target: { name: string; lat: number; lng: number } | null = null;
    for (const p of Object.values(places)) {
      if (p.name === q || p.alias === q) { target = { name: p.name, lat: p.lat, lng: p.lng }; break; }
    }
    if (!target) {
      const found = await searchPlace(q, '三门峡');
      if (found) target = { name: found.name, lat: found.lat, lng: found.lng };
    }
    if (!target) return `没找到「${q}」。`;
    const rt = await routeTime(c!.lat, c!.lng, target.lat, target.lng);
    if (!rt) return `查不到到${target.name}的路线。`;
    return `从她现在的位置到${target.name}：开车约 ${rt.min} 分钟，${rt.km} 公里。`;
  }

  if (name === 'weather_ahead') {
    const w = await weatherForecast(c!.lat, c!.lng);
    return w ?? '天气查不到。';
  }

  if (name === 'place_add') {
    const nm = String(input?.name ?? '').trim();
    const kw = String(input?.keyword ?? '').trim();
    if (!nm || !kw) return '要名字和地址关键词。';
    const found = await searchPlace(kw, String(input?.city ?? ''));
    if (!found) return `高德没搜到「${kw}」，换个说法试试？`;
    const places = loadPlaces();
    const key = 'p' + Date.now().toString(36);
    places[key] = {
      name: nm, alias: found.name, lat: found.lat, lng: found.lng,
      radius: Math.min(Math.max(Number(input?.radius ?? 300), 50), 2000),
    };
    savePlaces(places);
    return `记住了：${nm} = ${found.name}${found.address ? '（' + found.address + '）' : ''}。以后她到那儿我会认出来。`;
  }
  return null;
}

export function geoRoutes(app: Hono) {
  app.get('/api/places', async (c) => c.json({ places: loadPlaces() }));
}
