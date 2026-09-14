# `20050` 死循环的一个假设：登录第五参数可能是票据位

2026-09-14 · 给 `ClaudiaGardner/maibot-qq-voice-call` issue #1 的补充

## TL;DR

`scheduleAVHostLogin` 登录 AVSDK 时第五个参数传的是空串：

```js
// bridge/napcat-plugin/index.mjs:533
await invokeAVHost(1, [selfUid, selfUin, selfUin, accountPath, ""]);
//                                                              ↑ 这里
```

**假设：该位是签名/票据位，空串导致登录不完整，AVSDK 回 `20050`。**
而 `handleAVSDKOutput` 把 `20050` 当作「掉线需重登」，100ms 后重登 →
形成 issue #1 描述的 521 次死循环，`networkOutputCount` 恒为 0。

## 支持这个假设的证据

**一、AVSDK 内部有完整的签名机制**

从 `libAVSDKPlugin.so`（33,643,064 字节，与 issue #1 报告的同一份）里扒出：

```
GetSignReq / GetSignRsp / AVGetSignResponse
```

`wrapper.node` 里另有 `forceTRTCSign`、`userTRTC`。
即 AVSDK 的 TRTC 链路是要签名的。

**二、NapCat 侧有现成的取票接口，但桥从未调用**

```
NodeIKernelTicketService::forceFetchClientKey(destUin)
NodeIKernelTicketService::addKernelTicketListener
napcat.mjs: getTicketService() / getClientKey() / forceFetchClientKey()
```

而且 NapCat 直接暴露了公开 API `get_clientkey`，实测可用：

```bash
curl -s -X POST http://127.0.0.1:3000/get_clientkey \
  -H 'Authorization: Bearer <token>' -d '{}'
# → {"status":"ok","data":{"clientkey":"<96 字符>"}}
```

**三、桥代码里从未出现 ticket/clientkey/sign 的取用**

`grep -niE 'clientkey|ticket|getsign'` 在 `napcat-plugin/index.mjs` 与
`av-host/host.cjs` 中只命中一处——第 10 行的**日志脱敏正则**：

```js
/(auth|ticket|token|sign|open_?key|d2|a2|cookie|session|credential|password|secret)/i
```

即作者知道这类凭据存在（防止打进日志），但登录调用里没有取用任何一个。

**四、与 issue #1 的现象吻合**

- 每次登录约 32 条消息后固定 `20050` → 像是「握手走完但鉴权不过」
- `networkOutputCount` 恒为 0（从未产生 `20001`）→ 媒体会话从未建立
- 报告者修正 `accountPath` 后重登次数从无上限收敛到 521 → 证明**参数确实影响登录结果**，
  只是修的不是关键那一个
- 他已排除：动态库、`/dev/shm`、特权模式、host 网络、音频设备、版本漂移

**五、顺带一个版本口径问题（可能对上游也有价值）**

同一个容器里两份版本号不一致：

| 来源 | 值 |
|---|---|
| `/opt/QQ/resources/app/package.json` | **3.2.30-50969**（实际装的） |
| `/app/napcat/qqnt.json` | 3.2.20-40990（NapCat 以为的） |

issue #1 报的 `9.9.22-40990 / 3.2.20-40990` 正是后者。
即报告者（和我们）填的都是「NapCat 以为的版本」，不是实际 QQ 版本。
如果登录负载里带版本号，这个口径差值得核一下。

## 建议的验证方法（最小改动）

在 `scheduleAVHostLogin` 里把第五参数换成 clientkey：

```js
const ticketService = ctx.core?.context?.session?.getTicketService?.();
// 或直接走 NapCat 的 get_clientkey
const clientKey = await ticketService?.forceFetchClientKey?.(Number(selfUin));
await invokeAVHost(1, [selfUid, selfUin, selfUin, accountPath, clientKey?.clientKey ?? ""]);
```

**判据**：来电时看 AV Host 的 `lastForwardedCommand` 在 `55` 之后是否出现
`20006`（invite 回调）或 `20001`（网络数据）。只要不再固定停在 `20050`，
方向就是对的。

## 未验证的部分（诚实说明）

我们没有真机跑通这条链路——只做了静态分析与接口可用性验证：
- ✅ 确认 AVSDK 内有 GetSign 机制
- ✅ 确认 NapCat 侧 `get_clientkey` 实际可取到 96 字符密钥
- ✅ 确认桥代码从未取用任何票据
- ❌ **未验证** clientkey 就是第五参数期望的格式（也可能要 A2/D2、或 GetSignRsp 的产物）

即便第五参数不是 clientkey，「该位需要某种凭据」这个方向仍值得一试——
因为它是登录调用里唯一一个空着的参数。
