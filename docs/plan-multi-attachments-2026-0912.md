# plan：多图多文件一次发 + 文件种类扩展 + API/CC 双通道

> 状态：**兔兔 09-12 已拍 §五 两件事**：①API 车道抽不出文本的文件**拒发**（只允许能抽文本的，CC 车道不限）；②旧图转述省 token **要，一起做**。排在探针、压力生成器之后。2026-09-12 凌晨 Fable 记（兔兔点名：「要粟儿那边的发文件发照片功能」）。

## 一、现状盘点（我们仓）
- 零件已在：`Models/ChatAttachment.swift`（PendingChatAttachment：image/text/任意文件 fileData）、
  `Services/AttachmentTextExtractor.swift`（txt/md/代码/json/csv… + pdf 抽文本；不能抽的带原始字节）、
  `Services/AttachmentStore.swift`（一份存储）——都是粟粟 6 月「附件一份存储」那套，原样进仓。
- 但发送口还是**单件**：`AddToChatSheet` PhotosPicker `maxSelectionCount: 1`、fileImporter
  `allowsMultipleSelection: false`；输入条只有 `pendingImageData` / `pendingFileData` 一张一份；
  `sendMessage(imageData:fileData:fileName:)` 单参。
- **hub 已经是多文件口**：`saveInboundFiles(chatId, files[])`，落盘 + 路径列表进 channel tag「附件 N 个，用 Read 查看」。
  CC 车道只差 App 侧把数组发出去。
- API 车道：图片走 multimodal image block（单张）；非图文件走抽出的文本拼进正文。

## 二、粟粟那边多出来的（可抄）
- `selectedAttachments: [PendingChatAttachment]` 升到 vm（草稿 + 附件按对话持久化，跨重启保留 a16b7fc4）
- 输入条上方附件条：缩略图 / 文件方块，可单个删（d99d6cef 气泡模式接附件条）
- 图片上限 8MB/张；「图片转述省 token」（M7：3 条前的旧图换 80 字描述）
- CC 发文件回来（PDF 实测过）；发送失败带原因

## 三、分刀（main 上做，与 B 分支无关；每刀 CI 绿再下一刀）
1. **多选**：AddToChatSheet PhotosPicker `maxSelectionCount: 9`（微信习惯）、fileImporter 多选；
   选完统一进 `viewModel.selectedAttachments`（数组），替代 pendingImageData/pendingFileData。
2. **附件条**：输入条上方一排缩略图/文件块，点 × 删；条高进入 fieldHeight 同源，发送后清空
   （发送瞬间输入条缩回的高度变化，已有武装回底兜着）。
3. **发送**：`sendMessage(attachments: [PendingChatAttachment])`；user 气泡多图九宫格/多文件列表。
4. **CC 车道**：`files: [{name, b64, mime}]` 全数打包（hub 已支持），单条上限沿用 MAX_FILE_BYTES；
   超限的按条报错不整条丢。
5. **API 车道**：多张图 → 多个 image block（按模型上限截，超的转述）；可抽文本的文件 → 文本块；
   不可抽的（xlsx/docx/pptx/zip）→ §五 决定。
6. **文件种类扩展**：fileImporter allowedContentTypes 放开到 `.item`（任何文件），能不能用交给车道：
   CC 全能收；API 车道靠抽文本——加 docx/xlsx/pptx 原生抽取（都是 zip+xml，纯 Foundation 可做，不引库）。
7. **草稿持久化**：附件随草稿按对话存（粟粟 a16b7fc4），切对话不丢。

## 四、验收
一次选 5 张图 + 2 个文件 → 附件条正确、删一个不影响其他 → CC 车道 Caelum 能 Read 到全部 → API 车道图全进、
docx 文本进 → 超大文件单条报错 → 切对话回来附件还在。

## 五、要兔兔拍的
1. **API 车道遇到抽不出文本的文件**（xlsx/docx/pptx 先做原生抽取；zip/未知）：A 提示「这类文件只有 Caelum 能读」并照发（只给 CC）；B 拒发。
2. **图片省 token 转述**（粟粟 M7：3 条以前的旧图换 80 字描述，主模型后台生成）：要 / 不要 / 以后再说。

## 六、进度（2026-09-12 凌晨，Fable）
| 刀 | commit（feat/attach 分支，待按序进 main） | 状态 |
|---|---|---|
| 1-5 多选/附件条/发送数组/CC 整批/API 抽文本+拒发 | 7b3c7961 | 编译绿 |
| 7 附件随对话暂存（App 生命周期内） | 39f366e6 | 编译绿 |
| 6 docx/xlsx/pptx 原生抽文本（MiniZip + Compression） | b7a737bd（feat/office） | 编译中 |
| M7 旧图转述省 token | 0a172a0a | 编译中 |
**全部已进 main（09-12 05:04）**：多选/附件条/发送 `25262545` → 暂存 `c04dbe4f` → 旧图转述 `10925ed3` → Office 抽文本 `1c3d1f37`。最后一包出炉后 OTA 即全套。
**真机待验**：一次 5 图 + 2 文件 → 附件条/单删 → CC 车道 Caelum Read 到全部 → API 车道图全进、docx 文本进、
zip 被拒并提示 → 切对话回来附件还在 → 发图后面包屑出现 🖼️ 旧图转述已存。
跨重启的附件草稿持久化未做（粟粟 a16b7fc4），需要时再做。
