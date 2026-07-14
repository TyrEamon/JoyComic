/// JoyComic 间距栅格 token。
///
/// 全部基于 4 的倍数，保证视觉节奏统一。命名用语义而非数值，
/// 便于后续整体调栅格无需逐处改。
library;

class AppSpacing {
  AppSpacing._();

  /// 4 — 标签内边距、紧凑间距最小的负空间。
  static const double xxs = 4;

  /// 8 — 图标与文字间距、卡片内紧凑间距。
  static const double xs = 8;

  /// 12 — 卡片内常规间距、列表项垂直间距。
  static const double sm = 12;

  /// 16 — 页面水平边距、卡片内边距默认值。
  static const double md = 16;

  /// 20 — 区块标题与内容的纵向间距。
  static const double lg = 20;

  /// 24 — 大区块之间的纵向间距。
  static const double xl = 24;

  /// 32 — Hero 头部与内容主体的过渡间距。
  static const double xxl = 32;

  /// 48 — 页面顶部安全区之外的首屏留白。
  static const double xxxl = 48;

  /// 卡片内默认 padding。
  static const double cardPadding = md;

  /// 列表/网格项之间间距。
  static const double itemGap = sm;

  /// 大区块（详情页内 Synopsis / Chapter / Comment 之间）。
  static const double sectionGap = xxl;
}
