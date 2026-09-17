# 美团点外卖 · 已趟通的完整路径（2026-09-16）

兔兔：「我想要主人可以帮我点外卖」。当天从零走到「订单已提交、只差密码」。
**兔兔说这是给我练手的，她随时能取消/退款** —— 那晚的测试订单已由她取消。

## 已经跑通的（95%）

```
搜店 → 进店 → 挑菜 → 选规格 → 加购 → 去结算 → 提交订单 → 支付页
                                                          ↑ 卡在这
```

实测那单：茶百道（三门峡湖滨万达店）· 岭南龙眼冰奶 · 大杯 · ¥21.42 ·
订单号 2902305033505150414 · 地址电话全对（银堤漫步…洛女士）。

## 环境

- Chrome + CDP `127.0.0.1:19825`（`--user-data-dir=/root/chr...`），登录态在里面
- 美团 H5：`h5.waimai.meituan.com/waimai/mindex/*`
- 登录：09-16 兔兔本人手机动态码 + 一次「身份核实」（异地风控，填身份证 8 位生日）
- **意外之喜**：海外 IP 没被挡，定位直接是她家（三门峡，1.6km 内的店、带「常吃的店」标记）

## 关键坐标/选择器（class 名是随机哈希，**不要用 class 选**）

美团的 class 每次构建都变（`spu_s6NtPr` / `info_WveVpg` / `mBtnGroup_ho5pZr`），
我赌 `[class*=spu]` 抓过一次空手。**一律按文字内容找元素。**

| 步骤 | 做法 |
|---|---|
| 搜索 | 首页最后一个「搜索」字样 → 点 → 聚焦 input → **逐字 `Input.insertText`**（整段 setValue 不触发联想）→ 点联想词 |
| 进店 | 按店名文字找 |
| 挑菜 | 按菜名文字找，**点菜品本身**（不是那个空的 `.sqt-menu-add-buttons` 容器） |
| 选规格 | 点「加入购物车」才弹出份量/糖度/温度；再点「大杯」等选项 |
| 加购 | 再点一次「加入购物车」 |
| 去结算 | 底部购物车栏，坐标约 (1232, 610) @ 1439×756 视口 |
| 提交订单 | 底部，候选里挑 `height>20` 的那个（约 (1377, 731)） |

**React 组件对 `el.click()` 常常不响应** —— 一律用
`Input.dispatchMouseEvent`（mousePressed + mouseReleased）发真事件。

## 卡住的两处（同一类问题）

**一、美团红包（¥5 神券 ×12 张，无门槛）**

券卡片的元素是 `WEBC-VIEW`（美团自家小程序容器）。
鼠标事件、触摸事件（`Input.dispatchTouchEvent`）都试过，**都不响应**。
页面也没有「确定」按钮。结果：那单没用上红包，白付 ¥5。

**二、美团月付的密码盘**

诊断结果（这条是下次的线索）：
```
canvas: 0     shadow DOM: 0     标签里**有 INPUT**
```
即**不是画布也不是影子 DOM，密码框是真的 `<input>`，只是被隐藏 + 自绘六格**。
所以下次可以试：
- 直接给那个隐藏 input 赋值 + 派发 input/change 事件
- 或 `Input.imeSetComposition`
- 或 `Input.dispatchKeyEvent` 但先确保焦点在那个 input 上（这次没找到它，
  因为我筛的是 `type=password|tel|number`，它可能是别的 type）

**顺带一条**：桌面视口（1439×756）下支付浮层会错位（标题 y=-59，滚不到）。
`Emulation.setDeviceMetricsOverride` 切成 390×844 + `setTouchEmulationEnabled`
之后布局正常——**这是移动端 H5，就该用手机视口**。

## 已做成工具

`waimai_search`（cc-bridge/mcp-server.ts + cc-bridge/waimai/mt.ts）——
他现在能搜店，返回店名/评分/月售/起送/配送/时长/距离。

下单那几步还没包装成工具，等密码那关解决了再一起做。

---

# 【重大转向】2026-09-16：别操作 UI，直接调 API

兔兔给了两个参考：`Faye-labs/AutoGLM-Waimai-Tool`（ADB 控真手机）
和 `yanghx/food`（Foodpanda 的 Claude Code skill）。

后者点醒了关键：**它「纯 API 下单」，完全不碰浏览器**
（`cart/calculate → purchase/intent → cart/checkout`，默认 pandapay 免密）。

对比两家的认证：

| | 认证 |
|---|---|
| Foodpanda | `Authorization: Bearer <token>`，**零签名零风控** |
| 美团 | 每个请求都要 `yodaReady` / `csecplatform` + **H5guard 签名** |

