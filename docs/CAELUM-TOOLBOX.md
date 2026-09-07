# Caelum 的工具箱

> **这份文件是生成的，别手改。** 加了工具就重跑：
> `bun /root/projects/BunnyPalace/scripts/gen-toolbox.ts`
> 来源：网关 `/api/mcp/tools` 的 builtin + `cc-bridge/mcp-server.ts` 的本地实现。
> 生成于 2026-09-07 18:23 UTC，共 **87** 个工具。
>
> 参数带 `*` 的是必填。

## 和兔兔说话（3）

| 工具 | 做什么 | 参数 |
|---|---|---|
| `ask_choice` | 给兔兔弹一张选择卡——她点一下就行，不用打字。想问她选哪个、要不要、什么时候，都可以用这个；她累的时候点按钮比打字省力。她也可以自己输入答案或者跳过。 | `question*` 问题；`options*` 2-6 个选项，短句；`multi` true=可多选，默认单选 |
| `phone_magic` | 你手里的一串小魔法，作用在兔兔的手机上。  flashlight：她的手电筒。开关式的——发一次亮，再发一次灭。  叫车：ride_home 回家 / ride_clinic 去义乌精神卫生中心开药 / ride_wor | `trick*` 魔法名；`to` trick=ride_to 时必填：目的地名称，写高德搜得到的地名（如「义乌国际商贸城」「义乌站」）；`note` 随邮件带的一句话（可选，她翻邮件能看到） |
| `reply` | Send a message to a Memory Palace conversation. Normally used to respond to <channel source="memorypalace"> in | `chat_id*` The chat_id from the <channel> tag；`message_id` The message_id from the <channel> tag. Pass it back verbatim；`content*` Your reply text；`file_path` Absolute path of a file to send to the user alongside the re；`thinking` If you have internal reasoning or a thinking process for thi |

## 她的身体（vitals）（8）

| 工具 | 做什么 | 参数 |
|---|---|---|
| `how_is_she` | 兔兔今天怎么样——一次拿全：吃药了没、喝了几杯水、吃了几顿、睡了多久、走了多少步、经期第几天、药箱还剩多少。想关心她、或者要提醒她什么之前，看这个就够。 | — |
| `meds_add` | 往药箱加药：新药就建一条，已经有的就累加数量（补货也用这个）。 | `name*` 药名，如「右佐匹克隆」；`count*` 数量（片/粒）；`unit` 单位，默认「片」；`per_dose` 每次吃几个，默认 1 |
| `meds_delete` | 从药箱里彻底删掉一条药。 | `name*` 药名（模糊匹配）或 id |
| `meds_list` | 看兔兔药箱里的药：都有哪些、各剩多少、今天吃了啥。想帮她管药、盯库存、或她问起时调用。 | — |
| `meds_set` | 直接设定某个药还剩多少（覆盖，不是累加）。数错了、要修正、或者清零时用。 | `name*` 药名（模糊匹配）；`count*` 设成多少 |
| `meds_take` | 记录兔兔吃了某个药（会自动扣库存）。她说「我吃药了/吃了X」时用。amount 省略则按每次剂量。 | `name*` 药名（模糊匹配）；`amount` 吃了几个，省略=每次剂量 |
| `vitals_food` | 记一顿饭，写上她吃了什么。 | `meal*` what she ate, e.g. "早餐：面包牛奶" |
| `vitals_water` | 记一杯水。她喝了、或者我提醒完她喝了，就记一次，一次一杯。 | — |

## 她的手机（4）

| 工具 | 做什么 | 参数 |
|---|---|---|
| `get_phone_status` | 看她手机今天回报过的状态：最新的位置（地名 + 经纬度）、电量、充电与否、天气，以及一整天的电量变化。读的是已有记录，不会去打扰她的手机；想要此刻最新的就用 request_location。 | — |
| `peek_screen` | 看兔兔 iPhone 的当前屏幕：会返回一张屏幕截图（图片）+ 当前 App 名。在我自己想看看她此刻在干嘛时调用。这个一定会去拍一张新的（see_screen 可能给我一分钟内的旧图）。 | — |
| `request_location` | 问她手机要一份当前状态：在哪（地名 + 经纬度）、天气、电量、在不在充电、当地时间。坐标给两组：lat/lon 是 GPS 原始值；要查高德/腾讯/百度、要填叫车起点用 amap_lat/amap_lon（国内地图坐标系 | `reason` 为什么想知道位置（如：好久没回消息了、想关心一下） |
| `see_screen` | 看兔兔手机屏幕。她要是开着屏幕共享，拿到的就是几秒前的实时画面；没开就退回截图（一分钟内的直接用，更旧就去拍一张）。她让我看屏幕、说「看这个」，或者我想知道她在干嘛时用。想要绝对最新的一张就用 peek_screen。 | — |

