#!/usr/bin/env bun
/**
 * 美团红包/优惠券 · 自动选最优
 *
 * 2026-09-16 兔兔：「你没用优惠券啊血亏了」「你知道你刚才少用了一张七块钱的券吗」。
 * 当天解决——**券不在 UI 里选，在 API 里传一个字段。**
 *
 * 两个坑：
 *   1. 不传收货地址时所有券都不可用（status_tip 写着「填写地址后可选」）
 *   2. 券卡片是 WEBC-VIEW（美团小程序容器），鼠标触摸都点不动——别点它
 */

export interface Coupon {
  couponViewId: string
  couponId: number
  amount: number       // 减多少
  threshold: number    // 门槛（满多少可用），0 = 无门槛
  title: string
  limit: string
}

/** 拉全部可用券。页面里调，签名和 cookie 现成。 */
export function couponListExpr(): string {
  return `(async () => {
    const p = new URLSearchParams({ optimus_code:'10', optimus_risk_level:'71', data:'{}' });
    const r = await fetch('https://i.waimai.meituan.com/openh5/coupon/list?_=' + Date.now() +
      '&yodaReady=h5&csecplatform=4&csecversion=4.3.0', { method:'POST', credentials:'include',
      headers:{'Content-Type':'application/x-www-form-urlencoded'}, body:p.toString() });
    const j = await r.json();
    return JSON.stringify((j.data?.coupon_list || []).map(c => ({
      couponViewId: c.coupon_view_id, couponId: c.coupon_id,
      amount: c.amount, title: c.title || '', limit: c.price_limit || '',
      // 「满38可用」→ 38；无门槛 → 0
      threshold: Number((String(c.price_limit||'').match(/满\\s*([\\d.]+)/) || [,0])[1]),
      status: c.status,
    })));
  })()`
}

/** 挑最划算的一张：够得着门槛、金额最大。
 *  排除限定品类的——那些在结算时会被拒，白折腾一轮。 */
export function pickBest(coupons: any[], orderAmount: number): Coupon | null {
  const EXCLUDE = /宠物|药|酒饮|闪购便利店|生鲜|买菜|电影|酒店|门票/
  const ok = coupons.filter(c =>
    c.status === 1 &&
    c.amount > 0 &&
    c.threshold <= orderAmount &&
    !EXCLUDE.test(c.title))
  if (!ok.length) return null
  ok.sort((a, b) => b.amount - a.amount)
  return ok[0]
}

/** 选券时要塞进 preview/submit 的字段（三个都给，保险）。 */
export function couponFields(c: Coupon | null) {
  if (!c) return {}
  return {
    selected_coupon_view_id: c.couponViewId,
    coupon_view_id: c.couponViewId,
    selected_coupon_id: c.couponId,
  }
}
