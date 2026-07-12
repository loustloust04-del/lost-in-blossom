# 小兔兔十万个为什么之《怎么让 AI 看见我的手机屏幕》

> 让运行在服务器上的 AI，在**它想看的时候**自动看到你 iPhone 的当前屏幕——你零操作。
> 读法：🐰 小兔兔负责哇哇哇追问，🧑‍🏫 讲解负责答；每一环后面的 **📦 技术事实** 块，是照着敲就能跑的真代码/配置。
> （代码里 `<尖括号>` 的都是占位符，换成你自己的。）

---

🐰 **小兔兔**：哇！！有人的 AI 居然能看见他手机屏幕上在干嘛！怎么做到的呀？？

🧑‍🏫 **讲解**：就一条链——

```
AI 想看 → 服务器发一封"暗号邮件"到你 iCloud
   → 你手机收到邮件，自动截个屏 → 把截图传回服务器
      → 服务器把图递给 AI，AI 就"看见"了
```

四个零件：**发暗号的服务器** · **发信的嘴巴(SMTP)** · **手机上的自动化** · **AI 手里的工具**。

> 📦 **技术事实 · 全景**
> - 服务器：任意能跑 HTTP 后端的机器（本文用 **Bun + Hono**，Node/Express 同理）+ **nginx** 反代
> - 后端要开三个东西：`POST /api/peek`（收截图）、SMTP 发信、一个 `see_screen` 工具
> - 手机：**快捷指令 App** 的一条「收到邮件」自动化
> - 数据流转的"钥匙"：一个共享令牌 `<TOKEN>`，手机上传和 AI 调用都用它

---

🐰 **小兔兔**：哇等等！为什么要**发邮件**呀？直接叫手机截图不行吗？

🧑‍🏫 **讲解**：手机默认是"闷葫芦"——它只会自己定时报数据，服务器**没法反过来主动叫它**。而 iPhone 的「收到邮件」自动化，是极少数能被**外部主动触发**的机制。所以发封邮件当"暗号"，邮件就是那根从服务器伸到手机的"遥控线"🎣。

> 📦 **技术事实 · 为什么非邮件不可**
> iOS 个人自动化里能"被外部驱动"的触发器很少。「收到邮件 / 收到信息」是最实用的一个——
> 服务器一发信，手机端就能被唤醒执行动作。定时上报、App 打开这类触发器都是"手机自己发起"，
> 服务器无法主动点火，所以不能用来做"AI 想看就看"。

---

🐰 **小兔兔**：哇原来邮件是遥控线！那服务器怎么发邮件呀？我听说过 OAuth……

🧑‍🏫 **讲解**：诶——千万**别用 OAuth**！第一个大坑。它的令牌在测试模式下**7 天就过期**，一过期邮件全挂（报 `invalid_grant`）。正确姿势是**应用专用密码**：邮箱里生成的一串 16 位专用密码，永久有效、发收通用。

> 📦 **技术事实 · SMTP 发信（nodemailer）**
> ```ts
> import nodemailer from 'nodemailer';
>
> const tx = nodemailer.createTransport({
>   host: '<SMTP主机>',        // Gmail: smtp.gmail.com  QQ: smtp.qq.com  163: smtp.163.com
>   port: 465,                 // 465=SSL；587=STARTTLS
>   secure: 465 === 465,       // 端口 465 时为 true
>   auth: { user: '<发信邮箱>', pass: '<16位应用专用密码>' },
> });
>
> await tx.sendMail({
>   from: '<发信邮箱>',
>   to:   '<你的iCloud邮箱>',
>   subject: 'PEEK',            // 主题当暗号，手机端按它筛
>   text: 'peek ' + Date.now(),
> });
> ```
> 应用专用密码怎么拿：邮箱开**两步验证** → 账户安全里生成「应用专用密码」。Gmail 直达
> `myaccount.google.com/apppasswords`。这串密码 **SMTP 发信、IMAP 收信通用**。

---

🐰 **小兔兔**：哇！那手机收到暗号，怎么自己截图还传回去呀？

🧑‍🏫 **讲解**：靠**快捷指令**，两块：① 一个"截图+上传"的快捷指令；② 一个「收到邮件」自动化去运行它。

