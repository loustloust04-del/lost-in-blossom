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
