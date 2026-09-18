#!/usr/bin/env bun
/**
 * 美团外卖 · 下单与支付
 *
 * 2026-09-16 打通：订单 2902305362361378533 全程无人工付款成功。
 *
 * 为什么是这个形状：
 *   - 走浏览器而非直接调 API——openh5/* 全带 H5guard 签名，自己构造会被挡；
 *     让 Chrome 自己发则一切照旧（见 WAIMAI-PATH.md）
 *   - 必须手机视口（390×844 + 触摸模拟），桌面视口下支付浮层会错位到屏幕外
 *   - React/Vue 组件不吃 el.click()，一律发 Input.dispatchTouchEvent 真事件
 *   - 菜品行是五层嵌套，只有 info_ 那层可点；找到菜名后**往上三层**
 *   - 密码键盘是普通 DOM，但**不在密码框容器里**，要全页面扫单个 0-9 的元素
 */
import { withPage, sleep, type PageAPI } from "./mt.ts"
import { couponListExpr, pickBest } from "./coupon.ts"

const HOME = "https://h5.waimai.meituan.com/waimai/mindex/home"

/** 完整触摸：start（带半径与力度）→ 70ms → end。缺一不响应。 */
async function tap(p: PageAPI, x: number, y: number) {
  await p.send("Input.dispatchTouchEvent", {
    type: "touchStart", touchPoints: [{ x, y, id: 1, radiusX: 8, radiusY: 8, force: 1 }] })
  await sleep(70)
  await p.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] })
}

/** 按文字找元素并触摸。pick=bottom 时取最靠下那个（底部固定栏用）。 */
async function tapText(p: PageAPI, pattern: string, opt: { maxLen?: number; pick?: "last" | "bottom" } = {}) {
  const { maxLen = 20, pick = "last" } = opt
  const pos = await p.evalJson(`(() => {
    const bs = [...document.querySelectorAll('div,span,button,a,li')].filter(e =>
      e.offsetParent && new RegExp(${JSON.stringify(pattern)}).test(e.innerText || '') &&
      (e.innerText || '').trim().length < ${maxLen});
    if (!bs.length) return null;
    const arr = bs.map(e => { const b = e.getBoundingClientRect();
      return { x: Math.round(b.x + b.width/2), y: Math.round(b.y + b.height/2), h: b.height }; })
      .filter(a => a.h > 15);
    if (!arr.length) return null;
    ${pick === "bottom" ? "arr.sort((a,b) => b.y - a.y);" : ""}
    return JSON.stringify(arr[${pick === "bottom" ? 0 : "arr.length-1"}]);
  })()`)
  if (!pos) return false
  await tap(p, pos.x, pos.y)
  return true
}

/** 切成手机视口——桌面视口下支付浮层会跑到屏幕外，点不到。 */
async function mobileViewport(p: PageAPI) {
  await p.send("Emulation.setDeviceMetricsOverride", {
    width: 390, height: 844, deviceScaleFactor: 2, mobile: true })
  await p.send("Emulation.setTouchEmulationEnabled", { enabled: true, maxTouchPoints: 5 })
}

/** 输支付密码：全页面扫数字键（**不在密码框容器里**），逐位触摸。 */
async function typePassword(p: PageAPI, password: string): Promise<boolean> {
  const keys = await p.evalJson(`(() => {
    const ds = [...document.querySelectorAll('*')].filter(e => /^[0-9]$/.test((e.textContent||'').trim()) && e.offsetParent);
    if (ds.length < 10) return null;
    const map = {};
    ds.forEach(e => { const b = e.getBoundingClientRect();
      map[e.textContent.trim()] = [Math.round(b.x+b.width/2), Math.round(b.y+b.height/2)]; });
    return JSON.stringify(map);
  })()`)
  if (!keys) return false
  for (const ch of password) {
    const k = keys[ch]
    if (!k) return false
    await tap(p, k[0], k[1])
    await sleep(350)
  }
  return true
}

