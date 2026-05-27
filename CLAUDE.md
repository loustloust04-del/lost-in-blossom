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