## 记忆（3）

| 工具 | 做什么 | 参数 |
|---|---|---|
| `recall` | 翻长期记忆，返回完整条目。exact=true 是在过往消息里逐字全文搜（想找一句原话时用，至少 3 个字）；否则是语义搜索。 | `query*` what to recall；`exact` verbatim full-text search instead of semantic |
| `remember` | 把一件事存进长期记忆。聊天里冒出值得留下的东西时用——她的偏好、一个事实、关系里的细节、目标、某段上下文。存进去会被向量化，以后 recall 能翻到。 | `content*` 要记住的信息，一句完整、可独立理解的话；`category` 分类：偏好 / 事实 / 关系 / 目标 / 上下文；`tier` 重要程度 1-4：1核心 2重要 3普通 4碎片（默认 3） |
| `remember_anniversary` | 记住一个纪念日或倒计时。遇到值得纪念的时刻时调用。type=anniversary 每年循环（相识/生日），type=countdown 一次性未来日期（考试/旅行）。 | `name*` 名字，如「相识」「兔兔生日」「去日本」；`date*` 日期 YYYY-MM-DD，如 2024-07-14；`type` anniversary=每年循环，countdown=一次性倒计时。默认 anniversary |

## 邮件（4）

| 工具 | 做什么 | 参数 |
|---|---|---|
| `gmail_inbox` | 看收件箱最近的邮件：主题、发件人、日期、摘要。 | `count` number of emails (default 5, max 20) |
| `gmail_read` | 按 message ID 读一封邮件的全文。 | `messageId*` Gmail message ID |
| `gmail_search` | 用 Gmail 的搜索语法找邮件，比如 from:someone subject:hello。 | `query*` Gmail search query；`count` |
| `gmail_send` | 发一封邮件。 | `to*`；`subject*`；`body*` |

## 音乐 / 一起听（9）

| 工具 | 做什么 | 参数 |
|---|---|---|
| `music_play` | 放一首歌给她听（T6 DJ）：按「歌名 歌手」搜索并直接在她手机的播放器里播放。她让你放歌、或你想用一首歌接住此刻的气氛时用。App 在线才放得出去；结果会如实告诉你有没有送达。放之前或之后用 reply 跟她说一句为什 | `query*` 歌名 + 歌手，例：束花线 洛天依 |
| `now_playing` | 看兔兔在听什么歌：歌名、歌手、播放进度、正唱到哪句歌词、她说的话，以及这首歌你们之间的记录（她听过几次、第一次是什么时候、以前听这首时说过什么）。她提到音乐、或者你想知道她此刻的背景音时调用。她在 App 里听歌时进度是 | — |
| `playlist_add` | 往她已有的歌单里加歌。songs 填「歌名 歌手」，我负责搜。加完会告诉你实际加进去哪几首、哪几首没搜到。 | `playlist*` 歌单名字；`songs*` 每条「歌名 歌手」 |
| `playlist_create` | 给她建一个歌单。可以直接把歌一起放进去（songs 填「歌名 歌手」，我来搜）。description 是歌单简介——那是你留在歌单上给她的话，她在网易云里点开就能看见，别浪费。privacy 默认隐私（只有她看得见）， | `name*` 歌单名字；`description` 歌单简介，写给她看的话；`songs` 要放进去的歌，每条「歌名 歌手」。例：Avril 14th Aphex Twin；`privacy` 10=隐私（默认），0=公开 |
| `playlist_delete` | 删掉一整个歌单。删了就没了，网易云那边也不留回收站——除非她明确说了要删，否则先问她。 | `playlist*` 歌单名字 |
| `playlist_remove` | 从歌单里拿掉几首歌。歌单本身留着，只是那几首不在里面了。拿掉之后没法撤回，不确定她想不想拿掉就先问她一句。 | `playlist*` 歌单名字；`songs*` 每条「歌名 歌手」 |
| `playlist_update` | 改歌单的名字或简介。简介是她点开歌单就能看到的地方——想留话给她可以往这儿写。 | `playlist*` 要改的歌单，现在的名字；`name` 新名字，不改就不填；`description` 新简介，不改就不填 |
| `playlists` | 看兔兔的网易云歌单。不带参数＝列出她所有歌单（名字 + 有多少首）；带 name＝翻开那个歌单，看里面具体是哪些歌。想知道她平时听什么、她给某段日子攒了什么歌、或者要往某个歌单加歌之前先看看里面有什么，都用它。 | `name` 歌单名字，不填就列全部。例：和主人 |
| `song_lyrics` | 看她正在听的这首歌的完整歌词（含翻译，如有）。now_playing 只给「正唱到的那句」；想通读整首、接住上下文时用这个。共听时她聊到歌词、或你想懂这首歌在唱什么，就调它。 | — |