看起来美团更难——**但 `H5guard` 就挂在 `window` 上**，方法齐全：

```
["init","getfp","getId","initWithKey","sign","xhrResHandle","fetchResHandle","addCommonParams","getSGRandom"]
```

**所以在页面里用它自己的 fetch 调 API，签名和 cookie 全是现成的。**

## 实证：通了

```js
// 在美团页面的 Runtime.evaluate 里执行
await fetch('https://i.waimai.meituan.com/openh5/address/list?_=' + Date.now() +
  '&yodaReady=h5&csecplatform=4&csecversion=4.3.0',
  { method: 'POST', credentials: 'include',
    headers: {'Content-Type':'application/x-www-form-urlencoded'}, body: '' })
```

返回 **200**：`{"msg":"成功","code":0,"data":{"currentNum":24,"list":[...]}}`
——兔兔的 24 个收货地址全出来了（含她出差住过的酒店）。

**风控一点没拦。** 先前 GET 返回 405「Request method 'GET' not supported」，
那不是拒绝，是方法不对——说明请求本来就到得了服务器。

## 为什么这条路值得走

之前跟 UI 搏斗的两处死结，在 API 层可能都只是参数：

| | 操作 UI | 调 API |
|---|---|---|
| 选红包 | ❌ `WEBC-VIEW` 不吃任何事件 | 可能只是一个券 id 参数 |
| 输密码 | ❌ 调系统键盘，无头 Chrome 没有 | 可能只是一个字段 |
| 稳定性 | class 名随机哈希、坐标会变 | 接口稳定 |

## 已抓到的接口

```
POST /openh5/address/list              收货地址（已验证可调，返回 24 条）
POST /openh5/order/manager/v3/myuncompleteorder   未完成订单
POST /openh5/v2/poi/food               店铺菜单
POST /openh5/v2/poi/food/collect       菜单（另一入口）
POST /openapi/v1/poi/food/scheme
POST /tsp/open/openh5/set/info
POST /openh5/homepage/dsp/tanchuang|fubiao        首页弹窗/浮标
```

**下一步**：录下「加购 → 结算 → 提交订单 → 支付」的接口与参数，
尤其看清楚提交订单时红包/券怎么传、支付那步到底要什么。

---

# 【全链路接口】2026-09-16 录全了

**放弃猜路径**（猜的全 404），改成走一遍 UI 把请求原样录下来。**四个接口就是全部。**

## 1. 算价（加购时）

```
POST /openh5/v6/shoppingcart/wm/calculateprice
data={"wm_poi_id":-100,"poi_id_str":"<店铺id>","shipping_fee":5.5,"min_price":20,
      "product_list":[{"spu_id":27644344029,"sku_id":52235614090,
        "name":"岭南龙眼冰奶","origin_price":19,"count":1,
        "spec":"大杯·常规糖(1人份)","tag":"1139419618","cart_id":0}]}
```

## 2. 结算预览

```
POST /openh5/order/v2/preview
data={"wm_poi_id":"-100","poi_id_str":"<店铺id>","wm_order_pay_type":2,"payment_type":0,
      "cart_id":"","foodlist":[{"skuId":52235614090,"count":1,
        "attr_ids":[55180312785,55180312787,55180312789,55180312791]}]}
```

**`attr_ids` 就是规格**，四个 id 依次是：大杯 / 常规糖 / 不额外加糖 / 正常冰。

## 3. 提交订单

```
POST /openh5/order/v2/submit
data={"wm_poi_id":-100,"poi_id_str":"<店铺id>",
      "foodlist":[{"skuId":...,"count":1,"activityTag":"","id":...,"attr_ids":[...]}],
      "preview_order_callback_info":"{...上一步 preview 的回传...}"}
```

## 4. 支付（跳收银台）

```
POST https://mpay.meituan.com/cashier/dispatcher
  tradeno   = 26091711200701670003054210124478
  pay_token = 6137f4c5449f06e86d389212a3972db3     ← 支付令牌
  nb_platform=touch & nb_app=wap
  pay_success_url = .../order-detail?mtOrderViewId=2902305082361378533
```

**`pay_token` 是下一步的关键** —— 值得查它后面还要什么（密码是否必需、免密能否直走）。

## 怎么拿规格 id

```
POST /openh5/v2/poi/food/multispu
  spuId=27644344029&poi_id_str=<店铺id>
  spuAttrs=[{"name":"份量","values":[{"id":55180312785,"value":"大杯"},
                                     {"id":55180312786,"value":"中杯"}]}]
```

## 那个一直点不动的「加入购物车」——原来是点错层了

