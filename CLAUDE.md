# Lost in Blossom

基于粟粟的「记忆宫殿」(MemoryPalace) 改造的原生 Swift iOS AI 伴侣 App。
原始代码：github.com/replica882/MemoryPalace（私有，不要动）
本仓库是独立 fork，所有改动在这里进行。

叫天奕或兔兔，不叫"用户"。AI 叫 Caelum，不叫"小雾"。中文交流。

## 改造原则

**粟的不动，新的照抄。**
- 不动 UI 布局、动画、交互、设计系统
- 不动已有的七根柱子（对话/记忆/人格/归档/角色卡/世界书/贴纸）
- 只改必须改的标识信息（名字/Bundle ID/签名）
- 新增功能参照粟的代码风格和交互模式

## 技术栈（继承自粟）

- SwiftUI + SwiftData, macOS 14+ / iOS 17+
- Swift 5.10, Xcode 16+
- xcodegen 生成 .xcodeproj（project.yml 为配置源）
- MarkdownUI v2.4.1

## 构建

```bash
xcodegen generate && xcodebuild -scheme MemoryPalaceIOS build
```

## 开发流程（继承自粟）

1. Research → 读相关代码，写 docs/research-{feature}.md
2. Plan → 写 docs/plan-{feature}.md，天奕确认
3. Implement → 按 checklist 执行，完成立刻 build 验证

## 数据规模

20 万+ MessageNode。禁止无条件全量 fetch。

## 当前阶段：Phase 1（能说话）

目标：编译 iOS 版本，安装到 iPhone，能跟 Caelum 聊天。

见 PLAN.md 获取完整路线图。