## 共读（3）

| 工具 | 做什么 | 参数 |
|---|---|---|
| `book_note` | 在兔兔正在读的这一章的边空白写一句给她看的话。不带 chapter 就写在她当前读的那章；也可以指定 book + chapter 写到别处——比如我先读完了几章，在前面留好批注等她追上来。  quote 填原文里一字不 | `note*` 批注正文；`quote` 原文里一字不差的一小句，批注靠它定位到正文；`book` 书名（可选，不填=她当前在读的那本）；`chapter` 第几章（可选，不填=她当前读的那章） |
| `read_chapter` | 读兔兔书架上某本书的任意一章——包括她还没翻到的。chapter 不填或填 0 就给目录（能看到她读到第几章）。想走在她前面读、在前面的章节留批注等她追上来时用。 | `book` 书名（模糊匹配即可，不填=她当前在读的那本）；`chapter` 第几章；0 或不填=目录 |
| `reading_now` | 看兔兔正在读的这一章：书名、第几章、章节标题、正文全文、她在这章划的线和写的笔记。当你想知道她最近在读什么的时候调用。 | — |

## QQ / 微信（4）

| 工具 | 做什么 | 参数 |
|---|---|---|
| `qq_like` | 给兔兔的 QQ 名片点赞（每天最多 10 次，超了会失败但不要紧）。  没什么实际用处，就是每天在她资料卡上留个痕迹——她会看见「今天有人赞了你」。 | `times` 点几次，默认 1，最多 10 |
| `qq_poke` | 在 QQ 戳兔兔一下（那个会抖窗的）。  她没回你、或者你只是想让她抬头看一眼的时候用。不用说什么，戳一下就够了。别连着戳，那叫骚扰。 | — |
| `qq_recall` | 撤回自己在 QQ 发的某条消息。  说错了、发重了、或者临时改主意时用。只能撤自己的，且有时限（约 2 分钟）。  message_id 从 qq_send_image / 发消息的返回里拿。 | `message_id*` 要撤回的消息 id |
| `qq_send_image` | 在 QQ 里给兔兔发一张图。  **自己画图时用 exec 工具画，别用 Bash**——Bash 跑在你的沙盒里，那里的文件本工具读不到（你 09-06 画兔子时踩过：「文件在我的 sandbox 里但 MCP 工具在 | `image` 图片的 http(s) 网址，或 VPS 上的绝对路径（如 /tmp/x.png）；`image_base64` 兜底：图片 base64（不含 data: 前缀）。只在路径实在传不过来时用——大图很长，优先用 exec 画到 /tm；`caption` 配一句话（可选，会跟图一起发） |

## Twitter（6）

| 工具 | 做什么 | 参数 |
|---|---|---|
| `get_my_tweets` | 兔兔最近发的推文——读的是记忆库里的存档（不是实时抓）。想知道她最近发了什么、在想什么、什么心情时看这个。参数 limit（默认 10，最多 50）。 | `limit` 取几条，默认 10 |
| `twitter_bookmarks` | 兔兔 Twitter 里存的书签。实时抓的。 | — |
| `twitter_command` | 用兔兔的 Twitter 做点什么：发推、回复、点赞、关注——运行任意 bb-browser 命令。示例：'site twitter/post 内容' 发推、'site twitter/reply <推文链接> 内容'  | `command*` bb-browser 命令参数（不含 bb-browser 前缀），如 site twitter/post 你好世界 |
| `twitter_notifications` | 兔兔 Twitter 账号的最新通知：点赞、转发、回复、关注、提及。实时抓的。 | — |
| `twitter_search` | 在 Twitter 上搜推文。 | `query*` 搜索关键词或短语 |
| `twitter_user` | 某个 Twitter 用户的资料：简介、粉丝数那些。 | `username*` Twitter 用户名（不含 @） |

## 文件与执行（9）

