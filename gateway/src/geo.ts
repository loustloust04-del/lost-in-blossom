/// 坐标系转换 + 高德逆地理编码。
///
/// 实测（2026-08-22）：快捷指令「获取当前位置」给的是 **WGS-84**（标准 GPS）。
/// 直接送给高德会偏 559 米——高德把她所在的五原西路认成了 500 米外的电信家属院。
/// 所以给国内地图服务用之前必须转成 GCJ-02（火星坐标）。
///
/// 转换算法的坑：要先把经纬度减去参考点 105/35，网上很多实现漏了这步。
const AMAP_KEY = process.env.AMAP_KEY || '';

function outOfChina(lat: number, lng: number): boolean {
  return !(lng > 73.66 && lng < 135.05 && lat > 3.86 && lat < 53.55);
}

function transformLat(x: number, y: number): number {
  let r = -100 + 2 * x + 3 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * Math.sqrt(Math.abs(x));
  r += ((20 * Math.sin(6 * x * Math.PI) + 20 * Math.sin(2 * x * Math.PI)) * 2) / 3;
  r += ((20 * Math.sin(y * Math.PI) + 40 * Math.sin((y / 3) * Math.PI)) * 2) / 3;
  r += ((160 * Math.sin((y / 12) * Math.PI) + 320 * Math.sin((y * Math.PI) / 30)) * 2) / 3;
  return r;
}
function transformLng(x: number, y: number): number {
  let r = 300 + x + 2 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * Math.sqrt(Math.abs(x));
  r += ((20 * Math.sin(6 * x * Math.PI) + 20 * Math.sin(2 * x * Math.PI)) * 2) / 3;
  r += ((20 * Math.sin(x * Math.PI) + 40 * Math.sin((x / 3) * Math.PI)) * 2) / 3;
  r += ((150 * Math.sin((x / 12) * Math.PI) + 300 * Math.sin((x / 30) * Math.PI)) * 2) / 3;
  return r;
}

/// WGS-84 → GCJ-02
export function wgs84ToGcj02(lat: number, lng: number): { lat: number; lng: number } {
  if (outOfChina(lat, lng)) return { lat, lng };
  const a = 6378245.0, ee = 0.00669342162296594323;
  let dLat = transformLat(lng - 105.0, lat - 35.0);   // ← 减参考点，漏了就偏
  let dLng = transformLng(lng - 105.0, lat - 35.0);
  const radLat = (lat / 180.0) * Math.PI;
  let magic = Math.sin(radLat);
  magic = 1 - ee * magic * magic;
  const sqrtMagic = Math.sqrt(magic);
  dLat = (dLat * 180.0) / (((a * (1 - ee)) / (magic * sqrtMagic)) * Math.PI);
  dLng = (dLng * 180.0) / ((a / sqrtMagic) * Math.cos(radLat) * Math.PI);
  return { lat: lat + dLat, lng: lng + dLng };
}

export interface PlaceInfo {
  address: string;
  nearby: string[];
}

/// 逆地理编码：坐标 → 地址 + 附近有什么（自动转 GCJ-02）
export async function reverseGeocode(lat: number, lng: number): Promise<PlaceInfo | null> {
  if (!AMAP_KEY) return null;
  const g = wgs84ToGcj02(lat, lng);
  const url = `https://restapi.amap.com/v3/geocode/regeo?key=${AMAP_KEY}`
    + `&location=${g.lng.toFixed(6)},${g.lat.toFixed(6)}&extensions=all&radius=200`;
  try {
    const r = await fetch(url, { signal: AbortSignal.timeout(8000) });
    const d: any = await r.json();
    const re = d?.regeocode;
    if (!re) return null;
    return {
      address: String(re.formatted_address || ''),
      nearby: (re.pois || []).slice(0, 5).map((p: any) =>
        `${p.name}（${Math.round(Number(p.distance) || 0)}米）`),
    };
  } catch {
    return null;
  }
}

// ── 常用地点 ─────────────────────────────────────────────
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';

const PLACES_PATH = join(process.cwd(), 'data', 'places.json');

export interface KnownPlace {
  name: string; alias?: string;
  lat: number; lng: number;      // GCJ-02（高德搜出来的就是）
  radius: number;                // 米，进这个圈就算「到了」
  note?: string;
}

export function loadPlaces(): Record<string, KnownPlace> {
  try { return JSON.parse(readFileSync(PLACES_PATH, 'utf-8')); } catch { return {}; }
}
export function savePlaces(p: Record<string, KnownPlace>): void {
  mkdirSync(join(process.cwd(), 'data'), { recursive: true });
  writeFileSync(PLACES_PATH, JSON.stringify(p, null, 2), 'utf-8');
}