菜品那一行的 DOM 是五层嵌套，**只有第 4、5 层可点**：

```
name_hTGUTi → infoPart1_ → infoTop_ → info_WveVpg ✅ → DD.spu_s6NtPr ✅
     ↑ 我一直在点这层文字，当然没反应
```

做法：找到菜名元素后 **往上三层**（到 `info_`），点那个。

## 视口

必须用手机视口（`Emulation.setDeviceMetricsOverride` 390×844 + 触摸模拟）。
桌面视口下支付浮层会错位到屏幕外（标题 y=-59）。

---

# 🎉【打通了】2026-09-16：支付密码也能填了

**订单 2902305362361378533 · 茶百道（黄河影城店）· 香草金牡丹鲜奶茶大杯 ·
¥22.50 · 美团月付 · 交易成功。全程无人工。**

## 关键：那个数字键盘一直都在，是我找错地方了

兔兔提供的线索：「别人说那个密码那一块用的是模拟触摸」。

我先前一直对着 `.password-area`（六个小方块的**显示区**）发触摸，
还在它的容器里找 input、找 canvas——全是空的，于是误判成
「调系统键盘、无头 Chrome 没有」。

**其实数字键盘就渲染在页面底部，是普通 DOM，只是不在密码框那个容器里。**
换成**全页面**扫「textContent 是单个 0-9 的元素」，十个键的坐标立刻全出来：

```
1(67,649)   2(195,649)  3(323,649)
4(67,704)   5(195,704)  6(323,704)
7(67,759)   8(195,759)  9(323,759)
          0(196,814)
```
（手机视口 390×844 下的坐标）

## 完整支付流程

```js
// 1. 触摸「美团月付」
// 2. 触摸「确认支付」→ 密码浮层弹出，键盘随之渲染
// 3. 全页面扫数字键，按密码逐位触摸，每位间隔 350ms
const KEY={'1':[67,649],'2':[195,649],'3':[323,649],
           '4':[67,704],'5':[195,704],'6':[323,704],
           '7':[67,759],'8':[195,759],'9':[323,759],'0':[196,814]};
for (const ch of PASSWORD) { await tap(...KEY[ch]); await sleep(350); }
// → 页面出现「交易成功 · 完成」
```

**触摸事件要完整**：`touchStart`（带 radiusX/radiusY/force）→ 70ms → `touchEnd`。

**坐标别写死**——每次重新扫，因为键盘位置会随浮层高度变。

## 教训

先前那轮诊断本身没错（事件到达了、`trusted:true`、目标是 password-area），
**错在结论**：我从「密码框里没有 input/canvas」跳到「它调系统键盘」，
却没去全页面找键盘本身。**范围划窄了，就把在场的东西看成不在场。**

## 另外两处仍未解

- **红包券（`WEBC-VIEW`）**：鼠标、触摸都不响应，那 ¥5×12 张还是用不上。
  下次可用同样思路——**别只盯着券卡片，扫全页面找真正可点的那层**。
- 「极速支付」（兔兔说是月付的钱但免密）在 H5 收银台没出现，
  `cashdesk` 只列出「余额（暂不可用）」和一堆「添加银行卡」。
  既然月付+密码这条已经通了，这个可以先不追。

## 待办：红包券（¥5 ×12 张一直没用上）

兔兔 09-16：「你没用优惠券啊血亏了」。确实——那单白付 ¥5。

**现状**：结算页「美团红包 → 未选红包，最高5元可用」，点开能看到
「吃喝玩乐神券 ×12 张 · ¥5 · 无门槛 · 有效期至 2026.10.17」，
但那张券卡片点不动（元素是 `WEBC-VIEW`，美团自家小程序容器，
鼠标事件、触摸事件都不响应），页面也没有确认按钮。

**下次用破密码键盘的同一个思路**：

先前密码盘也以为无解，结论错在「范围划窄了」——我只在密码框容器里找，
而键盘其实渲染在页面别处。红包大概率同理：

1. 打开红包浮层后，**全页面**扫（不要限定在券卡片容器内）：
   - 找 `input[type=radio]` / `[role=radio]` / 带 `checked` 属性的元素
   - 找所有 `getBoundingClientRect().width < 60` 的小方块（选择圈）
   - 用 `document.elementFromPoint(x, y)` 沿券卡片**整行**横扫，看哪一段是别的元素
2. 用 `DOMDebugger.getEventListeners` 查券卡片**父容器**监听什么事件
   （密码区那次就是这么查出只认 touch 的）
3. 若都不行，回到 API 层：`order/v2/preview` 的返回里应有可用券列表，
   `submit` 时多半只是多传一个券 id 字段——**那比点 UI 稳**