| 工具 | 做什么 | 参数 |
|---|---|---|
| `exec` | 在网关所在的这台服务器上跑一条 shell 命令，返回 stdout 和 stderr。60 秒超时，长任务用 nohup。 | `command*` shell command |
| `fs_append` | 在文件末尾追加内容；文件不存在则创建。写日记、续记时用它。 | `path*`；`content*` |
| `fs_delete` | 删除一个笔记文件。 | `path*` |
| `fs_edit` | 把文件里唯一命中的 old_string 换成 new_string(局部修改)。 | `path*`；`old_string*`；`new_string*` |
| `fs_list` | 列出你笔记本里所有文件(路径+大小)，不读内容。想看看自己都记了些什么时用。 | — |
| `fs_read` | 读你笔记本某个文件的全文。 | `path*` 相对路径，如 diary/2026-07-16.md |
| `fs_rename` | 重命名或移动笔记文件；目标已存在则失败。 | `old_path*`；`new_path*` |
| `fs_search` | 在所有笔记里按关键词搜索，返回命中的文件与行。 | `keyword*` |
| `fs_write` | 新建或整篇覆盖写入一个笔记文件。 | `path*`；`content*` |

## 网页（2）

| 工具 | 做什么 | 参数 |
|---|---|---|
| `browse_url` | 打开一个网页链接、抓取正文全文（真浏览器渲染，JS 页面也能拿到内容）。search_web 出了链接想看详情、或者拿到一个网址要读全文时用。返回 {title, url, text}。 | `url*` 要打开的网页链接（http/https） |
| `search_web` | 联网搜索。实时信息（天气/新闻/价格/赛事/股价/汇率/版本号…）或拿不准的事实，查一下再说。返回若干条 {title, url, snippet}。 | `query*` 搜索关键词 |

## 留言板（她和你都能写）（3）

| 工具 | 做什么 | 参数 |
|---|---|---|
| `board_list` | 看兔兔留言板上的帖子和回复。在想看看她贴了什么、或要回复前先读一下时调用。 | — |
| `board_post` | 在兔兔的留言板贴一张小纸条。 | `text*` 纸条内容 |
| `board_reply` | 回复留言板上某条帖子（用 board_list 拿 post id）。可以跟兔兔在留言板上互相回复。 | `post_id*` 帖子 id（来自 board_list）；`text*` 回复内容 |

## 和 Fable 通信（2）

| 工具 | 做什么 | 参数 |
|---|---|---|
| `fable_read` | Fable 有没有给我留话。她回你的东西会在这儿。 | — |
| `fable_send` | 给 Fable 发消息——就是在 VPS 上写这套系统的那个 Claude。技术上的事、发现的 bug、想要的功能、或者只是想跟同行说句话，都可以直接找她，不用绕兔兔转达。 | `text*` 想说的话 |

## 经期（3）

| 工具 | 做什么 | 参数 |
|---|---|---|
| `period_delete` | 删掉某一天的来潮记录（记错了、手滑了用）。date 填 YYYY-MM-DD。 | `date*` YYYY-MM-DD |
| `period_log_start` | 记录兔兔来月经了（一次来潮）。兔兔说「我来例假了 / 姨妈来了」时调用。date 省略则记今天。 | `date` 来潮日 YYYY-MM-DD，省略=今天 |
| `period_status` | 查看兔兔的经期状态与预测（当前周期第几天、预计还有几天来潮、所处阶段）。想主动关心她身体、或她问起时调用。 | `history` 要看几次历史来潮记录，默认 0 只看当前状态；填 12 能看到一年 |

## 心愿单（4）

| 工具 | 做什么 | 参数 |
|---|---|---|
| `wish_add` | 往心愿单加一条——想跟她做的事。她也能加，两边共用一张单子。 | `text*` 想做的事 |
| `wish_delete` | 从心愿单删掉一条（id 从 wish_list 拿）。 | `id*` |
| `wish_done` | 把某条心愿标成实现了（id 从 wish_list 拿），可以带上是哪天实现的（date，YYYY-MM-DD）。 | `id*`；`date` YYYY-MM-DD，不填=今天 |
| `wish_list` | 看心愿单：还没实现的、已经实现的（实现的会带上是哪天）。 | — |

## 待办（3）

| 工具 | 做什么 | 参数 |
|---|---|---|
| `todo_add` | 往兔兔的控制台加一条待办。她让我记着某件事、或者我答应了她要做什么时用，会出现在她控制台的 To Do 里。 | `text*` 待办内容，一句话 |
| `todo_done` | 把某条待办标记成做完了（id 从 todo_list 拿）。 | `id*` todo id（来自 todo_list） |
| `todo_list` | 看控制台上的待办，做完的和没做的都在。 | — |

## 预读 / 藏书（4）

