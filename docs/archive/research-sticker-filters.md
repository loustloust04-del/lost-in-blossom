# Research: 描边预览 + 贴纸滤镜

## 1. 描边预览

### 现状
Gallery 右键 → 修改描边 → 盲选样式 → 后台重新渲染 PNG。用户看不到效果就要选。

### 方案
弹一个预览 sheet，左边原图，右边 8 种描边效果的小预览网格。点选后应用。

或者更简单：右键子菜单每个描边样式旁边加小色条预览（纯色块示意）。

**推荐**：弹 sheet + 预览网格。每种描边用缩略图实时渲染预览（图小所以很快）。

## 2. 贴纸滤镜

### 概念
描边是贴纸的"边框"，滤镜是贴纸的"整体质感"。两个独立维度：
- 描边：none / solid_white / gradient_rainbow / laser / ...
- 滤镜：none / vintage / holographic / pixel / comic / glow / ...

### 滤镜列表（CoreImage 可实现）

| 滤镜 | 效果 | CIFilter |
|------|------|----------|
| none | 原图 | — |
| vintage | 复古做旧（暖色偏移 + 低饱和 + 噪点） | CISepiaTone + CIColorControls |
| holographic | 全息彩虹（色相偏移 + 对比增强） | CIHueAdjust + CIColorControls |
| pixel | 像素化 | CIPixellate |
| comic | 漫画/半调（黑白点阵） | CIComicEffect 或 CIDotScreen |
| glow | 梦幻发光（柔焦 + 亮度提升） | CIGloom 反向 或 CIBloom |
| sparkle | 星星闪光 | CIStarShineGenerator 叠加 |

先做 4 个简单的：vintage / holographic / pixel / comic

### 数据模型改动

StickerAsset 加 `filterStyle: String = "none"`

### 渲染流程

导入时：抠图 → 滤镜 → 描边 → 存 PNG
修改时：读原图/抠图 → 新滤镜 → 描边 → 重新存 PNG

滤镜在描边之前应用（滤镜改变图像内容，描边在外围）。

### 预览面板

一个 sheet，上半区选描边（8 种），下半区选滤镜（5 种）。
每个选项是缩略图网格，实时预览效果。
底部"应用"按钮。
