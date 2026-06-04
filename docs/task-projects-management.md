# Projects 管理功能

> 对话按项目分组，项目内共享上下文。

---

## 需求

参考 Claude.ai 的 Projects 功能：

1. **项目创建与管理**
   - 用户可以创建项目（名称、描述、图标/颜色）
   - 项目列表在侧边栏或独立页面展示
   - 项目可编辑、归档、删除

2. **对话归属**
   - 每个对话可以属于一个项目（或不属于任何项目）
   - 新建对话时可选择项目
   - 已有对话可移入/移出项目

3. **项目级上下文**
   - 每个项目可设置项目指令（Project Instructions）—— 类似 system prompt 的补充
   - 项目指令在该项目下所有对话中自动注入
   - 项目可附加参考文件（知识库）—— 后续可做，先做基础

4. **UI 入口**
   - 侧边栏项目列表（折叠/展开）
   - 项目内对话列表
   - 项目设置页（名称、指令、文件）

---

## 数据模型

```swift
struct Project: Identifiable, Codable {
    let id: UUID
    var name: String
    var description: String
    var icon: String          // SF Symbol name
    var color: String         // hex
    var instructions: String  // 项目级 system prompt
    var createdAt: Date
    var archivedAt: Date?
}
```

Conversation 模型加一个可选字段：
```swift
var projectId: UUID?
```

---

## 存储

项目数据用现有的本地存储方案（跟对话存储一致）。不需要云端同步。

---

## 实现顺序

1. 数据模型 + 存储
2. 项目 CRUD UI（创建/编辑/删除）
3. 对话归属（新建时选项目 + 已有对话移动）
4. 项目指令注入（ChatService 发 API 时拼接）
5. 侧边栏项目列表