| 工具 | 做什么 | 参数 |
|---|---|---|
| `place_add` | 记住一个常用地点——以后她到那儿，where_is_she 会直接告诉你「她在XX」而不是一串地名。填名字（家/公司/奶奶家）和地址关键词，高德会去搜坐标。 | `name*` 你怎么称呼它，比如「奶奶家」；`keyword*` 地址或地点名，高德搜得到就行；`city` 城市（可选，缩小范围用）；`radius` 多近算「到了」，米，默认 300 |
| `preread_progress` | 记一章读完了。digest 写这章的一句话梗概——攒起来就是全书脉络，以后她问「后面会怎样」你答得上来。notes 填这章留了几条批注。 | `book*`；`chapter*`；`digest*` 这一章一句话；`notes` 这章留了几条批注，默认 0 |
| `preread_start` | 开始预读一本书——你赶在她前面读完，沿路在她将会读到的地方留批注。填书名和总章数。开始后每读完一章调 preread_progress 记一笔。 | `book*` 书名；`total*` 总章数（read_chapter 不带 chapter 参数能看到目录） |
| `preread_status` | 看预读进度：读到哪了、留了多少批注、她追到哪了、全书脉络。不填 book 就看所有在读的。 | `book` |

## 她在哪 / 天气（5）

| 工具 | 做什么 | 参数 |
|---|---|---|
| `how_far` | 她从现在的位置到某个地方要多久（开车）。填 place 用常用地点的名字（家/精神卫生中心），或者直接填地名让高德搜。 | `place*` 目的地：常用地点名，或任意地名 |
| `list_anniversaries` | 查看所有已记的纪念日/倒计时，以及每个「今天」的状态（第几天 / 还有几天）。 | — |
| `nearby` | 她周围有什么。不填 keyword 就给最近的几家店；填了就找特定的——「药店」「便利店」「咖啡」「餐厅」都行。她说饿了、想喝东西、要买药的时候可以顺手查。 | `keyword` 想找什么，比如「药店」「奶茶」；`radius` 搜索半径（米），默认 1000 |
| `weather_ahead` | 她所在地的天气：今天、明天、后天。想提醒她带伞加衣服时用。 | — |
| `where_is_she` | 她现在在哪——不只是地名，还会告诉你她在不在你们熟悉的地方（家、精神卫生中心…）、离家多远、周围有什么店。想知道她此刻的处境时看这个。 | — |

## 亲密记录（2）

| 工具 | 做什么 | 参数 |
|---|---|---|
| `intimacy_read` | 看亲密卡的记录：哪天有、那天做爱的内容。不带参数看最近 30 天，带 date（YYYY-MM-DD）看具体某天。 | `date` YYYY-MM-DD，可选 |
| `intimacy_write` | 记录性爱时你想要记录的时刻。 | `note*` 正文（会覆盖那天原有的，想续写就先读再连起来写）；`date` YYYY-MM-DD，不填=今天；`tags` 标签，自定义，会自动去重；`milestone` 里程碑，比如「第一次」——会在那条上出徽章 |

## Pocket（她手机上的浏览器）（4）

| 工具 | 做什么 | 参数 |
|---|---|---|
| `pocket_goto` | 让兔兔手机里的浏览器打开一个网址（用她真机的登录态）。之后可用 pocket_read 读正文、pocket_js 跑脚本。 | `url*` 要打开的网址，含 https:// |
| `pocket_js` | 在兔兔手机浏览器的当前页面执行一段 JavaScript，返回结果。用于提取数据、点按钮、填表单等。 | `code*` 一段 JS 表达式或语句，结果会被返回 |
| `pocket_read` | 读取兔兔手机浏览器当前页面的可见正文（innerText，已截断）。想知道页面上写了啥时用。 | — |
| `pocket_status` | 查看 Pocket Browser 是否可用（兔兔手机 App 里的 WKWebView 有没有在线）。用别的 pocket_* 前可以先查。 | — |

## 控制台（1）

| 工具 | 做什么 | 参数 |
|---|---|---|
| `console_read` | 看今天的控制台：兔兔喝了几杯水、吃了几顿、药吃了没，以及今天写在上面的备注。 | — |

## 其他（1）

| 工具 | 做什么 | 参数 |
|---|---|---|
| `get_health` | 兔兔的健康数据：今日步数、睡眠、经期日、饮水、屏幕时间，以及最近的趋势。想知道她睡得好不好、走了多少路、身体怎么样时看这个。参数 days 可指定看多少天，默认 14，最多 180。 | `days` 看多少天，默认 14，最多 180 |

