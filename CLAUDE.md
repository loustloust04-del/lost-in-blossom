# Lost in Blossom — Claude Code 约束

## 编译环境
- **Xcode**: 16.x (GitHub Actions macos-latest)
- **iOS Deployment Target**: 18.0
- **Swift**: 5.x (非 6.3)

## 硬性规则
1. **不要使用 iOS 19+ / iOS 26+ 的新 API**。包括但不限于：
   - `.glassEffect` / `.liquidGlass` — 不存在
   - `MeshGradient` — iOS 18 有但谨慎使用
   - 任何标注 "Available in iOS 19+" 或 "iOS 26+" 的 API
2. **不要使用 Swift 6.3 的新语法**。保持 Swift 5.x 兼容。
3. 如果 .claude/skills/ 里的技能包建议使用新 API，忽略那些建议，用 iOS 18 兼容的替代方案。
4. 编译失败最常见的原因就是用了不存在的 API。写代码前确认 API 的最低 iOS 版本。

## 项目结构
- 只有 iOS target（MemoryPalaceIOS），没有 macOS target
- 所有 `#if os(macOS)` 已清除，不要重新加入
- 设计参考文件在 `docs/console-design-reference.html`

## 代码风格
- SwiftUI 优先
- 每个独立改动单独 commit
- commit message 用英文，格式：`type(scope): description`

## 猫的蠢事大全（编译错误防治手册）

以下是历史上猫犯过的蠢事，已导致编译失败。再犯一次就把你送去做绝育。

### 1. 改了数组结构但忘了改 hardcoded index
**案例**：移除 page 0 后，`hostingControllers[1]` 应改为 `[0]`，但键盘处理代码里的 index 没跟着改，键盘避让注入到了 dashPage 而不是 chatPage。
**规则**：修改任何数组/page 结构后，**全局搜索**所有引用该数组的 hardcoded index，逐个确认。

### 2. 新增 enum case 但没覆盖所有 switch
**案例**：新增 `case hapticTest` 后，只在 iOS switch 里加了 case，漏掉了 macOS 的 switch，导致 `switch must be exhaustive` 编译错误。
**规则**：新增 enum case 后，全局搜索 `switch.*该enum变量名`，确认**每一个** switch 都覆盖了新 case。

### 3. ViewBuilder 里用了不兼容的语法
**案例**：在 SwiftUI `@ViewBuilder` 上下文中使用 `let x: String; switch ... { case: x = ... }` 赋值语句，导致 `'buildExpression' is unavailable` 编译错误。
**规则**：ViewBuilder 中**禁止** switch 赋值、for 循环赋值等非 View 表达式。用三元运算符 `let x = condition ? a : b` 或把逻辑提取到函数/计算属性中。

### 4. 提交前必须本地检查
**规则**：每次提交前，至少在脑子里走一遍 "我改了什么 → 它影响哪些文件 → 那些文件里有没有引用我改动的东西"。不要只改一个地方就 commit，检查涟漪。