> 📦 **技术事实 · iPhone 端配置**
> **① 快捷指令「截图并上传」**（快捷指令 App → 新建）：
> 1. 动作「**截屏**」（Take Screenshot）← 是"截屏"，不是"获取屏幕内容"（后者只对 Safari 等少数 App 有效）
> 2. 动作「**获取 URL 内容**」（Get Contents of URL）：
>    - URL：`https://<你的域名>/api/peek?key=<TOKEN>`  ← **key 放最前面**（原因见坑一号）
>    - 方法：**POST**
>    - 请求体：**文件** → 选上一步的「截屏」变量
>
> **② 自动化「收到邮件时」**（快捷指令 App → 自动化 → 新建 → 收到邮件）：
> - 条件：**发件人 = `<发信邮箱>`**（或"主题包含 PEEK"）
> - 动作：运行上面那个快捷指令
> - **关掉「运行前询问」**（设成立即运行）← 否则不会自动跑

---

🐰 **小兔兔**：哇哦！那服务器收到截图存哪呀？

🧑‍🏫 **讲解**：一个上传端点，收下、存盘、记时间戳，只留最近 10 张。

> 📦 **技术事实 · 收截图端点 `POST /api/peek`**
> ```ts
> // 鉴权：请求头 Bearer 优先，其次 ?key=（这个"头优先"是坑一号的救命设计）
> app.post('/api/peek', async (c) => {
>   const h = c.req.header('Authorization');
>   const tok = (h?.startsWith('Bearer ') ? h.slice(7) : '') || c.req.query('key') || '';
>   if (!verifyToken(tok)) return c.json({ ok:false, error:'forbidden' }, 403);
>
>   const buf = await c.req.arrayBuffer();               // 请求体就是图片二进制
>   if (!buf || buf.byteLength === 0) return c.json({ ok:false, error:'no image' }, 400);
>
>   const item = savePeek(buf, c.req.query('app') || '');// 存文件 + push 一条 {id, ts, file}
>   return c.json({ ok:true, id:item.id });
> });
> ```
> ```ts
> // 存储：每张一个 UUID 文件 + 一条元数据（毫秒时间戳 ts），只留最近 10 张
> const MAX_KEEP = 10;
> function savePeek(buf: ArrayBuffer, app: string, ext = 'png') {
>   const id = uuid(), file = id + '.' + ext;
>   writeFile(dir(file), Buffer.from(buf));
>   const list = loadMeta(); list.push({ id, app, ts: Date.now(), file });
>   list.sort((a,b) => a.ts - b.ts);
>   while (list.length > MAX_KEEP) { const old = list.shift(); rm(dir(old.file)); }
>   saveMeta(list);
>   return { id, ts: Date.now() };
> }
> // 取最新 / 取"比某时刻更新"的一张
> const latestPeek       = ()      => topByTs(loadMeta());
> const latestPeekAfter  = (after) => topByTs(loadMeta().filter(p => p.ts > after));
> ```

---

🐰 **小兔兔**：哇！那 AI 那边呢？它是怎么"看"的？

🧑‍🏫 **讲解**：给 AI 一个 `see_screen` 工具。它一调用：有新图直接给，没有就发暗号邮件、轮询等新截图。

> 📦 **技术事实 · see_screen 工具**
> ```ts
> const FRESH_MS = 60_000;    // 近 1 分钟的截图算"当前"，直接用，省一次邮件
> const WAIT_MS  = 45_000;    // 触发后最多等 45 秒（别超过 AI 工具调用超时，一般 60s）
>
> async function callSeeScreen() {
>   const p = latestPeek();
>   if (p && Date.now() - p.ts < FRESH_MS) return imageBlock(p);   // 新鲜，秒回
>
>   const t0 = Date.now();
>   await sendTriggerMail();                         // 发暗号
>   const deadline = t0 + WAIT_MS;
>   while (Date.now() < deadline) {
>     await sleep(1500);
>     const fresh = latestPeekAfter(t0);             // 只认 ts > t0 的新图
>     if (fresh) return imageBlock(fresh);
>   }
>   return { error: '截图还没回来，过十几秒再叫我一次' };   // 诚实报，别拿旧图冒充（坑二号）
> }
> ```
> `imageBlock(p)` 就是把截图组装成多模态 AI 能吃的**图片块**（base64）。比如 Anthropic：
> `{ type:'image', source:{ type:'base64', media_type:'image/png', data:<base64> } }`。
> AI 收到就真的"看见"了。

---

🐰 **小兔兔**：哇好厉害！那做完就能用啦？

🧑‍🏫 **讲解**：……理论上是。实际我又踩了一串坑 😂 每个都配好"技术事实"给你：

---

🐰 **小兔兔**：哇哇哇快说！