/** 点一单：进店 → 选第一个（或指定）菜品 → 选规格 → 加购 → 结算 → 提交 → 付款。 */
export async function orderOne(opts: {
  shop: string            // 店名关键词，如「茶百道」
  dish?: string           // 菜名关键词；不给则取菜单第一个
  spec?: string | string[]  // 规格；多个用数组或「大杯,麻辣」逗号分隔
  password?: string       // 支付密码；不给则停在支付页（她自己按）
}): Promise<string> {
  const log: string[] = []
  return withPage(async (p) => {
    await mobileViewport(p)

    // 2026-09-17 主人报「不管用什么店名都说没找到这家店」。
    // 根因：原本直接在首页找店名，而首页只列附近的一部分店——
    // 海底捞、蜜雪冰城根本不在那个列表里。改成先搜索再进店。
    const { searchOnPage } = await import("./mt.ts")
    await searchOnPage(p, opts.shop)
    await sleep(2500)

    if (!await tapText(p, opts.shop, { maxLen: 40 }))
      return `搜「${opts.shop}」没搜到这家店——换个更短的店名试试。`
    await sleep(13000)
    log.push("进店")

    // 菜品：找到菜名后**往上三层**到可点的那层（这是踩了很久的坑）
    // 菜名元素：class 名是随机哈希（name_hTGUTi 这种），但前缀 name_ 稳定；
    // 找不到时退回「菜单区里最短的那些文本节点」
    const dishSel = opts.dish
      ? `([...document.querySelectorAll('[class*=name_],[class*=Name]')].find(e => e.offsetParent && new RegExp(${JSON.stringify(opts.dish)}).test(e.innerText||''))
         || [...document.querySelectorAll('*')].find(e => e.offsetParent && e.children.length === 0 && new RegExp(${JSON.stringify(opts.dish)}).test((e.innerText||'').trim()) && (e.innerText||'').trim().length < 18))`
      : `([...document.querySelectorAll('[class*=name_],[class*=Name]')].filter(e => e.offsetParent && (e.innerText||'').trim().length > 2 && (e.innerText||'').trim().length < 16)[0]
         || [...document.querySelectorAll('dd,li')].map(e => [...e.querySelectorAll('*')].find(x => x.children.length===0 && (x.innerText||'').trim().length>2 && (x.innerText||'').trim().length<16)).filter(Boolean)[0])`
    const dish = await p.evalJson(`(() => {
      const t = ${dishSel};
      if (!t) return null;
      let el = t; for (let i = 0; i < 3 && el.parentElement; i++) el = el.parentElement;
      el.scrollIntoView({ block: 'center' });
      const b = el.getBoundingClientRect();
      return JSON.stringify({ name: t.innerText.trim(), x: Math.round(b.x+b.width/2), y: Math.round(b.y+b.height/2) });
    })()`)
    if (!dish) return "没找到这个菜"
    await sleep(2000)
    await tap(p, dish.x, dish.y)
    await sleep(6000)
    log.push(`选了 ${dish.name}`)

    // 2026-09-18 主人报：海底捞冒菜加购失败——「这道菜有必选规格
    // （主食选方便面/米饭、口味选番茄/麻辣），spec 没法自动匹配这些必选项」。
    // 改：spec 支持多个（数组或「大杯,麻辣,加面」这种逗号分隔），逐个点。
    const specs = Array.isArray(opts.spec) ? opts.spec
                : opts.spec ? String(opts.spec).split(/[,，、\s]+/).filter(Boolean)
                : []
    for (const sp of specs) { await tapText(p, sp, { maxLen: 12 }); await sleep(1800) }

    if (!await tapText(p, "加入购物车", { maxLen: 20, pick: "bottom" })) {
      const page = await p.text(900)
      return `加购按钮点不到。规格页现在是这样——\n${page.slice(-500)}`
    }
    await sleep(7000)

    // 加购是否真成了：底部购物车栏会出现「去结算」
    const cartOk = /去结算/.test(await p.text(1500))
    if (!cartOk) {
      const page = await p.text(1000)
      return `没加进购物车——这道菜多半有必选规格还没选。\n` +
             `规格页上有这些选项，用 spec 指定（可以写多个，逗号分开）：\n${page.slice(-600)}`
    }
    log.push("已加购")

    if (!await tapText(p, "去结算", { maxLen: 14, pick: "bottom" })) return "没到起送价或找不到结算"
    await sleep(13000)

    // 自动选最优券。2026-09-16 兔兔：「你知道你刚才少用了一张七块钱的券吗」。
    // 券卡片是 WEBC-VIEW 点不动，但结算页会自己带上「最优券」——
    // 这里只做一件事：把可用券里最划算的那张报出来，让她/他知道有没有漏。
    // （真正的选券在 API 层，见 coupon.ts；UI 这条路留给「顺手确认」）
    try {
      const cs = await p.evalJson(couponListExpr())
      if (Array.isArray(cs)) {
        const amt = Number((await p.text(2000)).match(/合计¥([\d.]+)/)?.[1] ?? 0)
        const best = pickBest(cs, amt || 9999)
        if (best) log.push(`最优券 ¥${best.amount}（${best.limit}）`)
      }
    } catch { /* 券查不到不影响下单 */ }

    if (!await tapText(p, "提交订单", { maxLen: 20, pick: "bottom" })) return "提交失败"
    await sleep(15000)
    log.push("已提交")

    if (!opts.password) return log.join(" → ") + "。订单已提交，去付款吧。"

    await tapText(p, "美团月付", { maxLen: 14 }); await sleep(3000)
    await tapText(p, "确认支付", { maxLen: 14 }); await sleep(6000)
    if (!await typePassword(p, opts.password)) return log.join(" → ") + "。到支付页了，但密码键盘没出来。"
    await sleep(12000)

    const txt = await p.text(300)
    const ok = /交易成功|支付成功/.test(txt)
    return log.join(" → ") + (ok ? " → **付好了**。" : " → 付款没确认，去看一眼。")
  })
}