/// 两点距离（米）
export function distanceMeters(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371000;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a = Math.sin(dLat / 2) ** 2
    + Math.cos((lat1 * Math.PI) / 180) * Math.cos((lat2 * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  return Math.round(2 * R * Math.asin(Math.sqrt(a)));
}

/// 她现在在哪个常用地点里（传 WGS-84，内部转 GCJ-02 比对）
export function whichPlace(latWgs: number, lngWgs: number): { key: string; place: KnownPlace; distance: number } | null {
  const g = wgs84ToGcj02(latWgs, lngWgs);
  const places = loadPlaces();
  let best: { key: string; place: KnownPlace; distance: number } | null = null;
  for (const [key, p] of Object.entries(places)) {
    const d = distanceMeters(g.lat, g.lng, p.lat, p.lng);
    if (d <= p.radius && (!best || d < best.distance)) best = { key, place: p, distance: d };
  }
  return best;
}

/// 高德搜地点（给 place_add 用）
export async function searchPlace(keyword: string, city = ''): Promise<{ name: string; lat: number; lng: number; address: string } | null> {
  if (!AMAP_KEY) return null;
  const u = `https://restapi.amap.com/v3/place/text?key=${AMAP_KEY}`
    + `&keywords=${encodeURIComponent(keyword)}${city ? `&city=${encodeURIComponent(city)}&citylimit=true` : ''}&offset=1`;
  try {
    const r = await fetch(u, { signal: AbortSignal.timeout(8000) });
    const d: any = await r.json();
    const p = (d?.pois || [])[0];
    if (!p) return null;
    const [lng, lat] = String(p.location).split(',').map(Number);
    return { name: p.name, lat, lng, address: p.address || '' };
  } catch { return null; }
}

/// 附近有什么（分类可选：餐饮/药店/便利店…）
export async function nearbySearch(latWgs: number, lngWgs: number, keyword = '', radius = 1000): Promise<string[]> {
  if (!AMAP_KEY) return [];
  const g = wgs84ToGcj02(latWgs, lngWgs);
  const u = `https://restapi.amap.com/v3/place/around?key=${AMAP_KEY}`
    + `&location=${g.lng.toFixed(6)},${g.lat.toFixed(6)}&radius=${radius}&offset=8&sortrule=distance`
    + (keyword ? `&keywords=${encodeURIComponent(keyword)}` : '');
  try {
    const r = await fetch(u, { signal: AbortSignal.timeout(8000) });
    const d: any = await r.json();
    return (d?.pois || []).slice(0, 8).map((p: any) =>
      `${p.name}（${Math.round(Number(p.distance) || 0)}米${p.address ? '，' + p.address : ''}）`);
  } catch { return []; }
}

/// 路线用时（驾车），返回 {distance_km, duration_min}
export async function routeTime(fromLatWgs: number, fromLngWgs: number, toLat: number, toLng: number)
  : Promise<{ km: number; min: number } | null> {
  if (!AMAP_KEY) return null;
  const f = wgs84ToGcj02(fromLatWgs, fromLngWgs);
  const u = `https://restapi.amap.com/v3/direction/driving?key=${AMAP_KEY}`
    + `&origin=${f.lng.toFixed(6)},${f.lat.toFixed(6)}&destination=${toLng.toFixed(6)},${toLat.toFixed(6)}&extensions=base`;
  try {
    const r = await fetch(u, { signal: AbortSignal.timeout(8000) });
    const d: any = await r.json();
    const p = d?.route?.paths?.[0];
    if (!p) return null;
    return { km: Math.round(Number(p.distance) / 100) / 10, min: Math.round(Number(p.duration) / 60) };
  } catch { return null; }
}

/// 天气（今天 + 未来几天）
export async function weatherForecast(latWgs: number, lngWgs: number): Promise<string | null> {
  if (!AMAP_KEY) return null;
  const g = wgs84ToGcj02(latWgs, lngWgs);
  try {
    // 先用逆地理拿 adcode
    const r1 = await fetch(`https://restapi.amap.com/v3/geocode/regeo?key=${AMAP_KEY}&location=${g.lng.toFixed(6)},${g.lat.toFixed(6)}`,
      { signal: AbortSignal.timeout(8000) });
    const d1: any = await r1.json();
    const adcode = d1?.regeocode?.addressComponent?.adcode;
    if (!adcode) return null;
    const r2 = await fetch(`https://restapi.amap.com/v3/weather/weatherInfo?key=${AMAP_KEY}&city=${adcode}&extensions=all`,
      { signal: AbortSignal.timeout(8000) });
    const d2: any = await r2.json();
    const casts = d2?.forecasts?.[0]?.casts || [];
    if (!casts.length) return null;
    return casts.slice(0, 3).map((c: any, i: number) =>
      `${i === 0 ? '今天' : i === 1 ? '明天' : '后天'}：${c.dayweather}转${c.nightweather}，${c.nighttemp}~${c.daytemp}℃`
    ).join('\n');
  } catch { return null; }
}