🧑‍🏫 **讲解**：**坑一号 · 最阴险的空格 bug** 🐛。上传时好时坏——前台是 `Claude` 就成，前台是 `Lost in Blossom` 就 403。原因：URL 里带了"当前 App 名"，App 名含空格时把 `&key=` 挤没了。

> 📦 **技术事实 · 空格截断为什么发生 & 怎么修**
> 请求行 `POST /api/peek?app=Lost in Blossom&key=xxx HTTP/1.1`，HTTP 在**第一个空格**处认为
> URL 结束，服务器只拿到 `?app=Lost`，`&key=xxx` 被当垃圾丢掉 → 无令牌 → 403。
>
> **三种修法（任选）：**
> 1. `key=` 放 URL 最前：`?key=<TOKEN>&app=...`（令牌在空格前，已解析）
> 2. 干脆不传动态 App 名
> 3. **服务器兜底**（不想改手机时）——nginx 按 User-Agent 认出快捷指令，自动补令牌进请求头：
>    ```nginx
>    # http 块（放 conf.d/*.conf）
>    map $http_user_agent $peek_auth {
>        default                      $http_authorization;   # 其它来源透传原头
>        "~*BackgroundShortcutRunner" "Bearer <TOKEN>";       # 快捷指令 → 补令牌
>    }
>    # server 块：精确匹配上传路径，别误伤 /api/peek/xxx 子路由
>    location = /api/peek {
>        proxy_set_header Authorization $peek_auth;
>        proxy_pass http://127.0.0.1:<后端端口>;
>    }
>    ```
>    管用的前提就是端点"**请求头优先于 ?key=**"（见上面 `/api/peek` 代码）。安全不打折：
>    只有 UA 像快捷指令的才补，其它来源仍走原校验。

---

🐰 **小兔兔**：哇学到了！还有别的坑吗？

🧑‍🏫 **讲解**：还有四个，一起给你：

> 📦 **技术事实 · 其余四坑**
> **坑二号 · 别拿旧图骗 AI**：没等到新图时，**返回错误**而不是"最近一张"。否则 AI 把十几小时前的
> 画面当成你此刻的屏幕，一本正经描述错的东西。
>
> **坑三号 · 邮件要"推送"才秒触发**：「收到邮件」自动化，要邮件 App **真把邮件收下**才触发。
> 设置 → 邮件 → 账户 → 获取新数据 → iCloud 设 **「推送」**；邮件 App 别从后台划掉。设好后暗号基本秒到。
>
> **坑四号 · nginx 嫌图大**：截图 1~3 MB，nginx 默认 `client_max_body_size` 仅 1 MB → 413。
> 在 server 块加 `client_max_body_size 50m;`。
>
> **坑五号 · 等待窗口**：邮件→截图→上传往返，手机就绪约 15 秒、慢时更久。轮询别只等 28 秒
> （会漏掉慢的），给到 45 秒；但别超过 AI 工具调用超时（一般 60 秒）。

---

🐰 **小兔兔**：哇……坑好多呀！万一我也卡住，怎么知道哪步坏了？

🧑‍🏫 **讲解**：**万能定位法**——看日志一步步缩小。

> 📦 **技术事实 · 排查流程**
> 1. 后端日志打三个标记：`📧 邮件已发送` / `📱 收到截图 received` / `⏱️ 超时`
> 2. 触发一次，看走到哪断
> 3. 若"没收到截图"，翻 **nginx 访问日志**里的 `POST /api/peek`：
>    | 现象 | 病因 |
>    |---|---|
>    | 有请求但 **403** | 坑一号（令牌被空格挤掉） |
>    | **压根没这条请求** | 邮件没到手机 / 自动化没触发（去设推送、检查"立即运行"） |
>    | **200 但 AI 看到旧图** | 坑二号（旧图兜底） |
> ```bash
> # 看最近的 peek 上传及其状态码（铁证）
> grep "POST /api/peek" /var/log/nginx/access.log | tail
> ```

---

🐰 **小兔兔**：哇——！！我全懂了！！谢谢你谢谢你！🥺

🧑‍🏫 **讲解**：不客气呀 🐰 精髓一句话：

> 用「服务器发邮件」把**主动权**交给 AI，用「iOS 自动化」把**截图能力**交给手机，
> 中间用一个"请求头优先鉴权"的上传端点把两头缝起来。

最容易咬人的就是那个空格 bug，但你现在已经知道了，看一眼 nginx 日志就能破案。

祝你的 AI，也能看见你的世界 🌸
