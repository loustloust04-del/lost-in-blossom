# Sidebar · 侧边栏 · 一级界面

> 灵魂：图书管理员。安静有序。

## 原则
保留现有功能布局，只换颜色和样式。不改位置、不改功能结构。

## 标题
- "Lost in Blossom" → Cormorant Garamond **600 Semibold**, 22px
- 需要引入 Cormorant Garamond 字体包

## 分组图标（全部统一颜色 #3D3D38）
- **Chats**: v2版双气泡+文字行（参考 sidebar-icons-v2.html）
- **Projects**: v2版文件夹翻盖+分层线
- **Almond**: 杏仁/水滴形轮廓，无中线，纯轮廓
- **Amber**: 六边形轮廓，无切面线，纯轮廓
- 图标SVG源码见 lib.amberrib.com/sidebar-icons-v2.html（Almond/Amber需去掉内部装饰线）

## 设置按钮
- 现有齿轮 ⚙ → 调节滑块图标（两条横线+两个圆点）
- 颜色 #6C6A62，opacity 0.55
- SVG参考 sidebar-icons-v2.html 底部的"调节滑块"方案

## 搜索栏
- 位置不动，功能不动，展开逻辑不动
- 减轻视觉重量：去掉实心背景色，或将背景改为极淡（opacity < 0.1）
- 让搜索栏从"区块"变成"一行淡文字"，不再隔断标题和分组

## 选中态
- 选中的对话项：背景 #E0D6C6
- 左边缘 3px 竖线，颜色 #B96747（杏色）

## 按钮
- "+ New chat" 按钮：背景 #B96747，文字白色
- 发送按钮（聊天界面）：#B96747

## 其他改动（跨页面）
- "助手" 标签 → 显示 "Caelum"
- 思考链折叠图标 ⏳ → ✦，颜色 #B96747

## 颜色（已通过主题编辑器设置）
侧边栏背景和文字颜色已在"小杏"主题中配置，无需代码改动。

## 参考
- 图标源码：https://lib.amberrib.com/sidebar-icons-v2.html
- 字体对比：https://lib.amberrib.com/sidebar-fonts.html（选定C）

## 更新 · Jun 6

### 新增分组：群聊
- 位置：Projects 和 Almond 之间
- 图标：保留现有图标（多人+声波线条），不重新设计
- 颜色：统一 #3D3D38，与其他分组一致

### 当前分组列表（从上到下）
1. Chats — 现有图标
2. Projects — 现有图标
3. 群聊 — 现有图标（新增）
4. Almond — 杏仁轮廓（v2版去中线）
5. Amber — 六边形轮廓（v2版去切面线）

注：Chats/Projects/群聊 保留现有图标不改。仅 Almond/Amber 使用新设计的图标。
