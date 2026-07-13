/// 微光胶囊标签（Pill Badge）。
///
/// 详情页"热度"徽标与列表页的精致小标签共用。设计要点：
/// - 真胶囊圆角（半径=高度/2）
/// - 半透明渐变底 + 微光晕阴影，营造发光感
/// - 可选前缀图标点（小圆点）
library pill_badge;

import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_radius.dart';
import '../app_shadows.dart';
import '../app_spacing.dart';

class PillBadge extends StatelessWidget {
  const PillBadge({
    super.key,
    required this.label,
    this.leadingDotColor,
    this.gradient = AppColors.brandGradient,
    this.backgroundColor,
    this.foregroundColor = Colors.white,
    this.style,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    this.glow = true,
  });

  /// 文本。
  final String label;

  /// 前缀小圆点颜色，null 则不显示。
  final Color? leadingDotColor;

  /// 渐变底；若同时给 [backgroundColor] 则优先用 backgroundColor。
  final Gradient? gradient;
  final Color? backgroundColor;

  final Color foregroundColor;
  final TextStyle? style;

  final EdgeInsetsGeometry padding;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      style: style ??
          const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: 0.4,
          ),
    );

    final content = Padding(
      padding: padding,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leadingDotColor != null) ...[
            _Dot(color: leadingDotColor!),
            const SizedBox(width: AppSpacing.xxs),
          ],
          text,
        ],
      ),
    );

    return Material(
      color: Colors.transparent,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: backgroundColor == null ? gradient : null,
          color: backgroundColor ?? const Color(0x33FFFFFF),
          borderRadius: AppRadius.pill(padding.vertical + 14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          boxShadow: glow ? AppShadows.pillGlow(gradient?.colors.first ?? AppColors.brandPink) : null,
        ),
        child: content,
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 4)],
      ),
    );
  }
}
