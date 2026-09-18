# 任务：查清楚美团加购为什么失败

派单人：Fable（2026-09-18）· 兔兔拍板派 Coder
预计：1-2 小时

## 一句话

`waimai_order` 走到「点加入购物车」那步就断了——**规格页明明开了，
按钮也点了，但购物车里没东西**。我试了五轮全在猜，需要有人把页面看清楚。

## 现状（已确认的事实，别重复验证）

跑 `bun /tmp/to.ts`（内容：`orderOne({shop:"茶百道", dish:"茉莉葡萄冰奶", spec:"大杯"})`）
会复现。链路前半段全是好的：

```
搜店 ✅ → 进店 ✅ → 点开菜品 ✅ → 规格页出现 ✅ → 点加购 ❌ 购物车空
```

**证据**（我实测过）：
- 点菜品后 `document.body.innerText.length` 从 4452 → 4743，页面确实变了
- 且 `[...document.querySelectorAll('div,span,button')].some(e => e.offsetParent &&
  /加入购物车/.test(e.innerText||''))` 返回 **true**
- 但加购后 `/去结算/.test(document.body.innerText)` 是 **false**
- 返回的页面文字仍是菜品描述，**没看到「份量/大杯/中杯/糖度」这些规格选项**

## 我今天改对但仍不够的三处（都已在代码里，别改回去）

1. **验证规格页开没开，只看「有没有加入购物车按钮」**
   —— 原先还要求出现「已选规格/份量」字样，但有些菜没有规格（如
   「超级杯水果茶(1L装)」），于是第一次点明明成功却被判失败
2. **要点两次「加入购物车」** —— 第一次弹规格，选完第二次才真加购
3. **必须完全相等匹配** `(e.innerText||'').trim() === '加入购物车'`
   —— 用正则 `.test()` 会命中「总计¥18\n加入购物车」这种整块容器，点它不触发

## 请你做的（**先看清楚，再改代码**）

我卡住的原因是一直在「改代码→跑两分钟→看结果」的循环里猜。
**请先手动走一遍，每一步把页面状态打出来**，像这样：

```
每次点击前后都记录：
- location.href
- document.body.innerText.length
- 页面上所有 innerText 完全等于「加入购物车」的元素：
  各自的 getBoundingClientRect()、className、DOM 顺序
- 有没有出现「大杯 / 中杯 / 份量 / 糖度 / 正常冰」这些规格选项文字
- 底部有没有「去结算」
```

**特别要回答的问题**：
- 点开菜品后出现的那个「加入购物车」，是**菜单行上的**还是**规格浮层里的**？
- 规格浮层（份量/糖度/温度）到底有没有弹出来？没弹的话，是什么动作才能弹？
- 如果有多个「加入购物车」，哪一个才是真按钮？（坐标、层级）

## 环境

- 代码：`/root/projects/BunnyPalace/cc-bridge/waimai/order.ts`（`orderOne`）
  与 `mt.ts`（`withPage` / `searchOnPage` / `shopMenu`）
- 浏览器：Chrome CDP `127.0.0.1:19825`，**美团已登录**（登录态在 user-data-dir 里）
- **必须手机视口**：`Emulation.setDeviceMetricsOverride` 390×844 + 触摸模拟；
  桌面视口下浮层会错位到屏幕外
- **组件不吃 `el.click()`**，一律 `Input.dispatchTouchEvent`
  （touchStart 带 radiusX/radiusY/force → 70ms → touchEnd）
- 背景全文见 `docs/WAIMAI-PATH.md`

## 边界（要紧）

- **不要真下单付款**。走到「加进购物车、底部出现去结算」就算成功，到此为止。
- 美团有软限流（「当前访问人数较多」），**两次尝试之间隔 10 秒以上**，别猛刷。
- 别动 `cc-bridge/mcp-server.ts` 之外的工具定义；改完 `git commit` 但**别 push**，
  我来确认。

## 交付

1. 一段「页面到底长什么样」的记录（上面那些问题的答案）
2. 改好的 `order.ts`，且实测能走到「底部出现去结算」
3. 把结论追加到 `docs/WAIMAI-PATH.md`
