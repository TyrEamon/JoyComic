/// JoyComic 阴影 token。
///
/// 深色底上的阴影不能沿用 Material 默认黑色（会被背景吞没），
/// 故统一用"上抬光晕"（浅紫低透明）+ 前景实体的"下沉暗影"双系。
library;

import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppShadows {
  AppShadows._();

  /// 前景封面（详情页前层主体封面）的微暗影，强调立体实体感。
  static const List<BoxShadow> coverElevation = [
    BoxShadow(
      color: Color(0x66000000),
      blurRadius: 24,
      spreadRadius: -6,
      offset: Offset(0, 12),
    ),
    BoxShadow(
      color: Color(0x22B967FF),
      blurRadius: 40,
      spreadRadius: -12,
      offset: Offset(0, 8),
    ),
  ];

  /// 卡片（列表/网格/章节卡）下沿暗影。
  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x40000000),
      blurRadius: 12,
      spreadRadius: -4,
      offset: Offset(0, 4),
    ),
  ];

  /// 悬浮底栏上沿暗影 + 轻微品牌光晕，区分它与内容层。
  static const List<BoxShadow> actionBar = [
    BoxShadow(
      color: Color(0x55000000),
      blurRadius: 20,
      spreadRadius: -2,
      offset: Offset(0, -6),
    ),
  ];

  /// 胶囊标签（热度 pill）的微光晕，营造"发光感"。
  static List<BoxShadow> pillGlow(Color glowColor) => [
    BoxShadow(
      color: glowColor.withValues(alpha: 0.45),
      blurRadius: 12,
      spreadRadius: -2,
      offset: const Offset(0, 2),
    ),
  ];

  /// 品牌胶囊按钮的默认光晕（用于静态品牌色时段）。
  static List<BoxShadow> brandPillGlow() => pillGlow(AppColors.brandPink);
}
