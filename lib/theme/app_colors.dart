/// JoyComic 色板 token。
///
/// 全局骨架色（背景/卡片/文字层级/描边）恒定，不随漫画封面变化。
/// 详情页头部渐变 / 底栏主按钮 / 星级强调色则由 [PaletteExtractor] 从
/// 封面实时提取主色后注入（取色失败回退 [AppColors.brandPink] /
/// [AppColors.brandViolet] 渐变，故静态主色本身即兜底色）。
///
/// 设计取向：藕粉 → 紫罗兰的品牌渐变，搭配深墨紫黑底与暖紫黑面卡片，
/// 营造温暖高级、少女向但不甜腻的漫画阅读氛围。
library app_colors;

import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ============================ 品牌色（静态主调，取色兜底） ============================

  /// 藕粉，品牌渐变起点。
  static const Color brandPink = Color(0xFFFF7BA9);

  /// 紫罗兰，品牌渐变终点。
  static const Color brandViolet = Color(0xFFB967FF);

  /// 品牌主渐变（横向 藕粉 → 紫罗兰）。
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [brandPink, brandViolet],
  );

  /// 品牌主渐变（垂直，用于胶囊按钮等纵向容器）。
  static const LinearGradient brandGradientVertical = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [brandPink, brandViolet],
  );

  // ============================ 背景与表面 ============================

  /// 全局最底层背景（深墨紫黑）。
  static const Color background = Color(0xFF0E0B14);

  /// 卡片表面（暖紫黑面）。
  static const Color surface = Color(0xFF1B1622);

  /// 抬升表面（悬浮底栏、弹出层），比卡片略亮。
  static const Color surfaceElevated = Color(0xFF221A2B);

  /// 沉浸头通栏与详情内容区的过渡背景（比 background 略暖，便于渐变蒙版融入）。
  static const Color heroBase = Color(0xFF120E18);

  // ============================ 文字层级 ============================

  /// 主标题文字（近白，对深色底高对比）。
  static const Color textHigh = Color(0xFFF6F2F8);

  /// 副标题/正文文字（柔白）。
  static const Color textMedium = Color(0xFFC6BFD0);

  /// 辅助文字（元数据、时间戳）。
  static const Color textLow = Color(0xFF8A8298);

  /// 禁用态文字。
  static const Color textDisabled = Color(0xFF5A5466);

  // ============================ 语义色 ============================

  /// 评分星色（金黄）。
  static const Color ratingStar = Color(0xFFFFC83D);

  /// 热度/NEW 角标（取自品牌粉，与封面取色区分强调）。
  static const Color hotAccent = Color(0xFFFF6FA5);

  /// 成功（收藏已收藏态/登录成功）。
  static const Color success = Color(0xFF6FE0A8);

  /// 危险（删除/取消收藏）。
  static const Color danger = Color(0xFFFF6B6B);

  // ============================ 描边与分隔 ============================

  /// 卡片描边（极淡紫，营造立体边缘但不抢戏）。
  static const Color border = Color(0x14FFFFFF);

  /// 分隔线。
  static const Color divider = Color(0x0FFFFFFF);

  // ============================ 蒙版 ============================

  /// 沉浸头部底部渐变蒙版（heroBase 起始，向下融入 background）。
  static const LinearGradient heroBottomMask = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: [0.0, 0.45, 0.78, 1.0],
    colors: [
      Color(0x000E0B14),
      Color(0x660E0B14),
      Color(0xCC0E0B14),
      Color(0xFF0E0B14),
    ],
  );

  /// 沉浸头部从顶部向下的暗化蒙版（与状态栏融合，提升顶层导航图标可读性）。
  static const LinearGradient heroTopMask = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: [0.0, 0.35],
    colors: [Color(0x66000000), Color(0x00000000)],
  );

  // ============================ 亮色模式色值 ============================

  /// 亮色模式色板。
  static final ColorScheme lightScheme = ColorScheme.light(
    primary: brandPink,
    onPrimary: Colors.white,
    secondary: brandViolet,
    onSecondary: Colors.white,
    surface: const Color(0xFFFFF8F5),
    onSurface: const Color(0xFF2D2636),
    error: danger,
    onError: Colors.white,
  );

  /// 亮色背景（暖白）。
  static const Color lightBackground = Color(0xFFF5F0F8);

  /// 亮色卡片表面。
  static const Color lightSurface = Color(0xFFFFF8F5);

  /// 亮色抬升表面。
  static const Color lightSurfaceElevated = Color(0xFFFFFFFF);

  /// 亮色文字（深灰）。
  static const Color lightTextHigh = Color(0xFF2D2636);

  /// 亮色副文字。
  static const Color lightTextMedium = Color(0xFF6B6280);

  /// 亮色辅助文字。
  static const Color lightTextLow = Color(0xFF9A91AD);

  /// 亮色描边。
  static const Color lightBorder = Color(0x2D2D2636);

  /// 亮色分隔线。
  static const Color lightDivider = Color(0x122D2636);
}
