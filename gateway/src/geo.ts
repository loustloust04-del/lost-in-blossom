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
