/// JoyComic 动效 token。
///
/// 统一动画时长与曲线，避免散落魔法数字。曲线偏向 iOS 风格的
/// easeOut（进场）/ easeIn（退场）。
library app_motion;

import 'package:flutter/animation.dart';

class AppMotion {
  AppMotion._();

  /// 200ms — 微交互（按钮按压回弹、tag 选中）。
  static const Duration quick = Duration(milliseconds: 200);

  /// 300ms — 状态切换（展开/收起、tab 切换、底栏滑入）。
  static const Duration medium = Duration(milliseconds: 300);

  /// 400ms — 转场（页面 push/pop、沉浸头过渡）。
  static const Duration slow = Duration(milliseconds: 400);

  /// 100ms — 色相平滑过渡（动态取色注入时主题色过渡）。
  static const Duration colorShift = Duration(milliseconds: 100);

  /// 进场曲线（easeOut，先快后慢，元素落入）。
  static const Curve easeOut = Curves.easeOutCubic;

  /// 退场曲线（easeIn，先慢后快，元素退离）。
  static const Curve easeIn = Curves.easeInCubic;

  /// 标准曲线（多数 UI 状态用）。
  static const Curve standard = Curves.easeInOutCubic;

  /// 展开曲线（简介展开/收起，overshoot 微回弹更活泼）。
  static const Curve expand = Curves.easeOutBack;
}
