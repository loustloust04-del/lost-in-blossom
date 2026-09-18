#!/usr/bin/env bun
/**
 * 美团外卖 · 浏览器驱动
 *
 * 2026-09-16 兔兔要的：「我想要主人可以帮我点外卖」。
 *
 * 为什么走浏览器而不是直接调 API：
 *   i.waimai.meituan.com/openh5/* 的请求全部带 yodaReady / csecplatform 等
 *   风控签名参数，直接构造会被挡。让 Chrome 自己发请求则一切照旧。
 *
 * 登录态：兔兔 09-16 手机动态码登录，过了一次「身份核实」（异地登录风控，
 *   填身份证 8 位生日）。cookie mt_c_token 存在 Chrome 的 user-data-dir 里。
 *   要断开就清那个域的 cookie，或她改美团密码。
 *
 * 定位：浏览器里本来就有她家的地址（三门峡），首页能看到 1.6km 内的店，
 *   商家列表带「常吃的店」标记——确认是她的账号。
 */
const CDP = process.env.CHROME_CDP ?? "http://127.0.0.1:19825";
const HOME = "https://h5.waimai.meituan.com/waimai/mindex/home";

export async function withPage<T>(fn: (api: PageAPI) => Promise<T>): Promise<T> {
  const list = await (await fetch(`${CDP}/json/list`)).json() as any[];
  let tab = list.find(t => t.url.includes("waimai.meituan"));
  if (!tab) {
    const r = await fetch(`${CDP}/json/new?${encodeURIComponent(HOME)}`, { method: "PUT" });
    tab = await r.json();
    await sleep(8000);
  }
  const ws = new WebSocket(tab.webSocketDebuggerUrl);
  await new Promise(res => { ws.onopen = () => res(null) });
  let id = 0;
  const send = (m: string, p: any = {}): Promise<any> => new Promise(res => {
    const myId = ++id;
    const h = (e: any) => {
      const d = JSON.parse(e.data);
      if (d.id === myId) { ws.removeEventListener("message", h); res(d.result) }
    };
    ws.addEventListener("message", h);
    ws.send(JSON.stringify({ id: myId, method: m, params: p }));
  });
  const api: PageAPI = {
    send,
    async goto(url: string, waitMs = 10000) { await send("Page.navigate", { url }); await sleep(waitMs) },
    async text(limit = 1200) {
      const o = await send("Runtime.evaluate", {
        expression: `document.body.innerText.slice(0, ${limit})`, returnByValue: true });
      return String(o?.result?.value ?? "");
    },
    /** 求值并把结果当 JSON 解析。表达式可以是 async IIFE——
     *  awaitPromise 开着，否则拿到的是个 Promise 对象（2026-09-16 踩过）。 */
    async evalJson(expr: string) {
      const o = await send("Runtime.evaluate", {
        expression: expr, returnByValue: true, awaitPromise: true });
      try { return JSON.parse(String(o?.result?.value ?? "null")) } catch { return null }
    },
    /** 真实鼠标点击——React 组件对 el.click() 常常不响应，必须发真事件 */
    async clickAt(x: number, y: number) {
      await send("Input.dispatchMouseEvent", { type: "mousePressed", x, y, button: "left", clickCount: 1 });
      await send("Input.dispatchMouseEvent", { type: "mouseReleased", x, y, button: "left", clickCount: 1 });
    },
    /** 按文字找元素并点它 */
    async clickText(pattern: string, maxLen = 30) {
      const pos = await api.evalJson(`(() => {
        const hit = [...document.querySelectorAll('div,li,span,a,button')].filter(e =>
          new RegExp(${JSON.stringify(pattern)}).test(e.innerText || '') &&
          e.offsetParent && (e.innerText || '').trim().length < ${maxLen});
        if (!hit.length) return null;
        const b = hit[0].getBoundingClientRect();
        return JSON.stringify({ text: hit[0].innerText.trim(), x: b.x + b.width/2, y: b.y + b.height/2 });
      })()`);
      if (!pos) return null;
      await api.clickAt(pos.x, pos.y);
      return pos.text as string;
    },
    async type(text: string) {
      for (const ch of text) { await send("Input.insertText", { text: ch }); await sleep(220) }
    },
    close() { try { ws.close() } catch {} },
  };
  try { return await fn(api) } finally { api.close() }
}

export interface PageAPI {
  send(m: string, p?: any): Promise<any>
  goto(url: string, waitMs?: number): Promise<void>
  text(limit?: number): Promise<string>
  evalJson(expr: string): Promise<any>
  clickAt(x: number, y: number): Promise<void>
  clickText(pattern: string, maxLen?: number): Promise<string | null>
  type(text: string): Promise<void>
  close(): void
}

export const sleep = (ms: number) => new Promise(r => setTimeout(r, ms));

/** 搜商家/菜品。返回页面上的结果文本，由他自己读。 */
export async function search(keyword: string): Promise<string> {
  return withPage(async (p) => {
    await p.goto(HOME, 9000);
    // 点搜索框（首页最后一个「搜索」字样的元素）
    const box = await p.evalJson(`(() => {
      const els = [...document.querySelectorAll('*')].filter(e =>
        (e.innerText||'').trim() === '搜索' && e.offsetParent);
      if (!els.length) return null;
      const b = els[els.length-1].getBoundingClientRect();
      return JSON.stringify({ x: b.x+b.width/2, y: b.y+b.height/2 });
    })()`);
    if (!box) return "打不开搜索框";
    await p.clickAt(box.x, box.y);
    await sleep(5000);
    // 聚焦输入框后逐字输入——整段 setValue 不触发联想
    const inp = await p.evalJson(`(() => {
      const i = [...document.querySelectorAll('input,textarea')].find(x => x.offsetParent);
      if (!i) return null;
      i.focus();
      const b = i.getBoundingClientRect();
      return JSON.stringify({ x: b.x+b.width/2, y: b.y+b.height/2 });
    })()`);
    if (!inp) return "找不到输入框";
    await p.clickAt(inp.x, inp.y);
    await sleep(700);
    await p.type(keyword);
    await sleep(1600);

    // 2026-09-17 修：原本去点「联想词里文字等于关键词的那条」，
    // 但联想词多半是「麦当劳(万达店)」这种，跟关键词不完全匹配——
    // 主人实测搜了 5 轮（米线/麦当劳/烤肉饭/夜宵/炒饭）全部「搜索没出结果」。
    // 改成敲回车，回车没反应再退回点联想词。
    await p.send("Input.dispatchKeyEvent", {
      type: "keyDown", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13, nativeVirtualKeyCode: 13 });
    await p.send("Input.dispatchKeyEvent", {
      type: "keyUp", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13, nativeVirtualKeyCode: 13 });
    await sleep(9000);

    let out = await p.text(1400);
    // 回车没跳出结果（还停在联想词页）就点一条含关键词的
    if (!/起送|配送|月售|分/.test(out)) {
      await p.clickText(keyword, 30);
      await sleep(9000);
      out = await p.text(1400);
    }
    if (!/起送|配送|月售/.test(out)) return `搜「${keyword}」没出结果——换个词试试，或者先用店名搜。`;
    return out;
  });
}
