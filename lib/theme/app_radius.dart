/// JoyComic 圆角 token。
///
/// 统一圆角语言，避免散落硬编码。胶囊（pill）= 高/2 动态，
/// 其余按语义取值。
library;

import 'package:flutter/material.dart';

class AppRadius {
  AppRadius._();

  /// 8 — 小卡片、角标、胶囊尾的轻微圆角。
  static const double sm = 8;

  /// 12 — 标准卡片、输入框、章节封面图。
  static const double md = 12;

  /// 16 — 大卡片、面板、Sheet。
  static const double lg = 16;

  /// 24 — 沉浸头部前景封面、强调容器。
  static const double xl = 24;

  /// 32 — 特殊强调（悬浮底栏主按钮圆角长胶囊的另一端）。
  static const double xxl = 32;

  /// [BorderRadius] 快捷形态。
  static const BorderRadius brSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius brMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius brLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius brXl = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius brXxl = BorderRadius.all(Radius.circular(xxl));

  /// 胶囊圆角（传入高度，半径=高度/2 实现真胶囊）。
  static BorderRadius pill(double height) =>
      BorderRadius.all(Radius.circular(height / 2));
}
